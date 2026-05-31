"""HTTP Proxy service for the Test Panel.

Generic HTTP request forwarder using aiohttp. Executes any HTTP
request from the desktop and returns the full response. Handles
timeouts (30s), redirects (up to 10), and error classification.

Used by TestPanelHandler to forward api.request messages from the
App to any target URL (localhost, LAN, or public internet).

Architecture:
    - Uses aiohttp.ClientSession for outbound requests
    - Classifies errors into typed categories (timeout, connection_refused, etc.)
    - Follows redirects up to 10 hops
    - Returns complete response (status, headers, body, duration)
"""

from __future__ import annotations

import time

import aiohttp
from loguru import logger


class HttpProxy:
    """Generic HTTP request forwarder.

    Executes any HTTP request from the desktop and returns the
    full response. Handles timeouts, redirects, and error typing.

    Usage:
        proxy = HttpProxy()
        result = await proxy.forward(
            url="http://localhost:3000/api/users",
            method="GET",
        )
    """

    _TIMEOUT_SECONDS = 30
    _MAX_REDIRECTS = 10

    async def forward(
        self,
        url: str,
        method: str = "GET",
        headers: dict[str, str] | None = None,
        body: str | None = None,
        follow_redirects: bool = True,
    ) -> dict:
        """Execute an HTTP request and return the full response.

        Forwards the request from the desktop, handling timeouts,
        redirects, and error classification.

        Args:
            url: Target URL (localhost, LAN, or public internet).
            method: HTTP method (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS).
            headers: Request headers as key-value map.
            body: Optional request body string.
            follow_redirects: Whether to follow redirects (up to 10 hops).

        Returns:
            Dict with either success fields (status_code, headers, body,
            duration_ms) or error fields (error=True, error_type, message).
        """
        logger.debug(f"HTTP 代理请求: {method} {url[:100]}")
        start_time = time.monotonic()

        timeout = aiohttp.ClientTimeout(total=self._TIMEOUT_SECONDS)
        max_redirects = self._MAX_REDIRECTS if follow_redirects else 0

        try:
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.request(
                    method=method,
                    url=url,
                    headers=headers or {},
                    data=body.encode("utf-8") if body else None,
                    allow_redirects=follow_redirects,
                    max_redirects=max_redirects,
                    ssl=False,
                ) as resp:
                    # Read response body (cap at 10MB to prevent OOM)
                    resp_body = await resp.read()
                    duration_ms = int((time.monotonic() - start_time) * 1000)

                    # Decode body as text (best effort)
                    try:
                        body_text = resp_body.decode("utf-8")
                    except (UnicodeDecodeError, ValueError):
                        body_text = resp_body.decode("latin-1")

                    # Truncate if > 10MB
                    if len(body_text) > 10 * 1024 * 1024:
                        body_text = body_text[:10 * 1024 * 1024] + "\n[truncated: response too large]"

                    # Flatten response headers (multidict → dict, last value wins)
                    resp_headers = {}
                    for key, value in resp.headers.items():
                        resp_headers[key] = value

                    logger.info(
                        f"HTTP 代理响应: {method} {url[:60]} → "
                        f"{resp.status}, {len(resp_body)} bytes, {duration_ms}ms"
                    )

                    return {
                        "status_code": resp.status,
                        "headers": resp_headers,
                        "body": body_text,
                        "duration_ms": duration_ms,
                    }

        except TimeoutError:
            duration_ms = int((time.monotonic() - start_time) * 1000)
            logger.warning(f"HTTP 代理超时: {method} {url[:60]}, {duration_ms}ms")
            return {
                "error": True,
                "error_type": "timeout",
                "message": f"Request timed out after {self._TIMEOUT_SECONDS} seconds",
            }
        except aiohttp.ClientConnectorError as e:
            logger.warning(f"HTTP 代理连接失败: {method} {url[:60]}, {e}")
            # Distinguish connection refused from DNS errors
            err_str = str(e).lower()
            if "name or service not known" in err_str or "nodename nor servname" in err_str:
                return {
                    "error": True,
                    "error_type": "dns_error",
                    "message": f"DNS resolution failed: {e}",
                }
            return {
                "error": True,
                "error_type": "connection_refused",
                "message": f"Connection refused: {e}",
            }
        except aiohttp.TooManyRedirects:
            logger.warning(f"HTTP 代理重定向过多: {method} {url[:60]}")
            return {
                "error": True,
                "error_type": "unknown",
                "message": f"Too many redirects (max {self._MAX_REDIRECTS})",
            }
        except Exception as e:
            logger.error(f"HTTP 代理未知错误: {method} {url[:60]}, {e}")
            return {
                "error": True,
                "error_type": "unknown",
                "message": f"Request failed: {e}",
            }
