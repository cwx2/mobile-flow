"""Agent Web Dashboard — local management panel served on the WebSocket port.

Provides HTTP routes for the browser-based management UI:
  GET /              → Dashboard SPA (index.html)
  GET /api/status    → Agent status JSON
  GET /api/connect   → Connection info (IP, port, password, QR data)
  GET /api/cli/list  → CLI list with install status
  POST /api/cli/...  → CLI install/uninstall/test/detect operations
  GET /api/keys      → API key list (masked)
  POST /api/keys     → Save API key
  GET /api/settings  → Current settings
  POST /api/settings → Update settings

All routes are handled via websockets' process_request hook,
which intercepts HTTP requests before the WebSocket upgrade handshake.
"""
