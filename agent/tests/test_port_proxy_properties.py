"""Property-based tests for PortProxy correctness properties.

Verifies 8 universal correctness properties of the Preview Proxy system
using hypothesis-generated inputs. Each property tests a fundamental
invariant that must hold across all valid inputs:

1. Request preservation through proxy
2. URL rewriting completeness in text bodies
3. Content-type routing for rewriting
4. CORS headers present on all proxied responses
5. HTTPS interceptor echoes specific Origin
6. URL parsing round-trip via activate_url
7. Location header rewriting
8. Error response on unreachable target
"""

import asyncio
import sys
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from hypothesis import given, settings, assume
from hypothesis import strategies as st

sys.path.insert(0, "src")

from mobileflow_agent.services.port_proxy import PortProxy


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

# Valid HTTP methods supported by the proxy
http_methods = st.sampled_from(["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"])

# Path segments: alphanumeric + common URL chars, non-empty
path_segment = st.from_regex(r"[a-zA-Z0-9._~\-]{1,20}", fullmatch=True)

# Valid URL paths (no leading slash — proxy adds it)
url_paths = st.lists(path_segment, min_size=0, max_size=5).map("/".join)

# Query strings: key=value pairs
query_key = st.from_regex(r"[a-zA-Z_][a-zA-Z0-9_]{0,10}", fullmatch=True)
query_value = st.from_regex(r"[a-zA-Z0-9._~\-]{0,20}", fullmatch=True)
query_strings = st.lists(
    st.tuples(query_key, query_value), min_size=0, max_size=4
).map(lambda pairs: "&".join(f"{k}={v}" for k, v in pairs))

# Request bodies (bytes)
request_bodies = st.binary(min_size=0, max_size=200)

# Ports in valid range
valid_ports = st.integers(min_value=1, max_value=65535)

# Text content types that should trigger rewriting
text_content_types = st.sampled_from([
    "text/html",
    "text/html; charset=utf-8",
    "text/css",
    "text/plain",
    "text/javascript",
    "application/json",
    "application/json; charset=utf-8",
    "application/javascript",
    "application/xml",
    "application/xhtml+xml",
    "application/manifest+json",
    "application/ld+json",
])

# Binary content types that should NOT trigger rewriting
binary_content_types = st.sampled_from([
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
    "image/svg+xml",
    "font/woff2",
    "font/woff",
    "font/ttf",
    "application/wasm",
    "application/octet-stream",
    "video/mp4",
    "audio/mpeg",
    "application/zip",
    "application/pdf",
])

# Random text that does NOT contain "localhost" or port references
safe_text_chars = st.from_regex(r"[a-zA-Z0-9 \t\n<>{}()\[\]=;:'\",./!@#$%^&_+~`|-]{0,50}", fullmatch=True)

# Origin header values
origin_schemes = st.sampled_from(["http", "https"])
origin_hosts = st.from_regex(r"[a-z][a-z0-9\-]{1,15}\.[a-z]{2,4}", fullmatch=True)
origin_ports = st.one_of(
    st.just(""),
    valid_ports.map(lambda p: f":{p}"),
)
origins = st.builds(
    lambda scheme, host, port: f"{scheme}://{host}{port}",
    origin_schemes, origin_hosts, origin_ports,
)

# Hostnames for URL parsing tests
hostnames = st.from_regex(r"[a-z][a-z0-9\-]{1,15}(\.[a-z]{2,6}){1,2}", fullmatch=True)


# ---------------------------------------------------------------------------
# Property 1: Request preservation through proxy
# ---------------------------------------------------------------------------
# Feature: preview-proxy-improvement, Property 1: Request preservation through proxy

