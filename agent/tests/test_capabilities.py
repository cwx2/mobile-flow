"""
Capability system tests.

Covers: ProviderCapabilities.to_capability_dict, _build_prompt_blocks,
CLIInfo capability fields, _parse_capabilities with _get helper,
protocol_version check, auth_required lifecycle state.
"""

from __future__ import annotations

import base64

import pytest
from conftest import Obj

from mobileflow_agent.providers.base import (
    ProviderCapabilities,
    ProviderLifecycleState,
)
from mobileflow_agent.providers.acp_provider import ACPProvider
from mobileflow_protocol.models import CLIInfo


class TestProviderCapabilitiesToDict:
    def test_all_fields_present(self):
        caps = ProviderCapabilities(
            supports_session_load=True,
            supports_image=True,
            supports_audio=False,
            supports_embedded_context=True,
            supports_session_list=True,
            supports_session_close=False,
            supports_session_fork=False,
            supports_session_resume=False,
            supports_mcp_http=True,
            supports_mcp_sse=False,
            available_modes=[{"id": "code", "name": "Code"}],
        )
        d = caps.to_capability_dict()
        assert d["supports_image"] is True
        assert d["supports_audio"] is False
        assert d["supports_embedded_context"] is True
        assert d["supports_session_list"] is True
        assert d["supports_mcp_http"] is True
        assert d["supports_mcp_sse"] is False
        assert len(d["available_modes"]) == 1

    def test_defaults_all_false(self):
        d = ProviderCapabilities().to_capability_dict()
        assert d["supports_image"] is False
        assert d["supports_audio"] is False
        assert d["supports_session_load"] is False
        assert d["available_modes"] == []


class TestCLIInfoCapabilities:
    def test_default_capabilities(self):
        info = CLIInfo(name="test", display_name="Test", installed=True)
        assert info.supports_image is False
        assert info.supports_audio is False
        assert info.supports_session_load is False
        assert info.supports_mcp_http is False
        assert info.available_modes == []

    def test_with_capabilities(self):
        info = CLIInfo(
            name="claude", display_name="Claude", installed=True,
            supports_image=True, supports_embedded_context=True,
            supports_session_list=True,
            available_modes=[{"id": "ask", "name": "Ask"}],
        )
        assert info.supports_image is True
        assert info.supports_embedded_context is True
        assert info.supports_session_list is True
        assert len(info.available_modes) == 1

    def test_serialization_roundtrip(self):
        info = CLIInfo(
            name="test", display_name="Test", installed=True,
            supports_image=True, supports_audio=True,
        )
        d = info.model_dump()
        restored = CLIInfo(**d)
        assert restored.supports_image is True
        assert restored.supports_audio is True


class TestParseCapabilities:
    def _make_provider(self):
        p = ACPProvider.__new__(ACPProvider)
        p._display_name = "test-agent"
        return p

    def test_protocol_version_stored(self):
        p = self._make_provider()
        result = Obj(
            protocol_version=1,
            agent_info=Obj(name="test", title=None, version="1.0"),
            agent_capabilities=None,
            auth_methods=[],
        )
        caps = p._parse_capabilities(result)
        assert caps.protocol_version == 1

    def test_protocol_version_default(self):
        p = self._make_provider()
        result = Obj(
            protocol_version=None,
            agent_info=None,
            agent_capabilities=None,
            auth_methods=None,
        )
        caps = p._parse_capabilities(result)
        assert caps.protocol_version == 1

    def test_nested_get_helper(self):
        """_get helper reads nested attributes safely."""
        p = self._make_provider()
        result = Obj(
            protocol_version=1,
            agent_info=Obj(name="nested", title=None, version="1.0"),
            agent_capabilities=Obj(
                load_session=True,
                prompt_capabilities=Obj(image=True, audio=False, embedded_context=True),
                session_capabilities=Obj(list=Obj(), close=None, fork=None, resume=None),
                mcp_capabilities=Obj(http=True, sse=False),
            ),
            auth_methods=[],
        )
        caps = p._parse_capabilities(result)
        assert caps.supports_session_load is True
        assert caps.supports_image is True
        assert caps.supports_audio is False
        assert caps.supports_embedded_context is True
        assert caps.supports_session_list is True
        assert caps.supports_session_close is False
        assert caps.supports_mcp_http is True

    def test_auth_methods_env_var(self):
        """EnvVarAuthMethod parsed with vars and link."""
        p = self._make_provider()
        result = Obj(
            protocol_version=1,
            agent_info=Obj(name="auth", title=None, version="1.0"),
            agent_capabilities=None,
            auth_methods=[Obj(
                id="env_key", name="API Key", type="env_var",
                description="Enter your key",
                link="https://example.com/keys",
                vars=[
                    Obj(name="API_KEY", label="API Key", secret=True, optional=False),
                    Obj(name="ORG_ID", label="Org ID", secret=False, optional=True),
                ],
            )],
        )
        caps = p._parse_capabilities(result)
        assert len(caps.auth_methods) == 1
        m = caps.auth_methods[0]
        assert m["id"] == "env_key"
        assert m["type"] == "env_var"
        assert m["link"] == "https://example.com/keys"
        assert len(m["vars"]) == 2
        assert m["vars"][0]["name"] == "API_KEY"
        assert m["vars"][0]["secret"] is True
        assert m["vars"][1]["optional"] is True


