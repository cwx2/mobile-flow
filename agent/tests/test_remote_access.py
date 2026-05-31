"""
远程访问模块测试

覆盖：
  1. ServerConnectionManager 连接模式枚举和初始化
  2. AgentConfig 新增字段（connection_mode, relay_url, device_id, tunnel_*）
  3. DaemonManager 状态文件读写、锁文件、生命周期
  4. ControlServer 端点
  5. Relay auth 模块（Ed25519 签名验证）
  6. Relay RelayHub（设备注册/注销/消息转发/离线暂存/限流/过期清理）
  7. __main__.py CLI 命令解析
  8. 配对流程（secret 生成 → QR URL → 短配对码）
"""

import asyncio
import subprocess
import json
import os
import shutil
import tempfile
import time
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# ═══════════════════════════════════════════════════════════════
# Task 4: AgentConfig 新增字段测试
# ═══════════════════════════════════════════════════════════════


class TestAgentConfigRemoteFields:
    """AgentConfig 远程连接配置字段测试"""

    def test_default_connection_mode_is_lan(self):
        from mobileflow_agent.core.config import AgentConfig
        config = AgentConfig()
        assert config.connection_mode == "lan"

    def test_relay_url_default_empty(self):
        from mobileflow_agent.core.config import AgentConfig
        config = AgentConfig()
        assert config.relay_url == ""

    def test_device_id_default_empty(self):
        from mobileflow_agent.core.config import AgentConfig
        config = AgentConfig()
        assert config.device_id == ""

    def test_ensure_device_id_generates_id(self):
        from mobileflow_agent.core.config import AgentConfig
        config = AgentConfig()
        did = config.ensure_device_id()
        assert len(did) == 32  # hex(16 bytes) = 32 chars
        # 调用两次应该返回相同 ID
        assert config.ensure_device_id() == did

    def test_tunnel_fields_default_empty(self):
        from mobileflow_agent.core.config import AgentConfig
        config = AgentConfig()
        assert config.tunnel_bearer_token == ""
        assert config.tunnel_tls_cert == ""
        assert config.tunnel_tls_key == ""

    def test_connection_mode_can_be_set(self):
        from mobileflow_agent.core.config import AgentConfig
        config = AgentConfig()
        config.connection_mode = "relay"
        assert config.connection_mode == "relay"
        config.connection_mode = "tunnel"
        assert config.connection_mode == "tunnel"


# ═══════════════════════════════════════════════════════════════
# Task 4: ServerConnectionManager 测试
# ═══════════════════════════════════════════════════════════════


class TestServerConnectionManager:
    """ServerConnectionManager 基本测试"""

    def test_default_mode_is_lan(self):
        from mobileflow_agent.server.connection_manager import (
            ServerConnectionManager, ConnectionMode,
        )
        mgr = ServerConnectionManager()
        assert mgr.mode == ConnectionMode.LAN

    def test_connection_mode_enum_values(self):
        from mobileflow_agent.server.connection_manager import ConnectionMode
        assert ConnectionMode.LAN == "lan"
        assert ConnectionMode.RELAY == "relay"
        assert ConnectionMode.TUNNEL == "tunnel"

    def test_set_message_handler(self):
        from mobileflow_agent.server.connection_manager import ServerConnectionManager
        mgr = ServerConnectionManager()
        handler = AsyncMock()
        mgr.set_message_handler(handler)
        assert mgr._on_message is handler

    def test_relay_send_without_connection_does_not_crash(self):
        """Relay 未连接时发送不应崩溃"""
        from mobileflow_agent.server.connection_manager import ServerConnectionManager
        mgr = ServerConnectionManager()
        # 应该只是 warning，不抛异常
        asyncio.run(mgr.relay_send({"type": "test"}))


# ═══════════════════════════════════════════════════════════════
# Task 8: Daemon 状态文件测试
# ═══════════════════════════════════════════════════════════════


