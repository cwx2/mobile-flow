"""HTTP router for the Agent Web Dashboard.

Intercepts HTTP requests via websockets' process_request hook.
Returns static files for the SPA and JSON for API endpoints.
WebSocket upgrade requests pass through untouched.

websockets 16+ supports async process_request, so POST endpoints
that need async operations (CLI install, detect) work correctly.

Used by:
    - server/websocket.py (passes process_request to websockets.serve)
"""

from __future__ import annotations

import json
import mimetypes
import os
import sys
from pathlib import Path
from typing import TYPE_CHECKING, Any, Callable, Coroutine

from loguru import logger
from websockets.http11 import Request, Response
from websockets.datastructures import Headers

if TYPE_CHECKING:
    from ..services.port_proxy import PortProxy
    from ..services.run_config import RunConfigurationExecutor, RunConfigurationStore


# Static files directory — supports both development and PyInstaller bundle.
# Development: server/dashboard_api.py → parent.parent = mobileflow_agent/ → dashboard/static/
# PyInstaller: sys._MEIPASS/mobileflow_agent/dashboard/static/
def _find_static_dir() -> Path:
    """Locate the dashboard static files directory."""
    # PyInstaller bundle
    meipass = getattr(sys, '_MEIPASS', None)
    if meipass:
        candidate = Path(meipass) / "mobileflow_agent" / "dashboard" / "static"
        if candidate.is_dir():
            return candidate

    # Development: relative to this file
    candidate = Path(__file__).resolve().parent.parent / "dashboard" / "static"
    if candidate.is_dir():
        return candidate

    # Fallback: current working directory
    return Path("dashboard") / "static"


_STATIC_DIR = _find_static_dir()
logger.debug(f"Dashboard 静态文件目录: {_STATIC_DIR} (exists={_STATIC_DIR.is_dir()})")


# ── CLI install output buffer (shared across requests) ──
# Stores streaming output from async CLI install operations so the
# Dashboard frontend can poll for real-time install progress.
import asyncio
from collections import deque

_cli_install_state = {
    "buffer": deque(maxlen=500),
    "counter": 0,
    "status": "idle",
    "result": "",
}


def _append_install_line(text: str) -> None:
    """Append a line to the CLI install output buffer."""
    _cli_install_state["buffer"].append({"index": _cli_install_state["counter"], "text": text})
    _cli_install_state["counter"] += 1


