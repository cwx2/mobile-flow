"""Transparent HTTP reverse proxy for previewing dev servers on phone.

Forwards HTTP requests from the phone's WebView to any target URL
(localhost or remote) on the desktop. Framework-agnostic — it proxies
bytes, not semantics.

Integration point:
    Registered in dashboard_api.py's process_request handler. The
    dashboard handler extracts the HTTP method, body, and headers from
    the incoming WebSocket HTTP request, then delegates to
    proxy_request() which forwards to the configured target origin.

Architecture:
    - Uses aiohttp.ClientSession for outbound HTTP requests
    - Rewrites localhost:{port} and target-host references in response
      bodies and headers to the Agent's LAN-accessible address
    - Adds CORS headers to all proxied responses
    - Returns HTTP 502 when target is unreachable
    - HTTPS interceptor (port 443, best-effort) catches API requests
      that frontend JS sends using https:// + location.hostname
    - Configuration values (timeouts, thresholds, ports) are read from
      AgentConfig.preview when provided, with hardcoded fallbacks for
      backward compatibility in tests
"""

from __future__ import annotations

import ipaddress
from typing import TYPE_CHECKING

import aiohttp
import aiohttp.web
from loguru import logger
from websockets.datastructures import Headers
from websockets.http11 import Response

if TYPE_CHECKING:
    from ..core.config import AgentConfig