class TestProperty1RequestPreservation:
    """For any HTTP request with valid path, query string, method, and body,
    when forwarded through PortProxy, the target dev server SHALL receive
    the same path, query string, method, body, and correct Host header.
    """

    @pytest.mark.asyncio
    @settings(max_examples=100)
    @given(
        method=http_methods,
        path=url_paths,
        query=query_strings,
        body=request_bodies,
        port=st.integers(min_value=1024, max_value=65535),
    )
    async def test_property_1_request_preservation(
        self, method: str, path: str, query: str, body: bytes, port: int
    ):
        """**Validates: Requirements 1.2, 1.5, 1.6, 4.2, 5.1**"""
        # Set up proxy state manually to avoid HTTPS server startup overhead
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = port
        proxy._target_origin = f"http://localhost:{port}"
        proxy._target_host = f"localhost:{port}"
        proxy._target_scheme = "http"

        # Track what the mock session receives
        captured = {}

        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.reason = "OK"
        mock_response.headers = {"Content-Type": "text/plain"}
        mock_response.read = AsyncMock(return_value=b"OK")

        mock_context = AsyncMock()
        mock_context.__aenter__ = AsyncMock(return_value=mock_response)
        mock_context.__aexit__ = AsyncMock(return_value=False)

        def capture_request(**kwargs):
            """Regular function (not async) — aiohttp session.request()
            returns a context manager directly, not a coroutine."""
            captured["method"] = kwargs.get("method")
            captured["url"] = kwargs.get("url")
            captured["headers"] = kwargs.get("headers")
            captured["data"] = kwargs.get("data")
            return mock_context

        proxy._session = MagicMock()
        proxy._session.request = capture_request

        await proxy.proxy_request(
            path=path,
            method=method,
            headers={"Host": "original-host", "Accept": "text/html"},
            body=body if method in ("POST", "PUT", "PATCH") else None,
            query_string=query,
        )

        # Verify method preserved
        assert captured["method"] == method

        # Verify path preserved in URL
        expected_url = f"http://localhost:{port}/{path}"
        if query:
            expected_url += f"?{query}"
        assert captured["url"] == expected_url

        # Verify body preserved
        if method in ("POST", "PUT", "PATCH"):
            assert captured["data"] == body
        else:
            assert captured["data"] is None

        # Verify Host header is set to target host
        assert captured["headers"]["Host"] == f"localhost:{port}"


# ---------------------------------------------------------------------------
# Property 2: URL rewriting completeness in text bodies
# ---------------------------------------------------------------------------
# Feature: preview-proxy-improvement, Property 2: URL rewriting completeness in text bodies

class TestProperty2URLRewritingCompleteness:
    """For any text-based response body containing occurrences of
    localhost:{target_port} or the configured target host, _rewrite_body
    SHALL replace ALL occurrences, leaving zero original references.
    """

    @settings(max_examples=100)
    @given(
        num_occurrences=st.integers(min_value=1, max_value=10),
        prefix_texts=st.lists(safe_text_chars, min_size=1, max_size=11),
        port=st.integers(min_value=1024, max_value=65535),
    )
    def test_property_2_url_rewriting_completeness(
        self, num_occurrences: int, prefix_texts: list, port: int
    ):
        """**Validates: Requirements 2.1, 2.2, 3.3, 5.2**"""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = port
        proxy._target_origin = f"http://localhost:{port}"
        proxy._target_host = f"localhost:{port}"
        proxy._target_scheme = "http"

        # Build a body with multiple localhost:{port} occurrences
        parts = []
        for i in range(num_occurrences):
            text_idx = i % len(prefix_texts)
            parts.append(prefix_texts[text_idx])
            parts.append(f"http://localhost:{port}/path{i}")
        # Add trailing text
        parts.append(prefix_texts[0] if prefix_texts else "end")

        body_text = "".join(parts)
        body_bytes = body_text.encode("utf-8")
        headers = {"Content-Type": "text/html"}

        result = proxy._rewrite_body(body_bytes, headers)
        result_text = result.decode("utf-8")

        # Zero original references should remain
        assert f"localhost:{port}" not in result_text
        # Agent address should be present instead
        assert "192.168.1.100:9600" in result_text

    @settings(max_examples=100)
    @given(
        num_occurrences=st.integers(min_value=1, max_value=5),
        prefix_texts=st.lists(safe_text_chars, min_size=1, max_size=6),
        port=st.integers(min_value=1024, max_value=65535),
    )
    def test_property_2_custom_host_rewriting(
        self, num_occurrences: int, prefix_texts: list, port: int
    ):
        """Custom domain references are also fully rewritten."""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = port
        proxy._target_origin = f"https://de4.nmm.com:{port}"
        proxy._target_host = f"de4.nmm.com:{port}"
        proxy._target_scheme = "https"

        # Build body with custom host references
        parts = []
        for i in range(num_occurrences):
            text_idx = i % len(prefix_texts)
            parts.append(prefix_texts[text_idx])
            parts.append(f"https://de4.nmm.com:{port}/api/{i}")
        parts.append("end")

        body_text = "".join(parts)
        body_bytes = body_text.encode("utf-8")
        headers = {"Content-Type": "application/javascript"}

        result = proxy._rewrite_body(body_bytes, headers)
        result_text = result.decode("utf-8")

        # Zero custom host references should remain
        assert f"de4.nmm.com:{port}" not in result_text
        assert "192.168.1.100:9600" in result_text


