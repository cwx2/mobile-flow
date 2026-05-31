"""MobileFlow Relay Server entry point.

Starts the FastAPI-based relay server with WebSocket forwarding,
Ed25519 authentication, offline message buffering, and rate limiting.

Usage:
  mobileflow-relay                    # default port 3005
  mobileflow-relay --port 8080        # custom port
  python -m mobileflow_relay --port 3005
"""

import argparse
import os


def main() -> None:
    parser = argparse.ArgumentParser(description="MobileFlow Relay Server")
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "3005")),
                        help="Listen port (default: 3005 or $PORT)")
    args = parser.parse_args()

    import uvicorn
    # Import the FastAPI app from the top-level main.py
    # In production (Docker), main.py is at /app/main.py
    # When installed as package, use the relay_server module
    from .relay_server import create_app

    app = create_app()
    uvicorn.run(app, host="0.0.0.0", port=args.port)


if __name__ == "__main__":
    main()
