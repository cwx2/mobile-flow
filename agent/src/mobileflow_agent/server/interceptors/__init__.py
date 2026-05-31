"""Message interceptor framework.

Provides pre_handle / post_handle / on_error hooks around WebSocket
message handlers for cross-cutting concerns like auth and logging.
"""

from .base import Interceptor, InterceptorChain, MessageContext
from .auth_interceptor import AuthInterceptor
from .log_interceptor import LogInterceptor

__all__ = [
    "Interceptor",
    "InterceptorChain",
    "MessageContext",
    "AuthInterceptor",
    "LogInterceptor",
]