# ---------------------------------------------------------------------------
# Property 3: Content-type routing for rewriting
# ---------------------------------------------------------------------------
# Feature: preview-proxy-improvement, Property 3: Content-type routing for rewriting

class TestProperty3ContentTypeRouting:
    """URL rewriting SHALL occur if and only if Content-Type is text-based.
    Binary types pass through unchanged.
    """

    @settings(max_examples=100)
    @given(content_type=text_content_types)
    def test_property_3_text_types_get_rewritten(self, content_type: str):
        """**Validates: Requirements 2.3, 2.4**"""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = 3000
        proxy._target_origin = "http://localhost:3000"
        proxy._target_host = "localhost:3000"
        proxy._target_scheme = "http"

        body = b"var url = 'http://localhost:3000/api';"
        headers = {"Content-Type": content_type}

        result = proxy._rewrite_body(body, headers)
        result_text = result.decode("utf-8")

        # Text types MUST be rewritten
        assert "localhost:3000" not in result_text
        assert "192.168.1.100:9600" in result_text

    @settings(max_examples=100)
    @given(content_type=binary_content_types)
    def test_property_3_binary_types_pass_through(self, content_type: str):
        """**Validates: Requirements 2.3, 2.4**"""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = 3000
        proxy._target_origin = "http://localhost:3000"
        proxy._target_host = "localhost:3000"
        proxy._target_scheme = "http"

        # Use binary-like content that happens to contain the port string
        body = b"http://localhost:3000/something"
        headers = {"Content-Type": content_type}

        result = proxy._rewrite_body(body, headers)

        # Binary types MUST pass through unchanged
        assert result == body


# ---------------------------------------------------------------------------
# Property 4: CORS headers present on all proxied responses
# ---------------------------------------------------------------------------
# Feature: preview-proxy-improvement, Property 4: CORS headers present on all proxied responses

class TestProperty4CORSHeaders:
    """For any response returned by proxy_request(), CORS headers SHALL
    be present.
    """

    @settings(max_examples=100)
    @given(
        extra_headers=st.dictionaries(
            keys=st.from_regex(r"X-[A-Za-z\-]{1,15}", fullmatch=True),
            values=st.from_regex(r"[a-zA-Z0-9 ]{1,30}", fullmatch=True),
            min_size=0,
            max_size=5,
        ),
    )
    def test_property_4_cors_headers_present(self, extra_headers: dict):
        """**Validates: Requirements 1.3**"""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)

        # Start with arbitrary headers
        headers = dict(extra_headers)
        headers["Content-Type"] = "text/html"

        result = proxy._add_cors_headers(headers)

        # CORS headers MUST be present
        assert "Access-Control-Allow-Origin" in result
        assert "Access-Control-Allow-Methods" in result
        assert "Access-Control-Allow-Headers" in result
        assert "Access-Control-Expose-Headers" in result

        # Values must be non-empty
        assert result["Access-Control-Allow-Origin"] == "*"
        assert "GET" in result["Access-Control-Allow-Methods"]
        assert "POST" in result["Access-Control-Allow-Methods"]

    @settings(max_examples=100)
    @given(
        extra_headers=st.dictionaries(
            keys=st.from_regex(r"X-[A-Za-z\-]{1,15}", fullmatch=True),
            values=st.from_regex(r"[a-zA-Z0-9 ]{1,30}", fullmatch=True),
            min_size=0,
            max_size=5,
        ),
    )
    def test_property_4_cors_does_not_remove_existing_headers(self, extra_headers: dict):
        """Adding CORS headers should not remove existing response headers."""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)

        headers = dict(extra_headers)
        result = proxy._add_cors_headers(headers)

        # All original headers should still be present
        for key, value in extra_headers.items():
            assert key in result
            assert result[key] == value


