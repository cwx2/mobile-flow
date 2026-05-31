"""
Error codes and exception types for the MobileFlow Agent.

Two layers of error handling:

1. ACP layer (JSON-RPC 2.0):
   Uses numeric error codes from ``acp.RequestError``. These are standard
   JSON-RPC codes extended with ACP-specific codes for auth and resources.
   See ``AcpErrorCode`` enum and ``is_auth_error()`` helper.

2. Application layer:
   Uses ``MobileFlowError`` with string error codes (``AppErrorCode``).
   These are sent to the frontend via WebSocket messages for user-facing
   error display.

ACP error codes reference (from SDK):
  -32700  Parse error
  -32600  Invalid request
  -32601  Method not found
  -32602  Invalid params
  -32603  Internal error
  -32000  Authentication required (triggers auth retry flow)
  -32002  Resource not found
"""

from __future__ import annotations

from enum import IntEnum


# ── ACP / JSON-RPC error codes ──

class AcpErrorCode(IntEnum):
    """ACP JSON-RPC error codes.

    Matches the factory methods on ``acp.RequestError`` (e.g.
    ``RequestError.auth_required()`` produces code -32000).
    Used by ``is_auth_error()`` to detect auth failures.
    """

    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
    AUTH_REQUIRED = -32000
    RESOURCE_NOT_FOUND = -32002


def is_auth_error(error: Exception) -> bool:
    """Check if an exception is an ACP authentication error (-32000).

    Two detection strategies:
    1. Primary: check ``RequestError.code == -32000`` (structured, reliable).
    2. Fallback: check error message contains "authentication required"
       (for transports that lose the error code, e.g. some HTTP proxies).

    Args:
        error: The exception to check.

    Returns:
        True if the error indicates authentication is required.
    """
    from acp import RequestError
    if isinstance(error, RequestError):
        return error.code == AcpErrorCode.AUTH_REQUIRED
    if isinstance(error, Exception) and "authentication required" in str(error).lower():
        return True
    return False


# ── Application error codes ──

class AppErrorCode:
    """Application-level error codes (string-based).

    Sent to the frontend via WebSocket messages for user-facing error display.
    Grouped by domain: CLI/Provider, Session, Permission, File, General.
    """

    # CLI / Provider
    CLI_NOT_FOUND = "cli_not_found"
    CLI_NOT_INSTALLED = "cli_not_installed"
    ACP_CONNECTION_FAILED = "acp_connection_failed"
    ACP_INIT_FAILED = "acp_init_failed"
    ACP_AUTH_REQUIRED = "acp_auth_required"

    # Session
    SESSION_NOT_FOUND = "session_not_found"
    SESSION_EXPIRED = "session_expired"

    # Permission
    PERMISSION_TIMEOUT = "permission_timeout"
    PERMISSION_DENIED = "permission_denied"

    # File
    FILE_NOT_FOUND = "file_not_found"
    FILE_PERMISSION_DENIED = "file_permission_denied"
    FILE_PATH_TRAVERSAL = "file_path_traversal"

    # Git
    GIT_REPO_LOCKED = "git_repo_locked"
    GIT_CANT_LOCK_REF = "git_cant_lock_ref"
    GIT_CANT_REBASE = "git_cant_rebase"
    GIT_NOT_A_REPO = "git_not_a_repo"

    # General
    INTERNAL_ERROR = "internal_error"
    TIMEOUT = "timeout"


class MobileFlowError(Exception):
    """Application-level exception with structured error code.

    Used throughout the agent for errors that should be reported to the
    frontend with a machine-readable code and human-readable message.

    Args:
        code: Error code string from ``AppErrorCode``.
        message: User-facing error message (Chinese). Defaults to code.
        detail: Technical detail for logging/debugging (not shown to user).
    """

    def __init__(self, code: str, message: str = "", detail: str = ""):
        self.code = code
        self.message = message or code
        self.detail = detail
        super().__init__(f"[{code}] {self.message}")

    def to_dict(self) -> dict:
        return {
            "code": self.code,
            "message": self.message,
            "detail": self.detail,
        }


class AuthRequiredError(MobileFlowError):
    """Raised when an ACP operation fails with -32000 (auth required).

    Caught by AuthInterceptor.on_error to transition the CLI provider
    to auth_required state and push to frontend. Replaces the old
    _with_auth_retry pattern that caused deadlocks.

    Args:
        cli_name: The CLI adapter that requires authentication.
        detail: Technical detail from the original ACP error.
    """

    def __init__(self, cli_name: str, detail: str = ""):
        super().__init__(
            code=AppErrorCode.ACP_AUTH_REQUIRED,
            message=f"CLI {cli_name} 需要认证",
            detail=detail,
        )
        self.cli_name = cli_name


class GitError(MobileFlowError):
    """Raised when a git command fails with a classifiable error.

    Enables structured retry logic in GitStateManager._retry_run()
    by mapping stderr messages to known error codes.

    Args:
        code: AppErrorCode constant (e.g. GIT_REPO_LOCKED).
        message: User-facing error message.
        stderr: Raw stderr output from the git command.
    """

    def __init__(self, code: str, message: str = "", stderr: str = ""):
        super().__init__(code=code, message=message, detail=stderr)
        self.stderr = stderr

    @staticmethod
    def classify(stderr: str) -> str | None:
        """Classify a git stderr message into a structured error code.

        Returns None if the error is not classifiable (generic failure).

        Args:
            stderr: Raw stderr output from git.

        Returns:
            AppErrorCode string, or None for unclassified errors.
        """
        s = stderr.lower()
        if "index.lock" in s or "unable to create" in s:
            return AppErrorCode.GIT_REPO_LOCKED
        if "cannot lock ref" in s or "unable to resolve reference" in s:
            return AppErrorCode.GIT_CANT_LOCK_REF
        if "cannot rebase" in s:
            return AppErrorCode.GIT_CANT_REBASE
        if "not a git repository" in s:
            return AppErrorCode.GIT_NOT_A_REPO
        return None