def create_dashboard_handler(
    get_status: Callable[[], dict],
    get_connect_info: Callable[[], dict],
    get_cli_list: Callable[[], list[dict]],
    install_cli: Callable[[str], Coroutine] | None = None,
    uninstall_cli: Callable[[str], Coroutine] | None = None,
    test_cli: Callable[[str], Coroutine] | None = None,
    detect_cli: Callable[[], Coroutine] | None = None,
    add_cli: Callable[..., dict] | None = None,
    remove_cli: Callable[[str], dict] | None = None,
    get_api_keys: Callable[[], list[dict]] | None = None,
    save_api_key: Callable[[str, str], bool] | None = None,
    reset_password: Callable[[], str] | None = None,
    get_logs: Callable[..., list[dict]] | None = None,
    list_projects: Callable[[], list[dict]] | None = None,
    add_project: Callable[[str, str | None], bool] | None = None,
    switch_project: Callable[[str], str | None] | None = None,
    remove_project: Callable[[str], bool] | None = None,
    browse_directory: Callable | None = None,
    port_proxy: PortProxy | None = None,
    run_config_store: RunConfigurationStore | None = None,
    run_config_executor: RunConfigurationExecutor | None = None,
) -> Callable:
    """Create the process_request handler for the dashboard.

    Returns an async callable that websockets.serve uses as process_request.
    If the request is a normal HTTP request (not a WebSocket upgrade),
    it returns an HTTP Response. Otherwise returns None to let the
    WebSocket handshake proceed.

    Args:
        get_status: Returns agent status dict.
        get_connect_info: Returns connection info dict.
        get_cli_list: Returns CLI list (list of dicts).
        install_cli: Async callback to install a CLI by name.
        uninstall_cli: Async callback to uninstall a CLI by name.
        test_cli: Async callback to test a CLI by name.
        detect_cli: Async callback to re-detect all CLIs.
        get_api_keys: Returns list of configured API keys (masked).
        save_api_key: Saves an API key (name, value) → success bool.
        reset_password: Resets the connection password → new password.
        port_proxy: Optional PortProxy instance for /preview/* forwarding.
        run_config_store: Optional RunConfigurationStore for config CRUD.
        run_config_executor: Optional RunConfigurationExecutor for start/stop.

    Returns:
        An async process_request handler function.
    """

    async def handler(connection: Any, request: Request) -> Response | None:
        """Process HTTP requests before WebSocket upgrade."""
        # Let WebSocket upgrade requests pass through untouched.
        # The Upgrade header distinguishes WS handshakes from normal HTTP.
        upgrade = request.headers.get("Upgrade", "").lower()
        if upgrade == "websocket":
            return None

        raw_path = request.path
        path, params = _parse_query_params(raw_path)

        # ── GET API routes ──

        if path == "/api/status":
            return _json_response(get_status())

        if path == "/api/connect":
            return _json_response(get_connect_info())

        if path == "/api/cli/list":
            return _json_response({"adapters": get_cli_list()})

        if path == "/api/keys":
            if "name" in params and "value" in params and save_api_key:
                # Save key (passed as query params for simplicity)
                try:
                    ok = save_api_key(params["name"], params["value"])
                    return _json_response({"success": ok})
                except Exception as e:
                    return _json_response({"success": False, "message": str(e)}, 500)
            keys = get_api_keys() if get_api_keys else []
            return _json_response({"keys": keys})

        if path == "/api/logs" and get_logs:
            since = int(params.get("since", "0"))
            entries = get_logs(since=since)
            return _json_response({"entries": entries})

        # ── Action API routes (use query params since process_request has no body) ──

        if path == "/api/cli/install" and install_cli:
            name = params.get("name", "")
            if not name:
                return _json_response({"success": False, "message": "Missing ?name= parameter"}, 400)
            if _cli_install_state["status"] == "installing":
                return _json_response({"success": False, "message": "Another install is in progress"}, 409)

            # Reset buffer and start async install
            _cli_install_state["buffer"].clear()
            _cli_install_state["counter"] = 0
            _cli_install_state["status"] = "installing"
            _cli_install_state["result"] = ""

            async def _do_install():
                try:
                    _append_install_line(f"$ Installing {name}...")
                    result = await install_cli(name)
                    if result.get("success"):
                        _cli_install_state["status"] = "done"
                        _cli_install_state["result"] = result.get("message", "Installed successfully")
                        _append_install_line(f"\n✅ {_cli_install_state['result']}")
                    else:
                        _cli_install_state["status"] = "error"
                        _cli_install_state["result"] = result.get("message", "Install failed")
                        _append_install_line(f"\n❌ {_cli_install_state['result']}")
                except Exception as e:
                    _cli_install_state["status"] = "error"
                    _cli_install_state["result"] = str(e)
                    _append_install_line(f"\n❌ Error: {e}")

            asyncio.create_task(_do_install())
            return _json_response({"success": True, "status": "installing"})

        if path == "/api/cli/install-output":
            since = int(params.get("since", "0"))
            lines = [l for l in _cli_install_state["buffer"] if l["index"] >= since]
            return _json_response({
                "lines": lines,
                "status": _cli_install_state["status"],
                "result": _cli_install_state["result"],
            })

        if path == "/api/cli/uninstall" and uninstall_cli:
            name = params.get("name", "")
            if not name:
                return _json_response({"success": False, "message": "Missing ?name= parameter"}, 400)
            try:
                result = await uninstall_cli(name)
                return _json_response(result)
            except Exception as e:
                return _json_response({"success": False, "message": str(e)}, 500)

        if path == "/api/cli/test" and test_cli:
            name = params.get("name", "")
            if not name:
                return _json_response({"success": False, "message": "Missing ?name= parameter"}, 400)
            try:
                result = await test_cli(name)
                return _json_response(result)
            except Exception as e:
                return _json_response({"success": False, "message": str(e)}, 500)

        if path == "/api/cli/detect" and detect_cli:
            try:
                await detect_cli()
                return _json_response({"success": True, "adapters": get_cli_list()})
            except Exception as e:
                return _json_response({"success": False, "message": str(e)}, 500)

        if path == "/api/cli/add" and add_cli:
            name = params.get("name", "")
            command = params.get("command", "")
            args_json = params.get("args", "[]")
            display_name = params.get("display_name", name)
            if not name or not command:
                return _json_response({"success": False, "message": "Missing name or command"}, 400)
            try:
                import json as _json
                args = _json.loads(args_json) if args_json else []
                result = add_cli(name, command, args, display_name)
                return _json_response(result)
            except Exception as e:
                return _json_response({"success": False, "message": str(e)}, 500)

        if path == "/api/cli/remove" and remove_cli:
            name = params.get("name", "")
            if not name:
                return _json_response({"success": False, "message": "Missing ?name= parameter"}, 400)
            try:
                result = remove_cli(name)
                return _json_response(result)
            except Exception as e:
                return _json_response({"success": False, "message": str(e)}, 500)

        if path == "/api/password/reset" and reset_password:
            try:
                new_pwd = reset_password()
                return _json_response({"success": True, "password": new_pwd})
            except Exception as e:
                return _json_response({"success": False, "message": str(e)}, 500)

        # ── Project API routes ──

        if path == "/api/project/list" and list_projects:
            return _json_response({"projects": list_projects()})

        if path == "/api/project/add" and add_project:
            proj_path = params.get("path", "")
            proj_name = params.get("name") or None
            if not proj_path:
                return _json_response({"success": False, "message": "Missing ?path= parameter"}, 400)
            ok = add_project(proj_path, proj_name)
            return _json_response({"success": ok})

        if path == "/api/project/switch" and switch_project:
            proj_path = params.get("path", "")
            if not proj_path:
                return _json_response({"success": False, "message": "Missing ?path= parameter"}, 400)
            switch_project(proj_path)
            return _json_response({"success": True})

        if path == "/api/project/remove" and remove_project:
            proj_path = params.get("path", "")
            if not proj_path:
                return _json_response({"success": False, "message": "Missing ?path= parameter"}, 400)
            ok = remove_project(proj_path)
            return _json_response({"success": ok})

        if path == "/api/project/browse" and browse_directory:
            browse_path = params.get("path", "")
            try:
                dirs = await browse_directory(browse_path)
                return _json_response({"directories": dirs})
            except ValueError as e:
                return _json_response({"success": False, "message": str(e)}, 403)
            except FileNotFoundError as e:
                return _json_response({"success": False, "message": str(e)}, 404)
            except Exception as e:
                return _json_response({"success": False, "message": str(e)}, 500)

        # ── Run Configuration API routes ──

        if path == "/api/run-config/list" and run_config_store:
            configs = run_config_store.list_all()
            return _json_response({
                "configurations": [c.model_dump(mode="json") for c in configs],
                "selected_id": run_config_store.selected_id,
            })

        if path == "/api/run-config/create" and run_config_store:
            from ..services.run_config import RunConfigType as RCType
            config_type_str = params.get("type", "custom")
            try:
                config_type = RCType(config_type_str)
            except ValueError:
                return _json_response(
                    {"success": False, "message": f"Invalid type: {config_type_str}"}, 400
                )
            config = run_config_store.create(config_type)
            return _json_response({
                "success": True,
                "configuration": config.model_dump(mode="json"),
            })

        if path == "/api/run-config/update" and run_config_store:
            config_id = params.get("id", "")
            field = params.get("field", "")
            value = params.get("value", "")
            if not config_id:
                return _json_response(
                    {"success": False, "message": "Missing ?id= parameter"}, 400
                )
            if not field:
                return _json_response(
                    {"success": False, "message": "Missing ?field= parameter"}, 400
                )
            # Parse boolean and null values from query string
            parsed_value: Any = value
            if value.lower() == "true":
                parsed_value = True
            elif value.lower() == "false":
                parsed_value = False
            elif value == "":
                parsed_value = None

            # Handle nested fields like "preview.url" or "preview.host_header"
            # Convert "preview.url" → update the preview sub-object
            try:
                if "." in field:
                    parts = field.split(".", 1)
                    parent_field = parts[0]
                    child_field = parts[1]
                    # Get current config to read existing sub-object
                    current = run_config_store.get(config_id)
                    if current is None:
                        return _json_response(
                            {"success": False, "message": f"Configuration not found: {config_id}"}, 404
                        )
                    # Get existing sub-object or create empty dict
                    current_data = current.model_dump(mode="json")
                    sub_obj = current_data.get(parent_field) or {}
                    if isinstance(sub_obj, dict):
                        sub_obj[child_field] = parsed_value
                    updates = {parent_field: sub_obj}
                else:
                    updates = {field: parsed_value}

                updated = run_config_store.update(config_id, updates)
            except Exception as e:
                return _json_response(
                    {"success": False, "message": f"Update failed: {e}"}, 500
                )

            if updated is None:
                return _json_response(
                    {"success": False, "message": f"Configuration not found: {config_id}"}, 404
                )
            return _json_response({
                "success": True,
                "configuration": updated.model_dump(mode="json"),
            })

        if path == "/api/run-config/delete" and run_config_store:
            config_id = params.get("id", "")
            if not config_id:
                return _json_response(
                    {"success": False, "message": "Missing ?id= parameter"}, 400
                )
            deleted = run_config_store.delete(config_id)
            if not deleted:
                return _json_response(
                    {"success": False, "message": f"Configuration not found: {config_id}"}, 404
                )
            return _json_response({"success": True, "config_id": config_id})

        if path == "/api/run-config/duplicate" and run_config_store:
            config_id = params.get("id", "")
            if not config_id:
                return _json_response(
                    {"success": False, "message": "Missing ?id= parameter"}, 400
                )
            duplicated = run_config_store.duplicate(config_id)
            if duplicated is None:
                return _json_response(
                    {"success": False, "message": f"Configuration not found: {config_id}"}, 404
                )
            return _json_response({
                "success": True,
                "configuration": duplicated.model_dump(mode="json"),
            })

        if path == "/api/run-config/reorder" and run_config_store:
            config_id = params.get("id", "")
            direction = params.get("direction", "down")
            if not config_id:
                return _json_response(
                    {"success": False, "message": "Missing ?id= parameter"}, 400
                )
            if direction not in ("up", "down"):
                return _json_response(
                    {"success": False, "message": "direction must be 'up' or 'down'"}, 400
                )
            moved = run_config_store.reorder(config_id, direction)  # type: ignore[arg-type]
            if not moved:
                return _json_response(
                    {"success": False, "message": f"Cannot move: config not found or at boundary"}, 400
                )
            return _json_response({"success": True})

        if path == "/api/run-config/start" and run_config_store and run_config_executor:
            config_id = params.get("id", "")
            if not config_id:
                return _json_response(
                    {"success": False, "message": "Missing ?id= parameter"}, 400
                )
            config = run_config_store.get(config_id)
            if config is None:
                return _json_response(
                    {"success": False, "message": f"Configuration not found: {config_id}"}, 404
                )
            # Start execution asynchronously with no-op callbacks
            # (Dashboard polls /api/run-config/status for state updates)

            async def _noop_output(stream: str, data: str) -> None:
                pass

            async def _noop_state(cid: str, state: Any, **kwargs: Any) -> None:
                pass

            asyncio.create_task(
                run_config_executor.start(config, _noop_output, _noop_state)
            )
            return _json_response({"success": True, "config_id": config_id})

        if path == "/api/run-config/stop" and run_config_executor:
            config_id = params.get("id", "")
            if not config_id:
                return _json_response(
                    {"success": False, "message": "Missing ?id= parameter"}, 400
                )
            asyncio.create_task(run_config_executor.stop(config_id))
            return _json_response({"success": True, "config_id": config_id})

        if path == "/api/run-config/status" and run_config_executor:
            states = run_config_executor.get_all_states()
            return _json_response({
                "states": {k: v.value for k, v in states.items()},
            })

        if path == "/api/run-config/output" and run_config_executor:
            config_id = params.get("id", "")
            since = int(params.get("since", "0"))
            lines = run_config_executor.get_output(config_id, since)
            return _json_response({"lines": lines})

        if path == "/api/run-config/clear-output" and run_config_executor:
            config_id = params.get("id", "")
            run_config_executor.clear_output(config_id)
            return _json_response({"success": True})

        # ── Transparent proxy mode ──
        # When PortProxy is active, ALL non-API requests go to the dev
        # server. This makes the frontend app work as if accessed directly
        # (Vue Router paths, relative API calls, chunk loading all work).
        # Agent's own dashboard is inaccessible during preview — acceptable
        # tradeoff since preview and dashboard aren't used simultaneously.

        if port_proxy is not None and port_proxy.is_active:
            # Strip /preview/ prefix for backward compatibility
            forward_path = path
            if path.startswith("/preview"):
                forward_path = path[len("/preview"):] or "/"

            forward_path = forward_path.lstrip("/")
            # Extract HTTP method from the websockets Request object.
            # websockets 16.0 Request only has path/headers (designed for
            # WS upgrade which is always GET). We use hasattr for forward
            # compatibility — future versions may expose .method directly.
            req_method = request.method if hasattr(request, "method") else "GET"
            # Extract request body for POST/PUT/PATCH forwarding.
            # Same forward-compatibility approach: websockets 16.0 does not
            # expose body on the Request object, but future versions might.
            req_body = request.body if hasattr(request, "body") else None
            req_headers = dict(request.headers) if request.headers else {}
            _, query_params_str = _parse_query_string_raw(raw_path)
            logger.debug(
                f"预览代理转发: method={req_method}, path={forward_path}, "
                f"body={'有' if req_body else '无'}"
            )
            try:
                return await port_proxy.proxy_request(
                    path=forward_path,
                    method=req_method,
                    headers=req_headers,
                    body=req_body,
                    query_string=query_params_str,
                )
            except Exception as e:
                logger.error(f"预览代理异常: path={forward_path}, error={e}")
                return _error_response_plain(502, f"Proxy error: {e}")

        # ── Static file routes (dashboard, only when proxy is inactive) ──

        if path == "/" or path == "/index.html":
            return _serve_static("index.html")

        clean_path = path.lstrip("/")
        if clean_path and not clean_path.startswith("api/"):
            static_response = _serve_static(clean_path)
            if static_response.status_code != 404:
                return static_response

        # Non-WebSocket request that doesn't match any route — return 404.
        # We already checked for Upgrade: websocket at the top, so this is
        # a plain HTTP request (e.g. /favicon.ico from a browser).
        return _error_response_plain(404, "Not found")

    return handler


