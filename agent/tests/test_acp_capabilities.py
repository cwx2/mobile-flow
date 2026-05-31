"""
ACPProvider._parse_capabilities tests.

Verifies correct reading of SDK InitializeResponse into ProviderCapabilities.
"""

from __future__ import annotations

import pytest
from conftest import Obj

from mobileflow_agent.providers.acp_provider import ACPProvider


def _make_provider():
    p = ACPProvider.__new__(ACPProvider)
    p._display_name = "test-agent"
    return p


class TestParseCapabilities:
    def test_full_capabilities(self):
        p = _make_provider()
        result = Obj(
            agent_info=Obj(name="codex", title="Codex CLI", version="0.11.1"),
            agent_capabilities=Obj(
                load_session=True,
                prompt_capabilities=Obj(image=True, audio=False, embedded_context=False),
                mcp_capabilities=Obj(http=False, sse=False),
                session_capabilities=Obj(list=Obj(), close=None, fork=None, resume=None),
            ),
            auth_methods=[],
        )
        caps = p._parse_capabilities(result)
        assert caps.name == "Codex CLI"
        assert caps.version == "0.11.1"
        assert caps.supports_session_load is True
        assert caps.supports_session_list is True
        assert caps.supports_image is True
        assert caps.supports_audio is False

    def test_no_session_capabilities(self):
        p = _make_provider()
        result = Obj(
            agent_info=Obj(name="basic", title=None, version="1.0"),
            agent_capabilities=Obj(
                load_session=False, prompt_capabilities=None,
                mcp_capabilities=None, session_capabilities=None,
            ),
            auth_methods=[],
        )
        caps = p._parse_capabilities(result)
        assert caps.supports_session_list is False
        assert caps.supports_image is False
        assert caps.name == "basic"

    def test_null_capabilities(self):
        p = _make_provider()
        result = Obj(agent_info=None, agent_capabilities=None, auth_methods=None)
        caps = p._parse_capabilities(result)
        assert caps.supports_session_load is False
        assert caps.name == "test-agent"

    def test_auth_methods(self):
        p = _make_provider()
        result = Obj(
            agent_info=Obj(name="auth-agent", title=None, version="2.0"),
            agent_capabilities=Obj(
                load_session=False, prompt_capabilities=None,
                mcp_capabilities=None, session_capabilities=None,
            ),
            auth_methods=[Obj(id="api_key", name="API Key", description="Enter key")],
        )
        caps = p._parse_capabilities(result)
        assert len(caps.auth_methods) == 1
        assert caps.auth_methods[0]["id"] == "api_key"