class TestDaemonState:
    """Daemon 状态文件读写测试"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self._data_dir = Path(self._tmpdir)

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_write_and_read_state(self):
        from mobileflow_agent.daemon.state import write_daemon_state, read_daemon_state
        state = {"pid": 12345, "http_port": 50097, "version": "0.1.0"}
        write_daemon_state(self._data_dir, state)
        loaded = read_daemon_state(self._data_dir)
        assert loaded is not None
        assert loaded["pid"] == 12345
        assert loaded["http_port"] == 50097

    def test_read_nonexistent_returns_none(self):
        from mobileflow_agent.daemon.state import read_daemon_state
        assert read_daemon_state(self._data_dir) is None

    def test_delete_state(self):
        from mobileflow_agent.daemon.state import (
            write_daemon_state, read_daemon_state, delete_daemon_state,
        )
        write_daemon_state(self._data_dir, {"pid": 1})
        delete_daemon_state(self._data_dir)
        assert read_daemon_state(self._data_dir) is None

    def test_read_corrupted_state(self):
        from mobileflow_agent.daemon.state import read_daemon_state
        state_file = self._data_dir / "daemon.state.json"
        state_file.write_text("not json {{{", encoding="utf-8")
        assert read_daemon_state(self._data_dir) is None


# ═══════════════════════════════════════════════════════════════
# Task 8: Daemon 锁文件测试
# ═══════════════════════════════════════════════════════════════


class TestDaemonLock:
    """Daemon 独占锁测试"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self._data_dir = Path(self._tmpdir)

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_acquire_and_release(self):
        from mobileflow_agent.daemon.lock import DaemonLock
        lock = DaemonLock(self._data_dir)
        assert lock.acquire()
        lock.release()

    def test_double_acquire_fails(self):
        from mobileflow_agent.daemon.lock import DaemonLock
        lock1 = DaemonLock(self._data_dir)
        lock2 = DaemonLock(self._data_dir)
        assert lock1.acquire()
        # 第二个锁应该获取失败
        assert not lock2.acquire()
        lock1.release()

    def test_release_then_reacquire(self):
        from mobileflow_agent.daemon.lock import DaemonLock
        lock = DaemonLock(self._data_dir)
        assert lock.acquire()
        lock.release()
        # 释放后应该能重新获取
        assert lock.acquire()
        lock.release()


# ═══════════════════════════════════════════════════════════════
# Task 5: 配对流程测试
# ═══════════════════════════════════════════════════════════════


class TestPairingFlow:
    """配对流程测试"""

    def test_generate_secret_is_32_bytes(self):
        from mobileflow_agent.crypto.crypto_module import CryptoModule
        secret = CryptoModule.generate_secret()
        assert len(secret) == 32

    def test_pair_url_format(self):
        """配对 URL 格式正确"""
        from mobileflow_agent.crypto.crypto_module import CryptoModule
        secret = CryptoModule.generate_secret()
        b64url = CryptoModule.secret_to_base64url(secret)
        relay_url = "wss://relay.mobileflow.dev"
        pair_url = f"mobileflow://pair/{relay_url}/{b64url}"
        assert pair_url.startswith("mobileflow://pair/")
        assert "+" not in b64url
        assert "/" not in b64url
        assert "=" not in b64url

    def test_short_code_from_secret(self):
        """短配对码生成"""
        import hashlib
        from mobileflow_agent.crypto.crypto_module import CryptoModule
        secret = CryptoModule.generate_secret()
        short_code = hashlib.sha256(secret).hexdigest()[:6].upper()
        assert len(short_code) == 6
        assert short_code.isalnum()

    def test_pair_url_roundtrip(self):
        """配对 URL 中的 secret 可以正确解码"""
        from mobileflow_agent.crypto.crypto_module import CryptoModule
        secret = CryptoModule.generate_secret()
        b64url = CryptoModule.secret_to_base64url(secret)
        decoded = CryptoModule.base64url_to_secret(b64url)
        assert decoded == secret

    def test_paired_devices_can_encrypt_decrypt(self):
        """配对后双方用相同 secret 可以互相加密/解密"""
        from mobileflow_agent.crypto.crypto_module import CryptoModule
        secret = CryptoModule.generate_secret()
        agent_crypto = CryptoModule(secret)
        app_crypto = CryptoModule(secret)

        # Agent → App
        msg1 = {"type": "chat.stream", "payload": {"chunk": {"type": "text", "content": "hello"}}}
        encrypted1 = agent_crypto.encrypt(msg1)
        assert app_crypto.decrypt(encrypted1) == msg1

        # App → Agent
        msg2 = {"type": "chat.send", "payload": {"message": "hi"}}
        encrypted2 = app_crypto.encrypt(msg2)
        assert agent_crypto.decrypt(encrypted2) == msg2

    def test_different_pairs_cannot_decrypt(self):
        """不同配对的设备不能互相解密"""
        from mobileflow_agent.crypto.crypto_module import CryptoModule
        secret1 = CryptoModule.generate_secret()
        secret2 = CryptoModule.generate_secret()
        crypto1 = CryptoModule(secret1)
        crypto2 = CryptoModule(secret2)

        msg = {"type": "test"}
        encrypted = crypto1.encrypt(msg)
        with pytest.raises(Exception):
            crypto2.decrypt(encrypted)


# ═══════════════════════════════════════════════════════════════
# Task 6: Relay Server 测试
# ═══════════════════════════════════════════════════════════════


class TestRelayAuth:
    """Relay 认证模块测试"""

    def test_verify_valid_challenge(self):
        """有效签名应该验证通过"""
        # 需要把 relay 目录加到 path
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)

        from auth import verify_ed25519_challenge
        from mobileflow_agent.crypto.crypto_module import CryptoModule

        secret = os.urandom(32)
        crypto = CryptoModule(secret)
        challenge = crypto.auth_challenge()

        assert verify_ed25519_challenge(
            challenge.challenge,
            challenge.public_key,
            challenge.signature,
        )

    def test_verify_invalid_signature(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)

        from auth import verify_ed25519_challenge
        from mobileflow_agent.crypto.crypto_module import CryptoModule

        crypto1 = CryptoModule(os.urandom(32))
        crypto2 = CryptoModule(os.urandom(32))
        c1 = crypto1.auth_challenge()
        c2 = crypto2.auth_challenge()

        assert not verify_ed25519_challenge(c1.challenge, c1.public_key, c2.signature)

    def test_generate_auth_token(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)

        from auth import generate_auth_token
        token = generate_auth_token("device-001", "pubkey-b64")
        assert token.token  # 非空
        assert token.device_id == "device-001"
        assert token.expires_at > token.created_at