def _parse_query_params(path: str) -> tuple[str, dict[str, str]]:
    """Parse query parameters from a URL path.

    Args:
        path: URL path possibly containing query string (e.g. /api/cli/install?name=codex).

    Returns:
        Tuple of (clean_path, params_dict).
    """
    if "?" not in path:
        return path, {}
    clean_path, query = path.split("?", 1)
    params = {}
    for part in query.split("&"):
        if "=" in part:
            k, v = part.split("=", 1)
            from urllib.parse import unquote
            params[unquote(k)] = unquote(v)
    return clean_path, params


def _parse_query_string_raw(path: str) -> tuple[str, str]:
    """Extract the raw query string from a URL path.

    Unlike _parse_query_params which parses into a dict, this returns
    the raw query string for forwarding to the proxy target.

    Args:
        path: URL path possibly containing query string.

    Returns:
        Tuple of (clean_path, raw_query_string). Query string is empty
        string if no '?' is present.
    """
    if "?" not in path:
        return path, ""
    clean_path, query = path.split("?", 1)
    return clean_path, query


def _json_response(data: dict | list, status: int = 200) -> Response:
    """Build an HTTP JSON response.

    Args:
        data: JSON-serializable data.
        status: HTTP status code.

    Returns:
        A websockets Response with JSON content type.
    """
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    headers = Headers()
    headers["Content-Type"] = "application/json; charset=utf-8"
    headers["Content-Length"] = str(len(body))
    headers["Access-Control-Allow-Origin"] = "*"
    reason = "OK" if status == 200 else "Error"
    return Response(status, reason, headers, body)


