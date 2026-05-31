"""Protocol version constant for App-Agent WebSocket communication.

Increment PROTOCOL_VERSION on breaking changes to message structure,
payload semantics, or envelope format. Non-breaking additions (new
message types, new optional payload fields) do not require a bump.

The version is exchanged during the auth handshake so both sides can
detect incompatibilities early.
"""

# Wire protocol version for MobileFlow App ↔ Agent communication.
# This is independent of the Python package version in pyproject.toml
# and the ACP protocol version negotiated with CLI agents.
PROTOCOL_VERSION: int = 1
