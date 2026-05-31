"""
Agent 配置管理
使用 pydantic-settings 实现类型安全的配置加载
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

from pydantic import Field
from pydantic_settings import BaseSettings
from loguru import logger


class SecurityConfig(BaseSettings):
    """安全策略配置"""

    # 需要用户确认的操作
    require_confirmation: list[str] = Field(default=[
        "file.delete",
        "file.write:*.env",
    ])
    # 完全禁止的操作
    blocked: list[str] = Field(default=[])
    # 会话超时（秒）
    session_timeout: int = 3600
    # 审计日志
    audit_log: bool = True


class AgentConfig(BaseSettings):
    """Agent 主配置"""

    model_config = {"env_prefix": "MOBILEFLOW_"}

    # 网络
    host: str = "0.0.0.0"
    port: int = 9600

    # 连接模式（lan / relay / tunnel）
    connection_mode: str = "lan"

    # Relay Server 配置（connection_mode=relay 时使用）
    relay_url: str = ""

    # 设备 ID（首次启动自动生成，用于 Relay 路由）
    device_id: str = ""

    # 工作目录（默认当前目录）
    work_dir: str = Field(default="")

    # 默认 CLI
    default_cli: str = "kiro"

    # 配对 token（首次启动自动生成）
    pair_token: Optional[str] = None

    # Tunnel 模式配置
    tunnel_bearer_token: str = ""
    tunnel_tls_cert: str = ""
    tunnel_tls_key: str = ""

    # 安全配置
    security: SecurityConfig = Field(default_factory=SecurityConfig)

    # 数据目录
    data_dir: Path = Field(
        default_factory=lambda: Path.home() / ".mobileflow"
    )

    def ensure_data_dir(self) -> Path:
        """确保数据目录存在"""
        self.data_dir.mkdir(parents=True, exist_ok=True)
        return self.data_dir

    def ensure_device_id(self) -> str:
        """确保有 device_id（首次启动自动生成）"""
        if not self.device_id:
            import secrets
            self.device_id = secrets.token_hex(16)
            logger.debug(f"生成 device_id: {self.device_id}")
        return self.device_id