# ---------------------------------------------------------------------------
# Property 5: HTTPS interceptor echoes specific Origin
# ---------------------------------------------------------------------------
# Feature: preview-proxy-improvement, Property 5: HTTPS interceptor echoes specific Origin

class TestProperty5HTTPSOriginEcho:
    """For any request to the HTTPS interceptor with an Origin header,
    the response SHALL echo that exact Origin (not wildcard *).
    """

    @pytest.mark.asyncio
    @settings(max_examples=100)
    @given(origin=origins)
    async def test_property_5_https_origin_echo(self, origin: str):
        """**Validates: Requirements 4.3**"""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = 3000
        proxy._target_origin = "http://localhost:3000"
        proxy._target_host = "localhost:3000"
        proxy._target_scheme = "http"

        # Mock the aiohttp session for the HTTPS handler
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.headers = {"Content-Type": "text/plain"}
        mock_response.read = AsyncMock(return_value=b"OK")

        mock_context = AsyncMock()
        mock_context.__aenter__ = AsyncMock(return_value=mock_response)
        mock_context.__aexit__ = AsyncMock(return_value=False)

        mock_session = MagicMock()
        mock_session.request = MagicMock(return_value=mock_context)
        proxy._session = mock_session

        # Create a mock aiohttp.web.Request for the HTTPS handler
        mock_request = MagicMock()
        mock_request.match_info = {"path_info": "api/data"}
        mock_request.method = "GET"
        mock_request.headers = MagicMock()
        mock_request.headers.get = lambda key, default=None: {
            "Origin": origin,
            "Host": "192.168.1.100",
        }.get(key, default)
        mock_request.headers.items = lambda: [
            ("Origin", origin),
            ("Accept", "application/json"),
        ]
        mock_request.can_read_body = False
        mock_request.query_string = ""

        response = await proxy._handle_https_request(mock_request)

        # The response MUST echo the exact Origin
        assert response.headers["Access-Control-Allow-Origin"] == origin
        # Must include credentials support
        assert response.headers["Access-Control-Allow-Credentials"] == "true"
        # Must NOT be wildcard
        assert response.headers["Access-Control-Allow-Origin"] != "*"


# ---------------------------------------------------------------------------
# Property 6: URL parsing round-trip via activate_url
# ---------------------------------------------------------------------------
# Feature: preview-proxy-improvement, Property 6: URL parsing round-trip via activate_url

class TestProperty6URLParsingRoundTrip:
    """For any valid URL with scheme/host/port, activate_url() SHALL
    correctly parse and store scheme, host, and port.
    """

    @pytest.mark.asyncio
    @settings(max_examples=100)
    @given(
        scheme=st.sampled_from(["http", "https"]),
        host=hostnames,
        port=st.integers(min_value=1, max_value=65535),
    )
    async def test_property_6_url_parsing_round_trip(
        self, scheme: str, host: str, port: int
    ):
        """**Validates: Requirements 5.4**"""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        url = f"{scheme}://{host}:{port}"

        await proxy.activate_url(url)

        # Scheme must be correctly parsed
        assert proxy._target_scheme == scheme
        # Host (netloc) must include host:port
        assert proxy._target_host == f"{host}:{port}"
        # Port must be correctly extracted
        assert proxy._port == port
        # Reconstructing origin must produce the original
        reconstructed = f"{proxy._target_scheme}://{proxy._target_host}"
        assert reconstructed == url

        await proxy.deactivate()


# ---------------------------------------------------------------------------
# Property 7: Location header rewriting
# ---------------------------------------------------------------------------
# Feature: preview-proxy-improvement, Property 7: Location header rewriting

