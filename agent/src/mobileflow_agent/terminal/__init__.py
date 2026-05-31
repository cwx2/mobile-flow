"""
终端子包：跨平台 PTY 终端会话管理

职责：
  为手机端提供真实终端体验，支持 CLI 交互。
  根据平台和 CLI 运行环境自动选择最佳 PTY 方案。

被谁调用：
  - server/handlers/terminal_handler.py
"""

from .manager import TerminalManager
from .session import TerminalSession

__all__ = ["TerminalManager", "TerminalSession"]
