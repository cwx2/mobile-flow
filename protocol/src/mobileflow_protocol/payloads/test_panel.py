"""Test Panel domain payload models for the MobileFlow WebSocket protocol.

Covers script execution, API proxy, preview management,
screenshot capture, and visual diff operations.

Message types handled:
  - script.run       (SCRIPT_RUN)       — execute a command
  - script.output    (SCRIPT_OUTPUT)    — stdout/stderr stream chunk
  - script.done      (SCRIPT_DONE)      — command completed
  - script.stop      (SCRIPT_STOP)      — stop running command
  - api.request      (API_REQUEST)      — execute HTTP request
  - api.response     (API_RESPONSE)     — HTTP response
  - api.error        (API_ERROR)        — request error
  - preview.start    (PREVIEW_START)    — start dev server + proxy
  - preview.ready    (PREVIEW_READY)    — preview URL available
  - preview.output   (PREVIEW_OUTPUT)   — dev server stdout/stderr
  - preview.stop     (PREVIEW_STOP)     — stop dev server + proxy
  - preview.stopped  (PREVIEW_STOPPED)  — dev server terminated
  - preview.file_changed (PREVIEW_FILE_CHANGED) — file change during preview
  - preview.detect   (PREVIEW_DETECT)   — detect project type (plugin)
  - preview.detect.result (PREVIEW_DETECT_RESULT) — detection result
  - screenshot.capture   (SCREENSHOT_CAPTURE)   — capture screenshot
  - screenshot.result    (SCREENSHOT_RESULT)    — screenshot image
  - screenshot.error     (SCREENSHOT_ERROR)     — capture error
  - visual_diff.start    (VISUAL_DIFF_START)    — capture "before" baseline
  - visual_diff.compare  (VISUAL_DIFF_COMPARE)  — capture "after" and diff
  - visual_diff.result   (VISUAL_DIFF_RESULT)   — diff result with images

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Literal

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


# ── Script Execution ──


class ScriptRunPayload(PayloadBase):
    """Payload for ``script.run`` — execute a command.

    Sent by the App to request command execution on the Agent.
    The command runs in a subprocess with optional working directory
    and environment variable overrides.

    Attributes:
        command: Shell command string to execute.
        working_directory: Optional working directory path.
            Defaults to project root on the Agent if not specified.
        env: Optional environment variable overrides (key-value map).
    """

    command: str
    working_directory: str | None = None
    env: dict[str, str] | None = None


class ScriptOutputPayload(PayloadBase):
    """Payload for ``script.output`` — streaming output chunk.

    Sent by the Agent as stdout/stderr data becomes available
    from the running subprocess.

    Attributes:
        stream: Which output stream produced this data ("stdout" or "stderr").
        data: The output text content.
    """

    stream: Literal["stdout", "stderr"]
    data: str


class ScriptDonePayload(PayloadBase):
    """Payload for ``script.done`` — command completed.

    Sent by the Agent when the subprocess terminates, regardless
    of whether it completed normally, was killed, or errored.

    Attributes:
        exit_code: Process exit code (0 = success).
        status: Termination reason — "completed" for normal exit,
            "killed" if stopped by user/SIGKILL, "error" if failed to start.
        error_message: Optional error description when status is "error".
    """

    exit_code: int
    status: Literal["completed", "killed", "error"]
    error_message: str | None = None


class ScriptStopPayload(PayloadBase):
    """Payload for ``script.stop`` — request termination.

    Sent by the App to request graceful stop of the running command.
    The Agent sends SIGTERM first, then SIGKILL after 5 seconds.

    Attributes:
        reason: Why the stop was requested (default "user_initiated").
    """

    reason: str = "user_initiated"


# ── API Proxy ──


class ApiRequestPayload(PayloadBase):
    """Payload for ``api.request`` — execute HTTP request via Agent.

    Sent by the App to have the Agent execute an HTTP request from
    the desktop, solving the localhost accessibility problem.

    Attributes:
        url: Target URL (localhost, LAN, or public internet).
        method: HTTP method (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS).
        headers: Request headers as key-value map.
        body: Optional request body string.
        follow_redirects: Whether to follow HTTP redirects (up to 10 hops).
        request_id: Unique identifier to correlate request with response.
    """

    url: str
    method: Literal["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"] = "GET"
    headers: dict[str, str] = {}
    body: str | None = None
    follow_redirects: bool = True
    request_id: str


class ApiResponsePayload(PayloadBase):
    """Payload for ``api.response`` — HTTP response from target.

    Sent by the Agent after successfully executing the HTTP request.

    Attributes:
        status_code: HTTP status code (e.g. 200, 404, 500).
        headers: Response headers as key-value map.
        body: Response body as string.
        duration_ms: Request duration in milliseconds.
        request_id: Correlates with the original api.request.
    """

    status_code: int
    headers: dict[str, str]
    body: str
    duration_ms: int
    request_id: str


class ApiErrorPayload(PayloadBase):
    """Payload for ``api.error`` — request failed.

    Sent by the Agent when the HTTP request could not be completed.

    Attributes:
        error_type: Classification of the failure — "timeout" for 30s
            exceeded, "connection_refused" for refused connections,
            "dns_error" for unresolvable hostnames, "unknown" for other.
        message: Human-readable error description.
        request_id: Correlates with the original api.request.
    """

    error_type: Literal["timeout", "connection_refused", "dns_error", "unknown"]
    message: str
    request_id: str


# ── Preview ──


class PreviewStartPayload(PayloadBase):
    """Payload for ``preview.start`` — start dev server and/or activate proxy.

    Sent by the App to initiate a web preview session. If command is
    provided, the Agent starts the subprocess and activates the port
    proxy. If command is None ("Connect Only" mode), only the proxy
    is activated for the specified target URL.

    Attributes:
        command: Optional shell command to start the dev server.
            If None, Agent only activates the port proxy.
        target_url: Full URL to proxy to (e.g. "https://de4.nmm.com:7001").
            If empty, Agent auto-detects from command output.
        port: Legacy field, ignored if target_url is set. Kept for
            backward compatibility during migration.
        working_directory: Optional working directory for the command.
    """

    command: str | None = None
    target_url: str = ""
    port: int = 0
    working_directory: str | None = None


class PreviewReadyPayload(PayloadBase):
    """Payload for ``preview.ready`` — preview URL is available.

    Sent by the Agent once the port proxy is active and the target
    port is responding.

    Attributes:
        preview_url: Full URL the App should load in the WebView
            (e.g. "http://192.168.1.100:8765/preview/").
    """

    preview_url: str


class PreviewOutputPayload(PayloadBase):
    """Payload for ``preview.output`` — dev server stdout/stderr.

    Sent by the Agent to stream compilation progress and server
    output while the dev server is starting up.

    Attributes:
        stream: Which output stream produced this data ("stdout" or "stderr").
        data: The output text content.
    """

    stream: Literal["stdout", "stderr"]
    data: str


class PreviewStopPayload(PayloadBase):
    """Payload for ``preview.stop`` — request shutdown.

    Sent by the App to stop the dev server and deactivate the port proxy.
    No fields required.
    """

    pass


class PreviewStoppedPayload(PayloadBase):
    """Payload for ``preview.stopped`` — dev server terminated.

    Sent by the Agent when the preview session ends, either by user
    request, crash, or port conflict.

    Attributes:
        reason: Why the preview stopped — "user_stopped" for normal
            shutdown, "crashed" for unexpected termination, "port_conflict"
            if the target port became unavailable.
        last_output: Optional last lines of process output (useful for
            diagnosing crashes).
    """

    reason: Literal["user_stopped", "crashed", "port_conflict"]
    last_output: str | None = None


class PreviewFileChangedPayload(PayloadBase):
    """Payload for ``preview.file_changed`` — file changed during active preview.

    Sent by the Agent when a file change is detected while a preview
    session is active, triggering auto-refresh in the App.

    Attributes:
        path: Relative path of the changed file.
        change: Type of change (default "modified").
    """

    path: str
    change: str = "modified"


class PreviewDetectPayload(PayloadBase):
    """Payload for ``preview.detect`` — request project type detection.

    Sent by the App to query installed plugins for project type
    detection and smart suggestions.
    No fields required.
    """

    pass


class PreviewDetectResultPayload(PayloadBase):
    """Payload for ``preview.detect.result`` — detection result from plugin.

    Sent by the Agent with plugin-provided suggestions for the
    current project's dev server configuration.

    Attributes:
        project_type: Detected project type (e.g. "next", "vite", "flask").
            None if no plugin could detect the project.
        suggested_command: Suggested start command (e.g. "npm run dev").
        suggested_port: Suggested port number (e.g. 3000).
    """

    project_type: str | None = None
    suggested_command: str | None = None
    suggested_port: int | None = None


# ── Screenshot ──


class ScreenshotCapturePayload(PayloadBase):
    """Payload for ``screenshot.capture`` — request screenshot.

    Sent by the App to request a headless browser screenshot of
    a URL on the desktop via Playwright.

    Attributes:
        url: URL to navigate to and capture.
        viewport_width: Browser viewport width in pixels (default 375 for mobile).
        viewport_height: Browser viewport height in pixels (default 812 for mobile).
        wait_until: Page load strategy — "networkidle" waits for no network
            activity, "domcontentloaded" for DOM ready, "load" for full load.
    """

    url: str
    viewport_width: int = 375
    viewport_height: int = 812
    wait_until: Literal["networkidle", "domcontentloaded", "load"] = "networkidle"


class ScreenshotResultPayload(PayloadBase):
    """Payload for ``screenshot.result`` — captured image.

    Sent by the Agent with the captured screenshot data.

    Attributes:
        image_data: Base64-encoded PNG image data.
        actual_width: Actual captured image width in pixels.
        actual_height: Actual captured image height in pixels.
        capture_time_ms: Time taken to capture the screenshot in milliseconds.
    """

    image_data: str
    actual_width: int
    actual_height: int
    capture_time_ms: int


class ScreenshotErrorPayload(PayloadBase):
    """Payload for ``screenshot.error`` — capture failed.

    Sent by the Agent when screenshot capture fails.

    Attributes:
        error_type: Classification — "not_installed" if Playwright is
            missing, "timeout" if page load timed out, "navigation_error"
            if the URL could not be reached.
        message: Human-readable error description with recovery instructions.
    """

    error_type: Literal["not_installed", "timeout", "navigation_error"]
    message: str


# ── Visual Diff ──


class VisualDiffStartPayload(PayloadBase):
    """Payload for ``visual_diff.start`` — capture before baseline.

    Sent by the App to capture the "before" screenshot that will
    be compared against the "after" state later.

    Attributes:
        url: URL to capture as the baseline.
        viewport_width: Browser viewport width in pixels (default 375).
        viewport_height: Browser viewport height in pixels (default 812).
    """

    url: str
    viewport_width: int = 375
    viewport_height: int = 812


class VisualDiffComparePayload(PayloadBase):
    """Payload for ``visual_diff.compare`` — capture after and compute diff.

    Sent by the App to trigger the "after" screenshot capture and
    pixel diff computation against the stored baseline.
    No fields required.
    """

    pass


class VisualDiffResultPayload(PayloadBase):
    """Payload for ``visual_diff.result`` — comparison result.

    Sent by the Agent with the before/after images and computed
    pixel diff overlay.

    Attributes:
        before_image: Base64-encoded PNG of the "before" state.
        after_image: Base64-encoded PNG of the "after" state.
        diff_image: Base64-encoded PNG highlighting changed regions.
        changed_percentage: Percentage of pixels that differ (0.0–100.0).
        has_changes: Whether any visual changes were detected.
    """

    before_image: str
    after_image: str
    diff_image: str
    changed_percentage: float
    has_changes: bool


# ── Registry wiring ──

register_payload(MessageType.SCRIPT_RUN, ScriptRunPayload)
register_payload(MessageType.SCRIPT_OUTPUT, ScriptOutputPayload)
register_payload(MessageType.SCRIPT_DONE, ScriptDonePayload)
register_payload(MessageType.SCRIPT_STOP, ScriptStopPayload)

register_payload(MessageType.API_REQUEST, ApiRequestPayload)
register_payload(MessageType.API_RESPONSE, ApiResponsePayload)
register_payload(MessageType.API_ERROR, ApiErrorPayload)

register_payload(MessageType.PREVIEW_START, PreviewStartPayload)
register_payload(MessageType.PREVIEW_READY, PreviewReadyPayload)
register_payload(MessageType.PREVIEW_OUTPUT, PreviewOutputPayload)
register_payload(MessageType.PREVIEW_STOP, PreviewStopPayload)
register_payload(MessageType.PREVIEW_STOPPED, PreviewStoppedPayload)
register_payload(MessageType.PREVIEW_FILE_CHANGED, PreviewFileChangedPayload)
register_payload(MessageType.PREVIEW_DETECT, PreviewDetectPayload)
register_payload(MessageType.PREVIEW_DETECT_RESULT, PreviewDetectResultPayload)

register_payload(MessageType.SCREENSHOT_CAPTURE, ScreenshotCapturePayload)
register_payload(MessageType.SCREENSHOT_RESULT, ScreenshotResultPayload)
register_payload(MessageType.SCREENSHOT_ERROR, ScreenshotErrorPayload)

register_payload(MessageType.VISUAL_DIFF_START, VisualDiffStartPayload)
register_payload(MessageType.VISUAL_DIFF_COMPARE, VisualDiffComparePayload)
register_payload(MessageType.VISUAL_DIFF_RESULT, VisualDiffResultPayload)