def _serve_static(file_path: str) -> Response:
    """Serve a static file from the dashboard/static directory.

    Args:
        file_path: Relative path within the static directory.

    Returns:
        HTTP Response with the file content, or 404 if not found.
    """
    # Prevent path traversal
    try:
        full_path = (_STATIC_DIR / file_path).resolve()
        if not str(full_path).startswith(str(_STATIC_DIR.resolve())):
            return _not_found(file_path)
    except (ValueError, OSError):
        return _not_found(file_path)

    if not full_path.is_file():
        return _not_found(file_path)

    content_type, _ = mimetypes.guess_type(str(full_path))
    if content_type is None:
        content_type = "application/octet-stream"

    body = full_path.read_bytes()
    headers = Headers()
    headers["Content-Type"] = content_type
    headers["Content-Length"] = str(len(body))
    headers["Cache-Control"] = "no-cache"
    return Response(200, "OK", headers, body)


def _not_found(path: str) -> Response:
    """Return a 404 response."""
    body = f"Not Found: {path}".encode("utf-8")
    headers = Headers()
    headers["Content-Type"] = "text/plain; charset=utf-8"
    headers["Content-Length"] = str(len(body))
    return Response(404, "Not Found", headers, body)


def _error_response_plain(status: int, message: str) -> Response:
    """Return a plain-text error response with CORS headers.

    Used for preview proxy errors where the PortProxy is not available
    or not active.

    Args:
        status: HTTP status code.
        message: Human-readable error message.

    Returns:
        A websockets Response with the error.
    """
    body = message.encode("utf-8")
    headers = Headers()
    headers["Content-Type"] = "text/plain; charset=utf-8"
    headers["Content-Length"] = str(len(body))
    headers["Access-Control-Allow-Origin"] = "*"
    reason = "Bad Gateway" if status == 502 else "Error"
    return Response(status, reason, headers, body)
