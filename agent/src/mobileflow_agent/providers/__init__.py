"""
Provider layer: unified AI Agent interaction interface.

ACP SDK types are re-exported here for convenience.
Direct import from acp.schema is preferred for new code.
"""

# Re-export commonly used SDK types
from acp.schema import (
    AgentCapabilities,
    SessionCapabilities,
    PromptCapabilities,
    McpCapabilities,
    ToolCallStart,
    ToolCallProgress,
    ToolCall,
    ToolCallLocation,
    AgentMessageChunk,
    AgentThoughtChunk,
    AgentPlanUpdate,
    PlanEntry,
    AvailableCommandsUpdate,
    AvailableCommand,
    CurrentModeUpdate,
    SessionInfoUpdate,
    SessionInfo,
    ListSessionsRequest,
    ListSessionsResponse,
    ConfigOptionUpdate,
)
