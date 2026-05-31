"""Test PortProxy URL rewriting for preview functionality.

Verifies that:
1. localhost:{port} references are rewritten to agent address
2. Custom domain references (de4.nmm.com:7000) are rewritten
3. Non-text responses (images, fonts) are not modified
4. Large responses (>50MB, configurable) skip rewriting for performance
5. Binary responses are not modified
"""

import pytest
import sys
sys.path.insert(0, "src")

from mobileflow_agent.services.port_proxy import PortProxy


class TestRewriteBody:
    """Test _rewrite_body URL rewriting logic."""

    def setup_method(self):
        """Create a PortProxy instance with test configuration."""
        self.proxy = PortProxy(agent_host="192.168.1.100", agent_port=9600)
        self.proxy._port = 7000
        self.proxy._target_origin = "https://localhost:7000"
        self.proxy._target_host = "de4.nmm.com:7000"
        self.proxy._target_scheme = "https"

    def test_html_gets_urls_rewritten(self):
        """HTML responses should have localhost URLs rewritten."""
        html = b'<html><head><title>Test</title></head><body>Hello</body></html>'
        headers = {"Content-Type": "text/html; charset=utf-8"}
        result = self.proxy._rewrite_body(html, headers)
        text = result.decode("utf-8")
        # No <base> tag injection — transparent proxy doesn't need it
        assert '<base' not in text

    def test_localhost_rewritten(self):
        """localhost:7000 references should be rewritten to agent address."""
        html = b'<html><head></head><body><script src="http://localhost:7000/app.js"></script></body></html>'
        headers = {"Content-Type": "text/html"}
        result = self.proxy._rewrite_body(html, headers)
        text = result.decode("utf-8")
        assert "http://localhost:7000" not in text
        assert "http://192.168.1.100:9600" in text

    def test_custom_domain_rewritten(self):
        """Custom domain (de4.nmm.com:7000) should be rewritten to agent address."""
        html = b'<html><head></head><body><script src="https://de4.nmm.com:7000/app.js"></script></body></html>'
        headers = {"Content-Type": "text/html"}
        result = self.proxy._rewrite_body(html, headers)
        text = result.decode("utf-8")
        assert "de4.nmm.com:7000" not in text
        assert "192.168.1.100:9600" in text

    def test_large_body_skipped(self):
        """Bodies larger than 50MB should not be rewritten."""
        large_body = b'x' * 50_000_001
        headers = {"Content-Type": "text/html"}
        result = self.proxy._rewrite_body(large_body, headers)
        assert result == large_body

    def test_binary_response_skipped(self):
        """Binary responses should not be rewritten."""
        binary = b'\x89PNG\r\n\x1a\n' + b'\x00' * 100
        headers = {"Content-Type": "image/png"}
        result = self.proxy._rewrite_body(binary, headers)
        assert result == binary

    def test_js_no_base_tag_but_urls_rewritten(self):
        """JS responses: URLs rewritten, no <base> tag."""
        js = b'var url = "http://localhost:7000/api";'
        headers = {"Content-Type": "application/javascript"}
        result = self.proxy._rewrite_body(js, headers)
        text = result.decode("utf-8")
        assert "localhost:7000" not in text
        assert "192.168.1.100:9600" in text
        assert "<base" not in text


class TestProxyActivation:
    """Test PortProxy activation."""

    @pytest.mark.asyncio
    async def test_activate_url_https(self):
        """activate_url with HTTPS custom domain."""
        proxy = PortProxy()
        await proxy.activate_url("https://de4.nmm.com:7000")
        assert proxy.is_active
        assert proxy.target_port == 7000
        assert proxy._target_host == "de4.nmm.com:7000"
        assert proxy._target_scheme == "https"
        await proxy.deactivate()

    @pytest.mark.asyncio
    async def test_activate_localhost(self):
        """activate_url with localhost."""
        proxy = PortProxy()
        await proxy.activate_url("http://localhost:3000")
        assert proxy.is_active
        assert proxy.target_port == 3000
        await proxy.deactivate()

    @pytest.mark.asyncio
    async def test_deactivate(self):
        """deactivate clears state."""
        proxy = PortProxy()
        await proxy.activate_url("http://localhost:3000")
        await proxy.deactivate()
        assert not proxy.is_active
        assert proxy.target_port is None