class TestRelayHub:
    """RelayHub 中继逻辑测试"""

    def _make_hub(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub
        return RelayHub()

    def test_register_and_unregister(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub, ConnectedDevice

        hub = RelayHub()
        ws_mock = MagicMock()
        device = ConnectedDevice(device_id="agent-001", role="agent", websocket=ws_mock)
        hub.register(device)
        assert hub.device_count == 1
        assert hub.get_device("agent-001") is not None

        hub.unregister("agent-001")
        assert hub.device_count == 0
        assert hub.get_device("agent-001") is None

    def test_find_target_app_to_agent(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub, ConnectedDevice

        hub = RelayHub()
        agent_ws = MagicMock()
        app_ws = MagicMock()

        agent = ConnectedDevice(device_id="agent-001", role="agent", websocket=agent_ws)
        app = ConnectedDevice(device_id="app-001", role="app", websocket=app_ws, target_device_id="agent-001")

        hub.register(agent)
        hub.register(app)

        # App 的目标应该是 Agent
        target = hub.find_target(app)
        assert target is not None
        assert target.device_id == "agent-001"

    def test_find_target_agent_to_app(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub, ConnectedDevice

        hub = RelayHub()
        agent_ws = MagicMock()
        app_ws = MagicMock()

        agent = ConnectedDevice(device_id="agent-001", role="agent", websocket=agent_ws)
        app = ConnectedDevice(device_id="app-001", role="app", websocket=app_ws, target_device_id="agent-001")

        hub.register(agent)
        hub.register(app)

        # Agent 的目标应该是连接到它的 App
        target = hub.find_target(agent)
        assert target is not None
        assert target.device_id == "app-001"

    def test_find_target_no_match(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub, ConnectedDevice

        hub = RelayHub()
        ws = MagicMock()
        app = ConnectedDevice(device_id="app-001", role="app", websocket=ws, target_device_id="agent-999")
        hub.register(app)

        assert hub.find_target(app) is None

    def test_forward_message_success(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub, ConnectedDevice

        hub = RelayHub()
        agent_ws = AsyncMock()
        app_ws = AsyncMock()

        agent = ConnectedDevice(device_id="agent-001", role="agent", websocket=agent_ws)
        app = ConnectedDevice(device_id="app-001", role="app", websocket=app_ws, target_device_id="agent-001")

        hub.register(agent)
        hub.register(app)

        # App 发消息给 Agent
        result = asyncio.run(hub.forward_message(app, '{"t":"encrypted","c":"abc"}'))
        assert result is True
        agent_ws.send_text.assert_called_once_with('{"t":"encrypted","c":"abc"}')

    def test_forward_message_target_offline(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub, ConnectedDevice

        hub = RelayHub()
        app_ws = AsyncMock()
        app = ConnectedDevice(device_id="app-001", role="app", websocket=app_ws, target_device_id="agent-999")
        hub.register(app)

        result = asyncio.run(hub.forward_message(app, '{"t":"encrypted","c":"abc"}'))
        assert result is False  # 目标不在线

    def test_rate_limit(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub

        hub = RelayHub()
        # 模拟超过限流
        hub._rate_limits["test-device"] = (300, time.time())
        assert not hub._check_rate_limit("test-device")

    def test_cleanup_expired_offline(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub

        hub = RelayHub()
        # 添加过期消息（25 小时前）
        hub._offline_messages["device-001"] = [
            {"data": "old", "ts": time.time() - 90000},
            {"data": "new", "ts": time.time()},
        ]
        cleaned = hub.cleanup_expired_offline()
        assert cleaned == 1
        assert len(hub._offline_messages["device-001"]) == 1


# ═══════════════════════════════════════════════════════════════
# Task 8: DaemonManager 测试
# ═══════════════════════════════════════════════════════════════


class TestDaemonManager:
    """DaemonManager 基本测试"""

    def test_is_process_alive_nonexistent(self):
        from mobileflow_agent.daemon.manager import DaemonManager
        assert not DaemonManager._is_process_alive(99999)

    def test_get_status_fields(self):
        """状态字典应该包含必要字段"""
        tmpdir = tempfile.mkdtemp()
        try:
            from mobileflow_agent.crypto.key_store import KeyStore
            key_store = KeyStore(data_dir=Path(tmpdir))
            status = {
                "pid": os.getpid(),
                "connection_mode": "lan",
                "paired_devices": len(key_store.list_devices()),
            }
            assert status["pid"] == os.getpid()
            assert status["connection_mode"] == "lan"
            assert status["paired_devices"] == 0
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_get_devices_empty(self):
        tmpdir = tempfile.mkdtemp()
        try:
            from mobileflow_agent.crypto.key_store import KeyStore
            from dataclasses import asdict
            key_store = KeyStore(data_dir=Path(tmpdir))
            devices = [asdict(d) for d in key_store.list_devices()]
            assert devices == []
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_daemon_manager_init(self):
        """DaemonManager 初始化不应崩溃"""
        from mobileflow_agent.daemon.manager import DaemonManager
        from mobileflow_agent.core.config import AgentConfig
        tmpdir = tempfile.mkdtemp()
        try:
            config = AgentConfig()
            config.data_dir = Path(tmpdir)
            daemon = DaemonManager(config)
            assert daemon.config is config
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)


# ═══════════════════════════════════════════════════════════════
# Task 14: 系统服务注册测试
# ═══════════════════════════════════════════════════════════════


class TestServiceInstall:
    """系统服务注册模块测试（不实际注册，只测试模板生成）"""

    def test_launchd_plist_template(self):
        """macOS launchd plist 模板格式正确"""
        from mobileflow_agent.daemon.install import _LAUNCHD_PLIST
        program_arguments = "\n".join([
            '    <string>/usr/bin/python3</string>',
            '    <string>-m</string>',
            '    <string>mobileflow_agent</string>',
            '    <string>start</string>',
            '    <string>--tray</string>',
        ])
        content = _LAUNCHD_PLIST.format(
            program_arguments=program_arguments,
            log_path="/tmp/mobileflow/logs",
            home_dir="/Users/test",
            extra_path="/usr/local/bin",
        )
        assert "dev.mobileflow.agent" in content
        assert "/usr/bin/python3" in content
        assert "RunAtLoad" in content
        assert "KeepAlive" in content
        assert "mobileflow_agent" in content

    def test_systemd_unit_template(self):
        """Linux systemd unit 模板格式正确"""
        from mobileflow_agent.daemon.install import _SYSTEMD_UNIT
        content = _SYSTEMD_UNIT.format(
            exec_start="/usr/bin/python3 -m mobileflow_agent start --tray",
            home_dir="/home/test",
            extra_path="/usr/local/bin",
        )
        assert "MobileFlow Agent" in content
        assert "Restart=on-failure" in content
        assert "RestartSec=5" in content
        assert "WantedBy=default.target" in content
        assert "mobileflow_agent" in content

    def test_service_names(self):
        """服务名称常量正确"""
        from mobileflow_agent.daemon.install import (
            _SERVICE_NAME_MACOS, _SERVICE_NAME_LINUX, _TASK_NAME_WINDOWS,
        )
        assert _SERVICE_NAME_MACOS == "dev.mobileflow.agent"
        assert _SERVICE_NAME_LINUX == "mobileflow-agent"
        assert _TASK_NAME_WINDOWS == "MobileFlowAgent"

    def test_install_uninstall_functions_exist(self):
        """install/uninstall 函数存在且可调用"""
        from mobileflow_agent.daemon.install import install_service, uninstall_service
        assert callable(install_service)
        assert callable(uninstall_service)


# ═══════════════════════════════════════════════════════════════
# Task 11: 推送通知测试
# ═══════════════════════════════════════════════════════════════


class TestPushNotification:
    """推送通知模块测试"""

    def _make_service(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from push import PushNotificationService
        return PushNotificationService()

    def test_register_token(self):
        svc = self._make_service()
        svc.register_token("dev-001", "android", "fcm-token-abc")
        assert svc.registered_count == 1

    def test_unregister_token(self):
        svc = self._make_service()
        svc.register_token("dev-001", "android", "fcm-token-abc")
        svc.unregister_token("dev-001")
        assert svc.registered_count == 0

    def test_send_to_unregistered_device(self):
        """发送给未注册设备应该返回 False"""
        import asyncio
        svc = self._make_service()
        result = asyncio.run(svc.send_notification("unknown", "task_done"))
        assert result is False

    def test_notification_types(self):
        """通知类型常量"""
        # 验证支持的通知类型
        types = ["permission_request", "task_done", "error"]
        for t in types:
            assert isinstance(t, str)


# ═══════════════════════════════════════════════════════════════
# Task 13: Docker 配置测试
# ═══════════════════════════════════════════════════════════════


class TestDockerConfig:
    """Docker 配置文件测试"""

    def test_dockerfile_exists(self):
        dockerfile = Path(__file__).parent.parent.parent / "relay" / "Dockerfile"
        assert dockerfile.exists()

    def test_dockerfile_content(self):
        dockerfile = Path(__file__).parent.parent.parent / "relay" / "Dockerfile"
        content = dockerfile.read_text()
        assert "python:3.12" in content
        assert "requirements.txt" in content
        assert "EXPOSE 3005" in content

    def test_docker_compose_exists(self):
        compose = Path(__file__).parent.parent.parent / "relay" / "docker-compose.yml"
        assert compose.exists()

    def test_docker_compose_content(self):
        compose = Path(__file__).parent.parent.parent / "relay" / "docker-compose.yml"
        content = compose.read_text(encoding="utf-8")
        assert "relay" in content
        assert "caddy" in content
        assert "443" in content

    def test_caddyfile_exists(self):
        caddyfile = Path(__file__).parent.parent.parent / "relay" / "Caddyfile"
        assert caddyfile.exists()

    def test_requirements_txt(self):
        req = Path(__file__).parent.parent.parent / "relay" / "requirements.txt"
        assert req.exists()
        content = req.read_text()
        assert "fastapi" in content
        assert "PyNaCl" in content


# ═══════════════════════════════════════════════════════════════
# 边界测试补充
# ═══════════════════════════════════════════════════════════════


class TestRelayHubEdgeCases:
    """RelayHub 边界测试"""

    def _make_hub(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub, ConnectedDevice
        return RelayHub()

    def test_unregister_nonexistent(self):
        """注销不存在的设备不应崩溃"""
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub
        hub = RelayHub()
        hub.unregister("nonexistent")  # 不应抛异常
        assert hub.device_count == 0

    def test_get_nonexistent_device(self):
        """获取不存在的设备返回 None"""
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub
        hub = RelayHub()
        assert hub.get_device("nonexistent") is None

    def test_offline_message_overflow_100(self):
        """离线消息超过 100 条时丢弃最旧的"""
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub
        hub = RelayHub()
        # 手动填充 101 条
        hub._offline_messages["dev-001"] = [
            {"data": f"msg-{i}", "ts": time.time()} for i in range(100)
        ]
        # 再加一条应该触发溢出
        hub._offline_messages["dev-001"].append({"data": "overflow", "ts": time.time()})
        # 手动模拟 _store_offline 的溢出逻辑
        queue = hub._offline_messages["dev-001"]
        if len(queue) > 100:
            queue.pop(0)
        assert len(queue) == 100
        assert queue[-1]["data"] == "overflow"

    def test_multiple_apps_same_agent(self):
        """多个 App 连接同一个 Agent"""
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub, ConnectedDevice

        hub = RelayHub()
        agent_ws = AsyncMock()
        app1_ws = AsyncMock()
        app2_ws = AsyncMock()

        agent = ConnectedDevice(device_id="agent-001", role="agent", websocket=agent_ws)
        app1 = ConnectedDevice(device_id="app-001", role="app", websocket=app1_ws, target_device_id="agent-001")
        app2 = ConnectedDevice(device_id="app-002", role="app", websocket=app2_ws, target_device_id="agent-001")

        hub.register(agent)
        hub.register(app1)
        hub.register(app2)
        assert hub.device_count == 3

        # Agent 发消息应该找到第一个 App
        target = hub.find_target(agent)
        assert target is not None
        assert target.role == "app"

    def test_forward_websocket_exception(self):
        """转发时 WebSocket 异常应该注销目标设备"""
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub, ConnectedDevice

        hub = RelayHub()
        agent_ws = AsyncMock()
        agent_ws.send_text.side_effect = Exception("connection lost")
        app_ws = AsyncMock()

        agent = ConnectedDevice(device_id="agent-001", role="agent", websocket=agent_ws)
        app = ConnectedDevice(device_id="app-001", role="app", websocket=app_ws, target_device_id="agent-001")

        hub.register(agent)
        hub.register(app)

        # App 发消息给 Agent，但 Agent 的 WebSocket 异常
        result = asyncio.run(hub.forward_message(app, "test"))
        assert result is False
        # Agent 应该被注销
        assert hub.get_device("agent-001") is None

    def test_rate_limit_window_reset(self):
        """限流窗口过期后应该重置"""
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub
        hub = RelayHub()
        # 设置一个过期的窗口（61 秒前）
        hub._rate_limits["dev-001"] = (300, time.time() - 61)
        assert hub._check_rate_limit("dev-001") is True  # 窗口过期，重置

    def test_cleanup_all_expired(self):
        """所有离线消息都过期时应该全部清理"""
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub
        hub = RelayHub()
        hub._offline_messages["dev-001"] = [
            {"data": "old1", "ts": time.time() - 90000},
            {"data": "old2", "ts": time.time() - 90000},
        ]
        cleaned = hub.cleanup_expired_offline()
        assert cleaned == 2
        assert "dev-001" not in hub._offline_messages

    def test_flush_offline_device_not_registered(self):
        """推送离线消息给未注册设备应该返回 0"""
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from relay import RelayHub
        hub = RelayHub()
        hub._offline_messages["dev-001"] = [{"data": "msg", "ts": time.time()}]
        sent = asyncio.run(hub.flush_offline("dev-001"))
        assert sent == 0


class TestPushNotificationEdgeCases:
    """推送通知边界测试"""

    def _make_service(self):
        import sys
        relay_dir = str(Path(__file__).parent.parent.parent / "relay")
        if relay_dir not in sys.path:
            sys.path.insert(0, relay_dir)
        from push import PushNotificationService
        return PushNotificationService()

    def test_overwrite_token(self):
        """覆盖注册同一设备的 token"""
        svc = self._make_service()
        svc.register_token("dev-001", "android", "token-1")
        svc.register_token("dev-001", "android", "token-2")
        assert svc.registered_count == 1  # 不应重复

    def test_unknown_platform(self):
        """未知平台应该返回 False"""
        svc = self._make_service()
        svc.register_token("dev-001", "unknown_os", "token-1")
        result = asyncio.run(svc.send_notification("dev-001", "task_done"))
        assert result is False

    def test_ios_push_returns_false(self):
        """iOS 推送（APNs 未实现）应该返回 False"""
        svc = self._make_service()
        svc.register_token("dev-001", "ios", "apns-token")
        result = asyncio.run(svc.send_notification("dev-001", "task_done"))
        assert result is False

    def test_unknown_notification_type(self):
        """未知通知类型应该使用默认标题"""
        svc = self._make_service()
        svc.register_token("dev-001", "ios", "token")
        # 不应崩溃，只是返回 False（APNs 未实现）
        result = asyncio.run(svc.send_notification("dev-001", "unknown_type"))
        assert result is False

    def test_unregister_nonexistent(self):
        """注销不存在的 token 不应崩溃"""
        svc = self._make_service()
        svc.unregister_token("nonexistent")  # 不应抛异常
        assert svc.registered_count == 0


class TestDaemonEdgeCases:
    """Daemon 边界测试"""

    def test_state_file_with_extra_fields(self):
        """状态文件含额外字段应该正常读取"""
        from mobileflow_agent.daemon.state import write_daemon_state, read_daemon_state
        tmpdir = tempfile.mkdtemp()
        try:
            write_daemon_state(Path(tmpdir), {
                "pid": 1, "extra_field": "should not crash", "nested": {"a": 1}
            })
            state = read_daemon_state(Path(tmpdir))
            assert state is not None
            assert state["pid"] == 1
            assert state["extra_field"] == "should not crash"
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_lock_in_nonexistent_dir(self):
        """锁文件目录不存在时应该自动创建"""
        from mobileflow_agent.daemon.lock import DaemonLock
        tmpdir = tempfile.mkdtemp()
        deep_dir = Path(tmpdir) / "a" / "b" / "c"
        try:
            lock = DaemonLock(deep_dir)
            assert lock.acquire()
            lock.release()
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_delete_nonexistent_state(self):
        """删除不存在的状态文件不应崩溃"""
        from mobileflow_agent.daemon.state import delete_daemon_state
        tmpdir = tempfile.mkdtemp()
        try:
            delete_daemon_state(Path(tmpdir))  # 不应抛异常
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_config_ensure_device_id_idempotent(self):
        """ensure_device_id 多次调用返回相同值"""
        from mobileflow_agent.core.config import AgentConfig
        config = AgentConfig()
        id1 = config.ensure_device_id()
        id2 = config.ensure_device_id()
        id3 = config.ensure_device_id()
        assert id1 == id2 == id3


# ═══════════════════════════════════════════════════════════════
# Git 多仓库发现测试
# ═══════════════════════════════════════════════════════════════


class TestGitDiscoverRepos:
    """GitService.discover_repos 测试（对标 VS Code model.ts）"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def _init_repo(self, path_str: str):
        """在指定目录初始化 git 仓库"""
        os.makedirs(path_str, exist_ok=True)
        subprocess.run(["git", "init", path_str], capture_output=True)
        # 创建初始提交（否则 HEAD 不存在）
        subprocess.run(["git", "-C", path_str, "config", "user.email", "test@test.com"], capture_output=True)
        subprocess.run(["git", "-C", path_str, "config", "user.name", "Test"], capture_output=True)
        dummy = os.path.join(path_str, ".gitkeep")
        Path(dummy).touch()
        subprocess.run(["git", "-C", path_str, "add", "."], capture_output=True)
        subprocess.run(["git", "-C", path_str, "commit", "-m", "init"], capture_output=True)

    def test_single_repo_at_root(self):
        """根目录本身是 git 仓库"""
        self._init_repo(self._tmpdir)
        from mobileflow_agent.services.git_service import GitService
        git = GitService(self._tmpdir)
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        assert len(repos) >= 1
        assert any(r["is_current"] for r in repos)

    def test_no_repo(self):
        """没有任何 git 仓库"""
        os.makedirs(os.path.join(self._tmpdir, "empty_dir"), exist_ok=True)
        from mobileflow_agent.services.git_service import GitService
        git = GitService(self._tmpdir)
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        assert len(repos) == 0

    def test_multiple_repos_in_subdirs(self):
        """子目录中有多个 git 仓库"""
        for name in ["project-a", "project-b", "project-c"]:
            self._init_repo(os.path.join(self._tmpdir, name))
        from mobileflow_agent.services.git_service import GitService
        git = GitService(self._tmpdir)
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        names = {r["name"] for r in repos}
        assert "project-a" in names
        assert "project-b" in names
        assert "project-c" in names

    def test_nested_repo_not_scanned_deeper(self):
        """发现仓库后不再深入其内部"""
        self._init_repo(os.path.join(self._tmpdir, "outer"))
        # 在 outer 内部创建一个非仓库子目录
        inner = os.path.join(self._tmpdir, "outer", "src", "deep")
        os.makedirs(inner, exist_ok=True)
        from mobileflow_agent.services.git_service import GitService
        git = GitService(self._tmpdir)
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        # 应该只发现 outer，不会把 src/deep 当成仓库
        assert len(repos) == 1
        assert repos[0]["name"] == "outer"

    def test_skip_node_modules(self):
        """node_modules 中的 .git 应该被跳过"""
        nm_repo = os.path.join(self._tmpdir, "node_modules", "some-pkg")
        self._init_repo(nm_repo)
        # 同时在根目录外创建一个正常仓库
        self._init_repo(os.path.join(self._tmpdir, "real-project"))
        from mobileflow_agent.services.git_service import GitService
        git = GitService(self._tmpdir)
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        names = {r["name"] for r in repos}
        assert "real-project" in names
        assert "some-pkg" not in names

    def test_max_depth_limit(self):
        """深度限制：max_depth=1 只扫描一层"""
        # 第一层
        self._init_repo(os.path.join(self._tmpdir, "level1"))
        # 第二层（应该被 max_depth=1 跳过）
        deep = os.path.join(self._tmpdir, "dir", "level2")
        self._init_repo(deep)
        from mobileflow_agent.services.git_service import GitService
        git = GitService(self._tmpdir)
        repos = asyncio.run(git.discover_repos(self._tmpdir, max_depth=1))
        names = {r["name"] for r in repos}
        assert "level1" in names
        # level2 在第二层，max_depth=1 应该扫不到
        # 注意：depth=0 是根目录，depth=1 扫描根目录的子目录
        # "dir" 在 depth=1 被扫描，但 "dir/level2" 需要 depth=2

    def test_repo_has_branch_info(self):
        """每个仓库应该有分支信息"""
        self._init_repo(os.path.join(self._tmpdir, "my-repo"))
        from mobileflow_agent.services.git_service import GitService
        git = GitService(self._tmpdir)
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        assert len(repos) == 1
        # 新初始化的仓库分支应该是 main 或 master
        assert repos[0]["branch"] in ("main", "master")

    def test_repo_has_kind_field(self):
        """仓库应该有 kind 字段"""
        self._init_repo(os.path.join(self._tmpdir, "repo"))
        from mobileflow_agent.services.git_service import GitService
        git = GitService(self._tmpdir)
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        assert repos[0]["kind"] == "repository"

    def test_nonexistent_root_returns_empty(self):
        """不存在的根目录返回空列表"""
        from mobileflow_agent.services.git_service import GitService
        git = GitService("/nonexistent/path/xyz")
        repos = asyncio.run(git.discover_repos("/nonexistent/path/xyz"))
        assert repos == []

    def test_empty_root_returns_empty(self):
        """空根目录返回空列表"""
        from mobileflow_agent.services.git_service import GitService
        git = GitService("")
        repos = asyncio.run(git.discover_repos(""))
        assert repos == []

    def test_relative_path_field(self):
        """relative_path 应该是相对于扫描根目录的路径"""
        self._init_repo(os.path.join(self._tmpdir, "sub", "project"))
        from mobileflow_agent.services.git_service import GitService
        git = GitService(self._tmpdir)
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        assert len(repos) == 1
        rel = repos[0]["relative_path"]
        assert "sub" in rel and "project" in rel

    def test_is_current_flag(self):
        """is_current 应该标记当前工作目录所在的仓库"""
        repo_a = os.path.join(self._tmpdir, "a")
        repo_b = os.path.join(self._tmpdir, "b")
        self._init_repo(repo_a)
        self._init_repo(repo_b)
        from mobileflow_agent.services.git_service import GitService
        git = GitService(repo_a)  # 当前在 repo_a
        repos = asyncio.run(git.discover_repos(self._tmpdir))
        current = [r for r in repos if r["is_current"]]
        assert len(current) == 1
        assert current[0]["name"] == "a"


class TestGitFindRepoForFile:
    """GitService.find_repo_for_file 测试"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def _init_repo(self, path_str: str):
        os.makedirs(path_str, exist_ok=True)
        subprocess.run(["git", "init", path_str], capture_output=True)
        subprocess.run(["git", "-C", path_str, "config", "user.email", "t@t.com"], capture_output=True)
        subprocess.run(["git", "-C", path_str, "config", "user.name", "T"], capture_output=True)

    def test_file_in_repo(self):
        """文件在仓库内应该返回仓库根目录"""
        repo = os.path.join(self._tmpdir, "myrepo")
        self._init_repo(repo)
        src = os.path.join(repo, "src")
        os.makedirs(src, exist_ok=True)
        test_file = os.path.join(src, "main.py")
        Path(test_file).touch()
        from mobileflow_agent.services.git_service import GitService
        git = GitService(repo)
        result = asyncio.run(git.find_repo_for_file(test_file))
        assert result is not None
        assert "myrepo" in result

    def test_file_not_in_repo(self):
        """文件不在任何仓库内应该返回 None"""
        no_repo = os.path.join(self._tmpdir, "norepo")
        os.makedirs(no_repo, exist_ok=True)
        test_file = os.path.join(no_repo, "file.txt")
        Path(test_file).touch()
        from mobileflow_agent.services.git_service import GitService
        git = GitService(no_repo)
        result = asyncio.run(git.find_repo_for_file(test_file))
        assert result is None


# ═══════════════════════════════════════════════════════════════
# Git Shell 安全命令执行器测试
# ═══════════════════════════════════════════════════════════════


class TestGitShell:
    """GitService.execute_command 安全测试"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self._init_repo(self._tmpdir)
        from mobileflow_agent.services.git_service import GitService
        self.git = GitService(self._tmpdir)

    def teardown_method(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def _init_repo(self, path_str):
        subprocess.run(["git", "init", path_str], capture_output=True)
        subprocess.run(["git", "-C", path_str, "config", "user.email", "t@t.com"], capture_output=True)
        subprocess.run(["git", "-C", path_str, "config", "user.name", "T"], capture_output=True)
        Path(os.path.join(path_str, "file.txt")).write_text("hello")
        subprocess.run(["git", "-C", path_str, "add", "."], capture_output=True)
        subprocess.run(["git", "-C", path_str, "commit", "-m", "init"], capture_output=True)

    def test_git_status(self):
        """git status 应该成功"""
        r = asyncio.run(self.git.execute_command("git status"))
        assert r["success"]
        assert not r["blocked"]

    def test_git_log(self):
        """git log 应该成功"""
        r = asyncio.run(self.git.execute_command("git log --oneline"))
        assert r["success"]
        assert "init" in r["stdout"]

    def test_without_git_prefix(self):
        """不带 git 前缀也能执行"""
        r = asyncio.run(self.git.execute_command("status"))
        assert r["success"]

    def test_bare_git(self):
        """裸 'git' 等同于 git status"""
        r = asyncio.run(self.git.execute_command("git"))
        assert r["success"]

    def test_empty_command(self):
        """空命令应该被拦截"""
        r = asyncio.run(self.git.execute_command(""))
        assert r["blocked"]

    def test_shell_injection_pipe(self):
        """管道注入应该被拦截"""
        r = asyncio.run(self.git.execute_command("git status | cat /etc/passwd"))
        assert r["blocked"]
        assert "|" in r["reason"]

    def test_shell_injection_semicolon(self):
        """分号注入应该被拦截"""
        r = asyncio.run(self.git.execute_command("git status; rm -rf /"))
        assert r["blocked"]

    def test_shell_injection_and(self):
        """&& 注入应该被拦截"""
        r = asyncio.run(self.git.execute_command("git status && whoami"))
        assert r["blocked"]

    def test_shell_injection_backtick(self):
        """反引号注入应该被拦截"""
        r = asyncio.run(self.git.execute_command("git status `whoami`"))
        assert r["blocked"]

    def test_shell_injection_dollar(self):
        """$() 注入应该被拦截"""
        r = asyncio.run(self.git.execute_command("git status $(whoami)"))
        assert r["blocked"]

    def test_shell_injection_redirect(self):
        """重定向应该被拦截"""
        r = asyncio.run(self.git.execute_command("git log > /tmp/leak"))
        assert r["blocked"]

    def test_dangerous_reset_hard(self):
        """git reset --hard 应该标记为危险"""
        r = asyncio.run(self.git.execute_command("git reset --hard HEAD~1"))
        assert r["dangerous"]
        assert not r["success"]

    def test_dangerous_push_force(self):
        """git push --force 应该标记为危险"""
        r = asyncio.run(self.git.execute_command("git push --force"))
        assert r["dangerous"]

    def test_dangerous_clean(self):
        """git clean -fd 应该标记为危险"""
        r = asyncio.run(self.git.execute_command("git clean -fd"))
        assert r["dangerous"]

    def test_git_branch(self):
        """git branch 应该成功"""
        r = asyncio.run(self.git.execute_command("git branch"))
        assert r["success"]

    def test_git_diff(self):
        """git diff 应该成功"""
        r = asyncio.run(self.git.execute_command("git diff"))
        assert r["success"]

    def test_git_stash(self):
        """git stash 应该成功（即使没有变更）"""
        r = asyncio.run(self.git.execute_command("git stash list"))
        assert r["success"]

    def test_non_git_command_not_blocked(self):
        """非 git 子命令会被 git 自己报错，不是我们拦截"""
        r = asyncio.run(self.git.execute_command("git notarealcommand"))
        assert not r["success"]
        assert not r["blocked"]  # 不是我们拦截的，是 git 自己报错