class TestProperty7LocationHeaderRewriting:
    """For any redirect response whose Location header contains
    localhost:{port}, _rewrite_headers SHALL rewrite all localhost references.
    """

    @settings(max_examples=100)
    @given(
        port=st.integers(min_value=1024, max_value=65535),
        path=url_paths,
        extra_headers=st.dictionaries(
            keys=st.from_regex(r"X-[A-Za-z\-]{1,15}", fullmatch=True),
            values=st.from_regex(r"[a-zA-Z0-9/. ]{1,30}", fullmatch=True),
            min_size=0,
            max_size=3,
        ),
    )
    def test_property_7_location_header_rewriting(
        self, port: int, path: str, extra_headers: dict
    ):
        """**Validates: Requirements 1.4**"""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = port
        proxy._target_origin = f"http://localhost:{port}"
        proxy._target_host = f"localhost:{port}"
        proxy._target_scheme = "http"

        headers = dict(extra_headers)
        headers["Location"] = f"http://localhost:{port}/{path}"
        headers["Content-Type"] = "text/html"

        result = proxy._rewrite_headers(headers)

        # Location header MUST NOT contain localhost:{port}
        assert f"localhost:{port}" not in result["Location"]
        # Must contain agent address instead
        assert "192.168.1.100:9600" in result["Location"]
        # Path must be preserved
        assert f"/{path}" in result["Location"]

    @settings(max_examples=100)
    @given(
        port=st.integers(min_value=1024, max_value=65535),
        path=url_paths,
    )
    def test_property_7_https_location_rewritten(self, port: int, path: str):
        """HTTPS Location headers are also rewritten to HTTP agent address."""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = port
        proxy._target_origin = f"https://localhost:{port}"
        proxy._target_host = f"localhost:{port}"
        proxy._target_scheme = "https"

        headers = {"Location": f"https://localhost:{port}/{path}"}

        result = proxy._rewrite_headers(headers)

        # Must be rewritten
        assert f"localhost:{port}" not in result["Location"]
        assert "192.168.1.100:9600" in result["Location"]

    @settings(max_examples=100)
    @given(
        port=st.integers(min_value=1024, max_value=65535),
        extra_headers=st.dictionaries(
            keys=st.from_regex(r"X-[A-Za-z\-]{1,15}", fullmatch=True),
            values=st.from_regex(r"[a-zA-Z0-9/. ]{1,30}", fullmatch=True),
            min_size=0,
            max_size=3,
        ),
    )
    def test_property_7_non_localhost_headers_unchanged(
        self, port: int, extra_headers: dict
    ):
        """Headers without localhost:{port} should pass through unchanged."""
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = port
        proxy._target_origin = f"http://localhost:{port}"
        proxy._target_host = f"localhost:{port}"
        proxy._target_scheme = "http"

        # No localhost references in these headers
        headers = dict(extra_headers)
        headers["Content-Type"] = "text/html"

        result = proxy._rewrite_headers(headers)

        # Non-localhost headers should be unchanged
        for key, value in headers.items():
            if f"localhost:{port}" not in value:
                assert result[key] == value


# ---------------------------------------------------------------------------
# Property 8: Error response on unreachable target
# ---------------------------------------------------------------------------
# Feature: preview-proxy-improvement, Property 8: Error response on unreachable target

class TestProperty8ErrorOnUnreachable:
    """When target is unreachable, proxy SHALL return HTTP 502."""

    @pytest.mark.asyncio
    @settings(max_examples=100)
    @given(
        method=http_methods,
        path=url_paths,
        query=query_strings,
    )
    async def test_property_8_error_on_unreachable(
        self, method: str, path: str, query: str
    ):
        """**Validates: Requirements 8.1**"""
        import aiohttp

        # Set up proxy state manually to avoid HTTPS server startup
        proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        proxy._port = 19999
        proxy._target_origin = "http://localhost:19999"
        proxy._target_host = "localhost:19999"
        proxy._target_scheme = "http"

        # Mock session to raise ClientConnectorError (target unreachable)
        connection_key = MagicMock()
        os_error = OSError("Connection refused")

        def raise_connector_error(**kwargs):
            raise aiohttp.ClientConnectorError(connection_key, os_error)

        mock_session = MagicMock()
        mock_session.request = raise_connector_error
        proxy._session = mock_session

        response = await proxy.proxy_request(
            path=path,
            method=method,
            query_string=query,
        )

        # Must return 502
        assert response.status_code == 502
        # Must have a human-readable body
        assert len(response.body) > 0
        body_text = response.body.decode("utf-8")
        assert "Cannot connect" in body_text or "Proxy error" in body_text