class PortProxy:
    """Reverse proxy for forwarding requests to a target URL.

    Integrates with the existing dashboard_api.py process_request hook
    to intercept /preview/* paths and forward them to the target.

    Supports full URLs (https://de4.nmm.com:7001) with correct Host
    header rewriting, not just localhost ports.

    Lifecycle:
        1. activate(port) or activate_url(url) — start proxying
        2. proxy_request() — forward individual HTTP requests
        3. deactivate() — stop proxying, close HTTP session

    Attributes:
        _port: Target port (extracted from URL or set directly).
        _target_origin: Full origin to proxy to (e.g. "https://de4.nmm.com:7001").
        _target_host: Host header value for the target.
        _target_scheme: "http" or "https".
        _session: aiohttp ClientSession for outbound requests.
        _agent_host: The Agent's LAN-accessible host address.
        _agent_port: The Agent's HTTP server port.
    """

    def __init__(
        self,
        agent_host: str = "0.0.0.0",
        agent_port: int = 9600,
        config: AgentConfig | None = None,
    ) -> None:
        self._port: int | None = None
        self._target_origin: str | None = None
        self._target_host: str | None = None
        self._target_scheme: str = "http"
        self._session: aiohttp.ClientSession | None = None
        self._agent_host = agent_host
        self._agent_port = agent_port
        self._config = config
        # HTTPS proxy server for intercepting API requests
        # that the frontend JS sends with https:// + location.hostname
        self._https_runner: aiohttp.web.AppRunner | None = None
        self._https_site: aiohttp.web.TCPSite | None = None

    @property
    def is_active(self) -> bool:
        """Whether the proxy is currently active."""
        return self._target_origin is not None

    @property
    def target_port(self) -> int | None:
        """The currently proxied target port, or None if inactive."""
        return self._port

    async def activate(self, port: int) -> None:
        """Start proxying to localhost:{port} (simple mode).

        Creates an aiohttp ClientSession for outbound requests.
        If already active, deactivates the previous session first.

        Args:
            port: Target localhost port number (1-65535).
        """
        await self.activate_url(f"http://localhost:{port}")

    async def activate_url(self, url: str) -> None:
        """Start proxying to a full target URL.

        Parses the URL to extract scheme, host, and port for correct
        request forwarding with proper Host header.

        Args:
            url: Full target URL (e.g. "https://de4.nmm.com:7001").
        """
        if self._target_origin is not None:
            logger.info(f"端口代理切换: {self._target_origin} → {url}")
            await self.deactivate()

        from urllib.parse import urlparse
        parsed = urlparse(url)
        self._target_scheme = parsed.scheme or "http"
        self._target_host = parsed.netloc or f"localhost:{parsed.port or 80}"
        self._port = parsed.port or (443 if self._target_scheme == "https" else 80)
        self._target_origin = f"{self._target_scheme}://{self._target_host}"

        self._session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(
                total=self._config.preview.proxy_request_timeout
                if self._config
                else 60
            ),
        )
        logger.info(f"端口代理已激活: {self._target_origin}")

        # Start HTTPS server on port 443 to intercept API requests
        # that frontend JS sends with https:// + location.hostname
        await self._start_https_server()

    async def deactivate(self) -> None:
        """Stop proxying and close the HTTP session.

        No-op if the proxy is not currently active.
        """
        await self._stop_https_server()
        if self._session:
            await self._session.close()
            self._session = None
        if self._target_origin is not None:
            logger.info(f"端口代理已停用: {self._target_origin}")
            self._target_origin = None
            self._target_host = None
            self._port = None

    async def _start_https_server(self) -> None:
        """Start an HTTPS server to intercept API requests (best-effort).

        Frontend JS often constructs API URLs using https:// + location.hostname,
        which hits port 443 directly (bypassing our HTTP proxy on 9600).
        This server catches those requests and forwards them to the dev server.

        Uses a self-signed certificate generated on-the-fly. WebView will
        accept it since we're on a local network.

        Platform limitation (Android WebView):
            Android WebView's onReceivedServerTrustAuthRequest callback only
            applies to page-level navigation (top-level document loads), NOT
            to XHR/fetch sub-resource requests. This means:
            - Page loads to self-signed HTTPS: works (WebView shows trust dialog)
            - XHR/fetch to self-signed HTTPS: fails with net_error -202
              (ERR_CERT_AUTHORITY_INVALID), no callback is triggered
            This is a platform limitation, not a bug in our implementation.
            The HTTPS interceptor is therefore best-effort: it works in mobile
            browsers (Chrome, Safari) but NOT in WebView for XHR/fetch requests.
        """
        import ssl
        try:
            ssl_ctx = self._create_self_signed_ssl_context()
        except Exception as e:
            logger.warning(f"HTTPS 代理服务器启动失败（无法生成证书）: {e}")
            return

        app = aiohttp.web.Application()
        app.router.add_route("*", "/{path_info:.*}", self._handle_https_request)

        self._https_runner = aiohttp.web.AppRunner(app)
        await self._https_runner.setup()

        # Port is configurable via config.preview.https_interceptor_port
        https_port = (
            self._config.preview.https_interceptor_port
            if self._config
            else 443
        )

        try:
            self._https_site = aiohttp.web.TCPSite(
                self._https_runner,
                host="0.0.0.0",
                port=https_port,
                ssl_context=ssl_ctx,
            )
            await self._https_site.start()
            logger.info(f"HTTPS 代理服务器已启动: https://0.0.0.0:{https_port}")
        except OSError as e:
            # Port may require admin privileges or be in use
            logger.warning(f"HTTPS 代理服务器启动失败（端口 {https_port} 不可用）: {e}")
            await self._https_runner.cleanup()
            self._https_runner = None
            self._https_site = None

    async def _stop_https_server(self) -> None:
        """Stop the HTTPS proxy server if running."""
        if self._https_site:
            await self._https_site.stop()
            self._https_site = None
        if self._https_runner:
            await self._https_runner.cleanup()
            self._https_runner = None
            logger.info("HTTPS 代理服务器已停止")

    async def _handle_https_request(self, request: aiohttp.web.Request) -> aiohttp.web.Response:
        """Handle incoming HTTPS requests and forward to dev server.

        This is the aiohttp handler for the 443 port server. It forwards
        all requests to the dev server using the same logic as proxy_request.
        """
        if not self.is_active or not self._session:
            return aiohttp.web.Response(status=502, text="Preview not active")

        path = request.match_info.get("path_info", "")
        method = request.method
        logger.info(f"[HTTPS:443] 收到请求: {method} /{path}")

        # Handle CORS preflight (OPTIONS) immediately
        if method == "OPTIONS":
            request_origin = request.headers.get("Origin", f"http://{self._agent_host}:{self._agent_port}")
            return aiohttp.web.Response(
                status=204,
                headers={
                    "Access-Control-Allow-Origin": request_origin,
                    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD",
                    "Access-Control-Allow-Headers": request.headers.get("Access-Control-Request-Headers", "*"),
                    "Access-Control-Allow-Credentials": "true",
                    "Access-Control-Max-Age": "86400",
                },
            )

        body = await request.read() if request.can_read_body else None
        query_string = request.query_string

        # Build target URL
        import ssl as ssl_mod
        target_url = f"{self._target_scheme}://localhost:{self._port}/{path}"
        if query_string:
            target_url += f"?{query_string}"

        # Forward headers with correct Host
        forward_headers = {}
        for key, value in request.headers.items():
            lower_key = key.lower()
            if lower_key in ("host", "transfer-encoding", "connection", "upgrade"):
                continue
            forward_headers[key] = value
        forward_headers["Host"] = self._target_host or f"localhost:{self._port}"

        # SSL context for HTTPS targets
        ssl_ctx = None
        if self._target_scheme == "https":
            ssl_ctx = ssl_mod.create_default_context()
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl_mod.CERT_NONE

        try:
            async with self._session.request(
                method=method,
                url=target_url,
                headers=forward_headers,
                data=body,
                allow_redirects=False,
                ssl=ssl_ctx,
            ) as resp:
                resp_body = await resp.read()
                resp_headers = dict(resp.headers)

                # Add CORS headers — must use specific origin (not *)
                # when request includes credentials (cookies)
                request_origin = request.headers.get("Origin", f"http://{self._agent_host}:{self._agent_port}")
                resp_headers["Access-Control-Allow-Origin"] = request_origin
                resp_headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD"
                resp_headers["Access-Control-Allow-Headers"] = "*"
                resp_headers["Access-Control-Allow-Credentials"] = "true"
                resp_headers["Access-Control-Expose-Headers"] = "*"

                # Remove hop-by-hop headers
                for h in ("transfer-encoding", "connection", "keep-alive"):
                    resp_headers.pop(h, None)
                    # Also try capitalized
                    resp_headers.pop(h.title(), None)

                return aiohttp.web.Response(
                    status=resp.status,
                    body=resp_body,
                    headers=resp_headers,
                )
        except Exception as e:
            logger.warning(f"HTTPS 代理请求失败: {method} /{path}, error={e}")
            return aiohttp.web.Response(status=502, text=f"Proxy error: {e}")

    def _create_self_signed_ssl_context(self) -> "ssl.SSLContext":
        """Create an SSL context with a self-signed certificate.

        Generates a temporary self-signed cert valid for 1 year.
        The cert is created in memory and not persisted to disk.

        Returns:
            An ssl.SSLContext configured with the self-signed cert.
        """
        import ssl
        import tempfile
        import os

        try:
            from cryptography import x509
            from cryptography.x509.oid import NameOID
            from cryptography.hazmat.primitives import hashes, serialization
            from cryptography.hazmat.primitives.asymmetric import rsa
            import datetime

            # Generate key
            key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

            # Generate cert
            subject = issuer = x509.Name([
                x509.NameAttribute(NameOID.COMMON_NAME, "MobileFlow Agent"),
            ])
            cert = (
                x509.CertificateBuilder()
                .subject_name(subject)
                .issuer_name(issuer)
                .public_key(key.public_key())
                .serial_number(x509.random_serial_number())
                .not_valid_before(datetime.datetime.now(datetime.timezone.utc))
                .not_valid_after(datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=365))
                .add_extension(
                    x509.SubjectAlternativeName([
                        x509.DNSName("localhost"),
                        x509.IPAddress(ipaddress.IPv4Address("127.0.0.1")),
                        x509.IPAddress(ipaddress.IPv4Address(self._agent_host) if self._agent_host != "0.0.0.0" else ipaddress.IPv4Address("127.0.0.1")),
                    ]),
                    critical=False,
                )
                .sign(key, hashes.SHA256())
            )

            # Write to temp files for ssl context
            cert_pem = cert.public_bytes(serialization.Encoding.PEM)
            key_pem = key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.TraditionalOpenSSL,
                serialization.NoEncryption(),
            )

            cert_file = tempfile.NamedTemporaryFile(delete=False, suffix=".pem")
            cert_file.write(cert_pem)
            cert_file.close()

            key_file = tempfile.NamedTemporaryFile(delete=False, suffix=".pem")
            key_file.write(key_pem)
            key_file.close()

            ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ssl_ctx.load_cert_chain(cert_file.name, key_file.name)

            # Clean up temp files
            os.unlink(cert_file.name)
            os.unlink(key_file.name)

            return ssl_ctx

        except ImportError:
            # cryptography package not available — use openssl command
            logger.warning("cryptography 包未安装，尝试用 openssl 生成证书")
            import subprocess
            cert_file = tempfile.NamedTemporaryFile(delete=False, suffix=".pem")
            key_file = tempfile.NamedTemporaryFile(delete=False, suffix=".pem")
            cert_file.close()
            key_file.close()

            subprocess.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-keyout", key_file.name, "-out", cert_file.name,
                "-days", "365", "-nodes",
                "-subj", "/CN=MobileFlow Agent",
            ], check=True, capture_output=True)

            ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ssl_ctx.load_cert_chain(cert_file.name, key_file.name)

            os.unlink(cert_file.name)
            os.unlink(key_file.name)

            return ssl_ctx

    async def proxy_request(
        self,
        path: str,
        method: str = "GET",
        headers: dict[str, str] | None = None,
        body: bytes | None = None,
        query_string: str = "",
    ) -> Response:
        """Forward an HTTP request to the configured target origin.

        Uses the full target URL (scheme + host + port) configured via
        activate_url(). Sets the correct Host header for the target server.
        Skips SSL certificate verification for local dev servers.

        Args:
            path: Request path relative to /preview/ (e.g. "index.html").
            method: HTTP method (GET, POST, PUT, etc.).
            headers: Request headers to forward. Host header is rewritten.
            body: Request body bytes (for POST/PUT/PATCH).
            query_string: Raw query string (without leading '?').

        Returns:
            A websockets Response with the proxied content, CORS headers,
            and rewritten URLs.
        """
        if not self.is_active or not self._session:
            return self._error_response(502, "Preview not active")

        # Build target URL: always connect to localhost:{port} for reliability,
        # but set the Host header to the configured target host.
        # This avoids DNS/SNI issues while satisfying host-based routing.
        target_url = f"{self._target_scheme}://localhost:{self._port}/{path}"
        if query_string:
            target_url += f"?{query_string}"

        # Filter and forward headers, set correct Host for target
        forward_headers = self._filter_request_headers(headers or {})

        # SSL context for HTTPS targets (skip cert verification for dev servers)
        ssl_ctx = None
        if self._target_scheme == "https":
            import ssl
            ssl_ctx = ssl.create_default_context()
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl.CERT_NONE

        try:
            logger.debug(f"代理请求: {method} {target_url}, Host={self._target_host}")
            async with self._session.request(
                method=method,
                url=target_url,
                headers=forward_headers,
                data=body,
                allow_redirects=False,
                ssl=ssl_ctx,
            ) as resp:
                resp_body = await resp.read()
                resp_headers = dict(resp.headers)
                logger.debug(f"代理响应: status={resp.status}, body_len={len(resp_body)}")

                # Warn on server errors from target
                if resp.status >= 500:
                    logger.warning(
                        f"目标服务器返回错误: status={resp.status}, "
                        f"path={path}, url={target_url}"
                    )

                resp_body = self._rewrite_body(resp_body, resp_headers)
                resp_headers = self._rewrite_headers(resp_headers)
                resp_headers = self._add_cors_headers(resp_headers)

                ws_headers = Headers()
                for key, value in resp_headers.items():
                    lower_key = key.lower()
                    if lower_key in _HOP_BY_HOP_RESPONSE:
                        continue
                    # Skip original Content-Length — we set the correct
                    # value below after body rewriting
                    if lower_key == "content-length":
                        continue
                    ws_headers[key] = value
                ws_headers["Content-Length"] = str(len(resp_body))

                reason = resp.reason or "OK"
                return Response(resp.status, reason, ws_headers, resp_body)

        except aiohttp.ClientConnectorError as e:
            logger.warning(f"代理连接失败: {self._target_origin} ({e})")
            return self._error_response(502, f"Cannot connect to {self._target_origin}")
        except aiohttp.ClientError as e:
            logger.error(f"代理请求失败: {e}")
            return self._error_response(502, f"Proxy error: {e}")
        except Exception as e:
            logger.error(f"代理未知错误: {e}")
            return self._error_response(502, f"Unexpected proxy error: {e}")

    def set_agent_address(self, host: str, port: int) -> None:
        """Update the Agent accessible address for URL rewriting.

        Called when the Agent network configuration changes (e.g.
        LAN IP detection on startup).

        Args:
            host: Agent LAN-accessible IP address.
            port: Agent HTTP server port.
        """
        self._agent_host = host
        self._agent_port = port

    def _filter_request_headers(self, headers: dict[str, str]) -> dict[str, str]:
        """Filter request headers, removing hop-by-hop headers.

        Rewrites the Host header to the target server host.

        Args:
            headers: Original request headers.

        Returns:
            Filtered headers suitable for forwarding.
        """
        filtered = {}
        for key, value in headers.items():
            lower_key = key.lower()
            if lower_key in _HOP_BY_HOP_REQUEST:
                continue
            if lower_key == "host":
                # Rewrite Host to target server's host
                filtered[key] = self._target_host or f"localhost:{self._port}"
                continue
            filtered[key] = value
        return filtered

    def _rewrite_body(self, body: bytes, headers: dict[str, str]) -> bytes:
        """Rewrite localhost:{port} references in response body.

        Only rewrites text-based content types (text/*, application/json,
        application/javascript, etc.) to avoid corrupting binary data.
        Skips bodies larger than the configured threshold (default 50MB,
        configurable via config.preview.max_rewrite_body_size_mb) to avoid
        performance degradation on extremely large files.

        Args:
            body: Raw response body bytes.
            headers: Response headers (used to check Content-Type).

        Returns:
            Body with localhost references rewritten, or original if binary/large.
        """
        content_type = headers.get("Content-Type", headers.get("content-type", ""))
        if not self._is_text_content(content_type):
            return body

        # Skip rewrite for bodies exceeding the configured threshold to avoid
        # performance issues with extremely large files. Most JS bundles (even
        # 26MB) need URL rewriting to work correctly through the proxy.
        max_body_size = (
            self._config.preview.max_rewrite_body_size_mb * 1_000_000
            if self._config
            else 50_000_000
        )
        if len(body) > max_body_size:
            return body

        try:
            text = body.decode("utf-8")
        except (UnicodeDecodeError, ValueError):
            return body

        # Replace localhost:{port} with agent address
        agent_base = f"{self._agent_host}:{self._agent_port}"
        # Match various forms: http://localhost:{port}, //localhost:{port}, localhost:{port}
        patterns = [
            (f"http://localhost:{self._port}", f"http://{agent_base}"),
            (f"https://localhost:{self._port}", f"http://{agent_base}"),
            (f"//localhost:{self._port}", f"//{agent_base}"),
            (f"localhost:{self._port}", f"{agent_base}"),
        ]

        # Also replace the target host if it's not localhost
        # (e.g. de4.nmm.com:7000 → agent address)
        if self._target_host and self._target_host != f"localhost:{self._port}":
            target_host = self._target_host
            scheme = self._target_scheme or "http"
            patterns.extend([
                (f"{scheme}://{target_host}", f"http://{agent_base}"),
                (f"//{target_host}", f"//{agent_base}"),
                (f"{target_host}", f"{agent_base}"),
            ])

        for old, new in patterns:
            text = text.replace(old, new)

        return text.encode("utf-8")

    def _rewrite_headers(self, headers: dict[str, str]) -> dict[str, str]:
        """Rewrite localhost:{port} references in response headers.

        Primarily targets Location headers for redirects.

        Args:
            headers: Original response headers.

        Returns:
            Headers with localhost references rewritten.
        """
        rewritten = {}
        for key, value in headers.items():
            if f"localhost:{self._port}" in value:
                agent_base = f"{self._agent_host}:{self._agent_port}"
                value = value.replace(
                    f"http://localhost:{self._port}",
                    f"http://{agent_base}",
                )
                value = value.replace(
                    f"https://localhost:{self._port}",
                    f"http://{agent_base}",
                )
                value = value.replace(
                    f"localhost:{self._port}",
                    agent_base,
                )
            rewritten[key] = value
        return rewritten

    def _add_cors_headers(self, headers: dict[str, str]) -> dict[str, str]:
        """Add CORS headers to the response.

        Ensures the proxied response is accessible from any origin,
        which is necessary for the phone WebView to load content.

        Args:
            headers: Response headers to augment.

        Returns:
            Headers with CORS headers added/overwritten.
        """
        headers["Access-Control-Allow-Origin"] = "*"
        headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD"
        headers["Access-Control-Allow-Headers"] = "*"
        headers["Access-Control-Expose-Headers"] = "*"
        return headers

    def _is_text_content(self, content_type: str) -> bool:
        """Check if a Content-Type indicates text-based content.

        Args:
            content_type: The Content-Type header value.

        Returns:
            True if the content is text-based and safe to rewrite.
        """
        text_types = (
            "text/",
            "application/json",
            "application/javascript",
            "application/xml",
            "application/xhtml",
            "application/manifest",
            "application/ld+json",
        )
        lower = content_type.lower()
        return any(lower.startswith(t) or t in lower for t in text_types)

    def _error_response(self, status: int, message: str) -> Response:
        """Build an error HTTP response.

        Args:
            status: HTTP status code.
            message: Human-readable error message.

        Returns:
            A websockets Response with the error.
        """
        body = message.encode("utf-8")
        headers = Headers()
        headers["Content-Type"] = "text/plain; charset=utf-8"
        headers["Content-Length"] = str(len(body))
        headers["Access-Control-Allow-Origin"] = "*"
        reason = "Bad Gateway" if status == 502 else "Error"
        return Response(status, reason, headers, body)


# Hop-by-hop headers that should not be forwarded
_HOP_BY_HOP_REQUEST: frozenset[str] = frozenset({
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
})

_HOP_BY_HOP_RESPONSE: frozenset[str] = frozenset({
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
})
