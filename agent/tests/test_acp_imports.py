"""
ACP SDK import completeness tests.

Verifies all required types can be imported from the SDK and local wrappers.
"""

import pytest


_SDK_TYPES = [
    ("acp.schema", "AgentCapabilities"),
    ("acp.schema", "SessionCapabilities"),
    ("acp.schema", "ToolCallStart"),
    ("acp.schema", "ToolCallProgress"),
    ("acp.schema", "AgentMessageChunk"),
    ("acp.schema", "SessionInfoUpdate"),
    ("acp.schema", "ListSessionsResponse"),
    ("acp.schema", "ConfigOptionUpdate"),
    ("mobileflow_agent.providers", "AgentCapabilities"),
    ("mobileflow_agent.providers.acp_converter", "ACPEventConverter"),
    ("mobileflow_agent.providers.base", "AgentEvent"),
]


@pytest.mark.parametrize("mod,name", _SDK_TYPES, ids=[f"{m}.{n}" for m, n in _SDK_TYPES])
def test_sdk_import(mod, name):
    m = __import__(mod, fromlist=[name])
    assert hasattr(m, name), f"{name} not found in {mod}"