class TestBuildPromptBlocks:
    def _make_provider(self):
        p = ACPProvider.__new__(ACPProvider)
        p._display_name = "test"
        return p

    def test_text_only(self):
        p = self._make_provider()
        blocks = p._build_prompt_blocks("hello", None, None, None)
        assert len(blocks) == 1

    def test_with_image(self):
        p = self._make_provider()
        img_data = b"\x89PNG\r\n\x1a\n"
        blocks = p._build_prompt_blocks("look", [{"data": img_data, "mime_type": "image/png"}], None, None)
        assert len(blocks) == 2

    def test_image_mime_type_preserved(self):
        p = self._make_provider()
        blocks = p._build_prompt_blocks("", [{"data": b"jpg", "mime_type": "image/jpeg"}], None, None)
        img_block = blocks[1]
        assert img_block.mime_type == "image/jpeg"

    def test_with_audio(self):
        p = self._make_provider()
        blocks = p._build_prompt_blocks("listen", None, [{"data": b"wav", "mime_type": "audio/wav"}], None)
        assert len(blocks) == 2
        assert blocks[1].type == "audio"
        assert blocks[1].mime_type == "audio/wav"

    def test_with_resource(self):
        p = self._make_provider()
        blocks = p._build_prompt_blocks("read", None, None, [
            {"type": "resource", "uri": "file:///main.py", "content": "print('hi')", "mime_type": "text/python"},
        ])
        assert len(blocks) == 2
        assert blocks[1].type == "resource"
        assert blocks[1].resource.uri == "file:///main.py"
        assert blocks[1].resource.text == "print('hi')"

    def test_with_resource_link(self):
        p = self._make_provider()
        blocks = p._build_prompt_blocks("see", None, None, [
            {"type": "resource_link", "uri": "file:///doc.pdf", "name": "doc.pdf", "mime_type": "application/pdf"},
        ])
        assert len(blocks) == 2
        assert blocks[1].type == "resource_link"
        assert blocks[1].uri == "file:///doc.pdf"
        assert blocks[1].name == "doc.pdf"

    def test_all_types_combined(self):
        p = self._make_provider()
        blocks = p._build_prompt_blocks(
            "analyze",
            [{"data": b"img", "mime_type": "image/png"}],
            [{"data": b"aud", "mime_type": "audio/mp3"}],
            [{"type": "resource_link", "uri": "file:///a.py", "name": "a.py", "mime_type": ""}],
        )
        # text + image + audio + resource_link = 4
        assert len(blocks) == 4


class TestAuthRequiredState:
    def test_enum_value(self):
        assert ProviderLifecycleState.AUTH_REQUIRED.value == "auth_required"

    def test_enum_count(self):
        assert len(list(ProviderLifecycleState)) == 6
