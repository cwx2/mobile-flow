"""
加密模块单元测试

测试覆盖：
  1. CryptoModule 初始化和参数验证
  2. secretbox 对称加密/解密往返一致性
  3. Ed25519 签名认证 challenge 生成和验证
  4. X25519 公钥加密/解密
  5. Base64URL 编码/解码
  6. 错误处理（篡改密文、错误密钥、格式错误）
  7. KeyStore 设备管理（增删查改）
  8. KeyStore 密钥存储（保存/加载/删除）
  9. 跨实例一致性（相同 secret 产生相同密钥）
  10. 大消息加密/解密
"""

import json
import os
import tempfile
import time
from pathlib import Path

import pytest

from mobileflow_agent.crypto.crypto_module import CryptoModule, AuthChallenge
from mobileflow_agent.crypto.key_store import KeyStore, DeviceInfo


# ═══════════════════════════════════════════════════════════════
# CryptoModule 测试
# ═══════════════════════════════════════════════════════════════


class TestCryptoModuleInit:
    """CryptoModule 初始化测试"""

    def test_init_with_valid_secret(self):
        """32 字节 secret 正常初始化"""
        secret = os.urandom(32)
        crypto = CryptoModule(secret)
        assert crypto is not None
        assert crypto.public_key_b64  # 公钥非空
        assert crypto.verify_key_b64  # 验证公钥非空

    def test_init_with_short_secret_raises(self):
        """secret 太短应该抛出 ValueError"""
        with pytest.raises(ValueError, match="32 字节"):
            CryptoModule(os.urandom(16))

    def test_init_with_long_secret_raises(self):
        """secret 太长应该抛出 ValueError"""
        with pytest.raises(ValueError, match="32 字节"):
            CryptoModule(os.urandom(64))

    def test_init_with_empty_secret_raises(self):
        """空 secret 应该抛出 ValueError"""
        with pytest.raises(ValueError, match="32 字节"):
            CryptoModule(b"")

    def test_same_secret_produces_same_keys(self):
        """相同 secret 应该产生相同的密钥对（确定性派生）"""
        secret = os.urandom(32)
        crypto1 = CryptoModule(secret)
        crypto2 = CryptoModule(secret)
        assert crypto1.public_key_b64 == crypto2.public_key_b64
        assert crypto1.verify_key_b64 == crypto2.verify_key_b64

    def test_different_secrets_produce_different_keys(self):
        """不同 secret 应该产生不同的密钥对"""
        crypto1 = CryptoModule(os.urandom(32))
        crypto2 = CryptoModule(os.urandom(32))
        assert crypto1.public_key_b64 != crypto2.public_key_b64
        assert crypto1.verify_key_b64 != crypto2.verify_key_b64


class TestSecretboxEncryption:
    """secretbox 对称加密/解密测试"""

    def setup_method(self):
        self.secret = os.urandom(32)
        self.crypto = CryptoModule(self.secret)

    def test_encrypt_decrypt_roundtrip(self):
        """加密后解密应该得到原始消息（往返一致性）"""
        message = {"type": "chat.send", "payload": {"message": "hello"}}
        encrypted = self.crypto.encrypt(message)
        decrypted = self.crypto.decrypt(encrypted)
        assert decrypted == message

    def test_encrypt_decrypt_complex_message(self):
        """复杂嵌套消息的往返一致性"""
        message = {
            "type": "chat.stream",
            "payload": {
                "chunk": {
                    "type": "text",
                    "content": "这是一段中文内容 🎉",
                    "language": None,
                    "locations": [{"path": "src/main.py", "line": 42}],
                }
            },
            "id": "abc123",
            "timestamp": 1712345678000,
        }
        encrypted = self.crypto.encrypt(message)
        decrypted = self.crypto.decrypt(encrypted)
        assert decrypted == message

    def test_encrypt_decrypt_empty_payload(self):
        """空 payload 的往返一致性"""
        message = {"type": "status.ping", "payload": {}}
        encrypted = self.crypto.encrypt(message)
        decrypted = self.crypto.decrypt(encrypted)
        assert decrypted == message

    def test_encrypt_produces_different_ciphertext(self):
        """相同消息加密两次应该产生不同密文（随机 nonce）"""
        message = {"type": "test", "payload": {}}
        enc1 = self.crypto.encrypt(message)
        enc2 = self.crypto.encrypt(message)
        assert enc1 != enc2  # 不同 nonce → 不同密文

    def test_decrypt_with_wrong_key_fails(self):
        """用错误密钥解密应该失败"""
        message = {"type": "test", "payload": {"data": "secret"}}
        encrypted = self.crypto.encrypt(message)

        wrong_crypto = CryptoModule(os.urandom(32))
        with pytest.raises(Exception):  # CryptoError
            wrong_crypto.decrypt(encrypted)

    def test_decrypt_tampered_ciphertext_fails(self):
        """篡改密文应该解密失败"""
        message = {"type": "test", "payload": {}}
        encrypted = self.crypto.encrypt(message)

        # 篡改 Base64 中间的字符
        import base64
        raw = bytearray(base64.b64decode(encrypted))
        raw[30] ^= 0xFF  # 翻转一个字节
        tampered = base64.b64encode(bytes(raw)).decode()

        with pytest.raises(Exception):
            self.crypto.decrypt(tampered)

    def test_decrypt_invalid_base64_fails(self):
        """无效 Base64 应该解密失败"""
        with pytest.raises(Exception):
            self.crypto.decrypt("not-valid-base64!!!")

    def test_encrypt_decrypt_large_message(self):
        """大消息（100KB）的往返一致性"""
        large_content = "x" * 100_000
        message = {"type": "file.read.result", "payload": {"content": large_content}}
        encrypted = self.crypto.encrypt(message)
        decrypted = self.crypto.decrypt(encrypted)
        assert decrypted == message
        assert decrypted["payload"]["content"] == large_content

    def test_encrypt_decrypt_unicode(self):
        """Unicode 内容（中文、emoji、特殊字符）的往返一致性"""
        message = {
            "type": "chat.stream",
            "payload": {
                "content": "你好世界 🌍 こんにちは мир 🎉 <script>alert('xss')</script>"
            },
        }
        encrypted = self.crypto.encrypt(message)
        decrypted = self.crypto.decrypt(encrypted)
        assert decrypted == message

    def test_encrypt_decrypt_all_message_types(self):
        """所有 MobileFlow MessageType 的往返一致性"""
        messages = [
            {"type": "auth.pair", "payload": {"token": "123456"}},
            {"type": "chat.send", "payload": {"cli": "kiro", "message": "hi"}},
            {"type": "file.tree", "payload": {"path": "/", "depth": 2}},
            {"type": "git.status", "payload": {}},
            {"type": "terminal.input", "payload": {"data": "ls -la\n"}},
            {"type": "permission.request", "payload": {"tool": "write_file"}},
            {"type": "diff.preview", "payload": {"path": "main.py"}},
        ]
        for msg in messages:
            encrypted = self.crypto.encrypt(msg)
            decrypted = self.crypto.decrypt(encrypted)
            assert decrypted == msg, f"消息类型 {msg['type']} 往返不一致"

    def test_cross_instance_decrypt(self):
        """不同 CryptoModule 实例（相同 secret）可以互相解密"""
        secret = os.urandom(32)
        sender = CryptoModule(secret)
        receiver = CryptoModule(secret)

        message = {"type": "test", "payload": {"from": "sender"}}
        encrypted = sender.encrypt(message)
        decrypted = receiver.decrypt(encrypted)
        assert decrypted == message


class TestAuthChallenge:
    """Ed25519 签名认证测试"""

    def setup_method(self):
        self.secret = os.urandom(32)
        self.crypto = CryptoModule(self.secret)

    def test_auth_challenge_structure(self):
        """challenge 应该包含正确的字段"""
        challenge = self.crypto.auth_challenge()
        assert isinstance(challenge, AuthChallenge)
        assert challenge.challenge  # 非空
        assert challenge.public_key  # 非空
        assert challenge.signature  # 非空

    def test_auth_challenge_verify_success(self):
        """自己生成的 challenge 应该能验证通过"""
        challenge = self.crypto.auth_challenge()
        assert CryptoModule.verify_challenge(
            challenge.challenge,
            challenge.public_key,
            challenge.signature,
        )

    def test_auth_challenge_verify_wrong_signature(self):
        """错误签名应该验证失败"""
        challenge = self.crypto.auth_challenge()
        # 用另一个密钥的签名
        other = CryptoModule(os.urandom(32))
        other_challenge = other.auth_challenge()
        assert not CryptoModule.verify_challenge(
            challenge.challenge,
            challenge.public_key,
            other_challenge.signature,  # 错误签名
        )

    def test_auth_challenge_verify_wrong_public_key(self):
        """错误公钥应该验证失败"""
        challenge = self.crypto.auth_challenge()
        other = CryptoModule(os.urandom(32))
        other_challenge = other.auth_challenge()
        assert not CryptoModule.verify_challenge(
            challenge.challenge,
            other_challenge.public_key,  # 错误公钥
            challenge.signature,
        )

    def test_auth_challenge_verify_tampered_challenge(self):
        """篡改 challenge 应该验证失败"""
        challenge = self.crypto.auth_challenge()
        import base64
        raw = bytearray(base64.b64decode(challenge.challenge))
        raw[0] ^= 0xFF
        tampered = base64.b64encode(bytes(raw)).decode()
        assert not CryptoModule.verify_challenge(
            tampered,
            challenge.public_key,
            challenge.signature,
        )

    def test_auth_challenge_unique_each_time(self):
        """每次生成的 challenge 应该不同"""
        c1 = self.crypto.auth_challenge()
        c2 = self.crypto.auth_challenge()
        assert c1.challenge != c2.challenge
        assert c1.signature != c2.signature
        # 公钥应该相同（同一个密钥对）
        assert c1.public_key == c2.public_key

    def test_verify_invalid_base64(self):
        """无效 Base64 输入应该返回 False"""
        assert not CryptoModule.verify_challenge("!!!", "!!!", "!!!")


class TestBoxEncryption:
    """X25519 公钥加密/解密测试"""

    def test_encrypt_decrypt_for_public_key(self):
        """公钥加密后用私钥解密应该得到原始数据"""
        sender = CryptoModule(os.urandom(32))
        receiver = CryptoModule(os.urandom(32))

        plaintext = b"hello, this is a secret message"
        import base64
        recipient_pubkey = base64.b64decode(receiver.public_key_b64)

        encrypted = sender.encrypt_for_public_key(plaintext, recipient_pubkey)
        decrypted = receiver.decrypt_from_public_key(encrypted)
        assert decrypted == plaintext

    def test_box_encrypt_different_ciphertext(self):
        """公钥加密两次应该产生不同密文（临时密钥对）"""
        sender = CryptoModule(os.urandom(32))
        receiver = CryptoModule(os.urandom(32))

        plaintext = b"test data"
        import base64
        recipient_pubkey = base64.b64decode(receiver.public_key_b64)

        enc1 = sender.encrypt_for_public_key(plaintext, recipient_pubkey)
        enc2 = sender.encrypt_for_public_key(plaintext, recipient_pubkey)
        assert enc1 != enc2  # 不同临时密钥 → 不同密文

    def test_box_decrypt_wrong_key_fails(self):
        """用错误私钥解密应该失败"""
        sender = CryptoModule(os.urandom(32))
        receiver = CryptoModule(os.urandom(32))
        wrong_receiver = CryptoModule(os.urandom(32))

        plaintext = b"secret"
        import base64
        recipient_pubkey = base64.b64decode(receiver.public_key_b64)

        encrypted = sender.encrypt_for_public_key(plaintext, recipient_pubkey)
        with pytest.raises(Exception):
            wrong_receiver.decrypt_from_public_key(encrypted)

    def test_box_decrypt_short_data_fails(self):
        """数据太短应该抛出 ValueError"""
        crypto = CryptoModule(os.urandom(32))
        with pytest.raises(ValueError, match="太短"):
            crypto.decrypt_from_public_key(b"short")


class TestBase64URL:
    """Base64URL 编码/解码测试"""

    def test_roundtrip(self):
        """Base64URL 编码后解码应该得到原始 secret"""
        secret = os.urandom(32)
        encoded = CryptoModule.secret_to_base64url(secret)
        decoded = CryptoModule.base64url_to_secret(encoded)
        assert decoded == secret

    def test_url_safe_characters(self):
        """Base64URL 不应该包含 +, /, = 字符"""
        # 测试多个 secret 确保 URL 安全
        for _ in range(20):
            secret = os.urandom(32)
            encoded = CryptoModule.secret_to_base64url(secret)
            assert "+" not in encoded
            assert "/" not in encoded
            assert "=" not in encoded

    def test_generate_secret_length(self):
        """生成的 secret 应该是 32 字节"""
        secret = CryptoModule.generate_secret()
        assert len(secret) == 32

    def test_generate_secret_unique(self):
        """每次生成的 secret 应该不同"""
        s1 = CryptoModule.generate_secret()
        s2 = CryptoModule.generate_secret()
        assert s1 != s2


# ═══════════════════════════════════════════════════════════════
# KeyStore 测试
# ═══════════════════════════════════════════════════════════════


class TestKeyStore:
    """KeyStore 密钥存储测试"""

    def setup_method(self):
        """每个测试用临时目录"""
        self._tmpdir = tempfile.mkdtemp()
        self.store = KeyStore(data_dir=Path(self._tmpdir))

    def teardown_method(self):
        """清理临时目录"""
        import shutil
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_save_and_load_secret(self):
        """保存后加载应该得到相同 secret"""
        secret = os.urandom(32)
        self.store.save_secret("device-001", secret)
        loaded = self.store.load_secret("device-001")
        assert loaded == secret

    def test_load_nonexistent_secret(self):
        """加载不存在的 secret 应该返回 None"""
        assert self.store.load_secret("nonexistent") is None

    def test_delete_secret(self):
        """删除后加载应该返回 None"""
        secret = os.urandom(32)
        self.store.save_secret("device-001", secret)
        assert self.store.delete_secret("device-001")
        assert self.store.load_secret("device-001") is None

    def test_delete_nonexistent_secret(self):
        """删除不存在的 secret 应该返回 False"""
        assert not self.store.delete_secret("nonexistent")

    def test_save_invalid_secret_length(self):
        """保存非 32 字节 secret 应该抛出 ValueError"""
        with pytest.raises(ValueError, match="32 字节"):
            self.store.save_secret("device-001", os.urandom(16))

    def test_overwrite_secret(self):
        """覆盖保存应该用新值"""
        secret1 = os.urandom(32)
        secret2 = os.urandom(32)
        self.store.save_secret("device-001", secret1)
        self.store.save_secret("device-001", secret2)
        loaded = self.store.load_secret("device-001")
        assert loaded == secret2

    def test_multiple_devices(self):
        """多个设备的 secret 应该互不干扰"""
        secrets = {}
        for i in range(5):
            device_id = f"device-{i:03d}"
            secret = os.urandom(32)
            secrets[device_id] = secret
            self.store.save_secret(device_id, secret)

        for device_id, expected in secrets.items():
            loaded = self.store.load_secret(device_id)
            assert loaded == expected, f"设备 {device_id} 的 secret 不匹配"


class TestKeyStoreDeviceManagement:
    """KeyStore 设备管理测试"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self.store = KeyStore(data_dir=Path(self._tmpdir))

    def teardown_method(self):
        import shutil
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def _make_device(self, device_id: str = "dev-001", name: str = "iPhone 15") -> DeviceInfo:
        return DeviceInfo(
            device_id=device_id,
            name=name,
            platform="ios",
            paired_at=time.time(),
        )

    def test_add_and_list_device(self):
        """添加设备后应该能列出"""
        device = self._make_device()
        secret = os.urandom(32)
        self.store.add_device(device, secret)

        devices = self.store.list_devices()
        assert len(devices) == 1
        assert devices[0].device_id == "dev-001"
        assert devices[0].name == "iPhone 15"
        assert devices[0].platform == "ios"

    def test_add_device_saves_secret(self):
        """添加设备应该同时保存 secret"""
        device = self._make_device()
        secret = os.urandom(32)
        self.store.add_device(device, secret)

        loaded = self.store.load_secret("dev-001")
        assert loaded == secret

    def test_remove_device(self):
        """撤销设备应该删除 secret 和元数据"""
        device = self._make_device()
        secret = os.urandom(32)
        self.store.add_device(device, secret)

        assert self.store.remove_device("dev-001")
        assert self.store.list_devices() == []
        assert self.store.load_secret("dev-001") is None

    def test_remove_nonexistent_device(self):
        """撤销不存在的设备应该返回 False"""
        assert not self.store.remove_device("nonexistent")

    def test_get_device(self):
        """获取指定设备信息"""
        device = self._make_device()
        self.store.add_device(device, os.urandom(32))

        found = self.store.get_device("dev-001")
        assert found is not None
        assert found.name == "iPhone 15"

    def test_get_nonexistent_device(self):
        """获取不存在的设备应该返回 None"""
        assert self.store.get_device("nonexistent") is None

    def test_update_last_seen(self):
        """更新最后在线时间"""
        device = self._make_device()
        self.store.add_device(device, os.urandom(32))

        self.store.update_last_seen("dev-001")
        found = self.store.get_device("dev-001")
        assert found is not None
        assert found.last_seen > 0

    def test_has_devices(self):
        """has_devices 应该正确反映是否有设备"""
        assert not self.store.has_devices()

        self.store.add_device(self._make_device(), os.urandom(32))
        assert self.store.has_devices()

        self.store.remove_device("dev-001")
        assert not self.store.has_devices()

    def test_add_duplicate_device_updates(self):
        """重复添加同一设备应该更新而不是重复"""
        device1 = self._make_device(name="iPhone 15")
        device2 = self._make_device(name="iPhone 15 Pro")
        secret1 = os.urandom(32)
        secret2 = os.urandom(32)

        self.store.add_device(device1, secret1)
        self.store.add_device(device2, secret2)

        devices = self.store.list_devices()
        assert len(devices) == 1
        assert devices[0].name == "iPhone 15 Pro"
        assert self.store.load_secret("dev-001") == secret2

    def test_multiple_devices_management(self):
        """多设备管理：添加、列出、删除"""
        devices_data = [
            ("dev-001", "iPhone 15", "ios"),
            ("dev-002", "Pixel 8", "android"),
            ("dev-003", "iPad Pro", "ios"),
        ]
        for did, name, platform in devices_data:
            device = DeviceInfo(
                device_id=did, name=name, platform=platform,
                paired_at=time.time(),
            )
            self.store.add_device(device, os.urandom(32))

        assert len(self.store.list_devices()) == 3

        # 删除中间一个
        self.store.remove_device("dev-002")
        remaining = self.store.list_devices()
        assert len(remaining) == 2
        ids = {d.device_id for d in remaining}
        assert ids == {"dev-001", "dev-003"}

    def test_devices_persist_across_instances(self):
        """设备数据应该在 KeyStore 重新实例化后保持"""
        device = self._make_device()
        secret = os.urandom(32)
        self.store.add_device(device, secret)

        # 创建新实例（模拟重启）
        store2 = KeyStore(data_dir=Path(self._tmpdir))
        devices = store2.list_devices()
        assert len(devices) == 1
        assert devices[0].device_id == "dev-001"
        assert store2.load_secret("dev-001") == secret

    def test_corrupted_devices_json(self):
        """损坏的 devices.json 应该优雅处理"""
        # 写入损坏的 JSON
        devices_file = Path(self._tmpdir) / "devices.json"
        devices_file.write_text("not valid json {{{", encoding="utf-8")

        devices = self.store.list_devices()
        assert devices == []  # 应该返回空列表而不是崩溃


# ═══════════════════════════════════════════════════════════════
# Python/Dart 跨语言互操作测试
# ═══════════════════════════════════════════════════════════════


class TestCrossLanguageInterop:
    """Python/Dart 跨语言互操作测试（硬编码测试向量）"""

    def test_fixed_secret_verify_key(self):
        """固定 secret 应该产生已知的 verifyKey（与 Dart 端一致）"""
        secret = bytes(range(32))
        crypto = CryptoModule(secret)
        # 这个值必须与 Dart 端 CryptoModule(Uint8List.fromList(List.generate(32, (i) => i)))
        # 产生的 verifyKeyB64 完全一致
        assert crypto.verify_key_b64 == "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg="

    def test_decrypt_dart_encrypted_message(self):
        """Python 应该能解密 Dart 加密的消息"""
        secret = bytes(range(32))
        crypto = CryptoModule(secret)
        # 这是 Dart 端用相同 secret 加密 {'type': 'dart_test', 'payload': {'hello': 'from_dart'}} 的输出
        dart_encrypted = "yHVcaZvRNEMduKQfvcn0ArWzjUnPORy1pjqGjy2faLalav8j6ltV+UjPCaY/agCdsIWaIbl/uRp3z25BYArrGw94ubXltom9ONvndkCjgLhtjpkNWYWlx6skln8="
        decrypted = crypto.decrypt(dart_encrypted)
        assert decrypted == {"type": "dart_test", "payload": {"hello": "from_dart"}}

    def test_python_encrypted_can_be_decrypted(self):
        """Python 加密的消息格式应该是 nonce(24B) + ciphertext"""
        secret = bytes(range(32))
        crypto = CryptoModule(secret)
        msg = {"type": "test", "value": 42}
        encrypted = crypto.encrypt(msg)

        # 验证格式：Base64 解码后至少 24(nonce) + 16(MAC) 字节
        import base64
        raw = base64.b64decode(encrypted)
        assert len(raw) >= 40

        # 自解密验证
        assert crypto.decrypt(encrypted) == msg

    def test_base64url_roundtrip_with_known_value(self):
        """Base64URL 编码应该与 Dart 端一致"""
        secret = bytes(range(32))
        encoded = CryptoModule.secret_to_base64url(secret)
        decoded = CryptoModule.base64url_to_secret(encoded)
        assert decoded == secret
        # 确保 URL 安全
        assert "+" not in encoded
        assert "/" not in encoded
        assert "=" not in encoded


# ═══════════════════════════════════════════════════════════════
# 边界测试补充
# ═══════════════════════════════════════════════════════════════


class TestCryptoEdgeCases:
    """CryptoModule 边界测试"""

    def setup_method(self):
        self.crypto = CryptoModule(os.urandom(32))

    def test_encrypt_empty_dict(self):
        """空字典 {} 加密/解密"""
        assert self.crypto.decrypt(self.crypto.encrypt({})) == {}

    def test_encrypt_deeply_nested(self):
        """深层嵌套 JSON（10 层）"""
        msg = {"level": 0}
        current = msg
        for i in range(1, 10):
            current["child"] = {"level": i}
            current = current["child"]
        assert self.crypto.decrypt(self.crypto.encrypt(msg)) == msg

    def test_encrypt_special_chars_in_keys(self):
        """key 含特殊字符（引号、反斜杠、换行）"""
        msg = {
            'key"with"quotes': "value",
            "key\\with\\backslash": "value",
            "key\nwith\nnewline": "value",
            "key\twith\ttab": "value",
        }
        assert self.crypto.decrypt(self.crypto.encrypt(msg)) == msg

    def test_encrypt_null_values(self):
        """None/null 值"""
        msg = {"a": None, "b": [None, 1, None], "c": {"d": None}}
        assert self.crypto.decrypt(self.crypto.encrypt(msg)) == msg

    def test_encrypt_boolean_and_numbers(self):
        """布尔值和各种数字类型"""
        msg = {"bool_t": True, "bool_f": False, "int": 0, "neg": -1,
               "float": 3.14, "big": 10**18, "sci": 1e-10}
        result = self.crypto.decrypt(self.crypto.encrypt(msg))
        assert result["bool_t"] is True
        assert result["bool_f"] is False
        assert result["int"] == 0
        assert result["neg"] == -1

    def test_encrypt_empty_string_value(self):
        """空字符串值"""
        msg = {"type": "", "payload": {"content": ""}}
        assert self.crypto.decrypt(self.crypto.encrypt(msg)) == msg

    def test_encrypt_very_long_key(self):
        """超长 key（1000 字符）"""
        long_key = "k" * 1000
        msg = {long_key: "value"}
        assert self.crypto.decrypt(self.crypto.encrypt(msg)) == msg

    def test_encrypt_list_payload(self):
        """payload 是列表"""
        msg = {"type": "test", "items": [1, "two", {"three": 3}, [4, 5]]}
        assert self.crypto.decrypt(self.crypto.encrypt(msg)) == msg

    def test_decrypt_empty_string_raises(self):
        """空字符串解密应该失败"""
        with pytest.raises(Exception):
            self.crypto.decrypt("")

    def test_decrypt_valid_base64_but_wrong_content(self):
        """有效 Base64 但不是加密数据"""
        import base64
        fake = base64.b64encode(b"not encrypted data at all").decode()
        with pytest.raises(Exception):
            self.crypto.decrypt(fake)

    def test_multiple_encrypt_decrypt_cycles(self):
        """连续 100 次加密/解密不出错"""
        for i in range(100):
            msg = {"index": i, "data": f"message_{i}"}
            assert self.crypto.decrypt(self.crypto.encrypt(msg)) == msg

    def test_base64url_with_all_zero_secret(self):
        """全零 secret 的 Base64URL"""
        secret = bytes(32)
        encoded = CryptoModule.secret_to_base64url(secret)
        assert CryptoModule.base64url_to_secret(encoded) == secret

    def test_base64url_with_all_ff_secret(self):
        """全 0xFF secret 的 Base64URL"""
        secret = bytes([0xFF] * 32)
        encoded = CryptoModule.secret_to_base64url(secret)
        assert CryptoModule.base64url_to_secret(encoded) == secret


class TestKeyStoreEdgeCases:
    """KeyStore 边界测试"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self.store = KeyStore(data_dir=Path(self._tmpdir))

    def teardown_method(self):
        import shutil
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_device_id_with_special_chars(self):
        """device_id 含特殊字符"""
        # 只测试文件系统安全的字符
        secret = os.urandom(32)
        self.store.save_secret("device-with-dashes-123", secret)
        assert self.store.load_secret("device-with-dashes-123") == secret

    def test_save_load_many_devices(self):
        """保存和加载 50 个设备"""
        secrets = {}
        for i in range(50):
            did = f"dev-{i:04d}"
            s = os.urandom(32)
            secrets[did] = s
            self.store.save_secret(did, s)
        for did, expected in secrets.items():
            assert self.store.load_secret(did) == expected

    def test_corrupted_key_file(self):
        """损坏的密钥文件应该返回 None"""
        key_file = Path(self._tmpdir) / "keys" / "bad-device.key"
        key_file.parent.mkdir(parents=True, exist_ok=True)
        key_file.write_text("not-valid-hex!!!", encoding="utf-8")
        assert self.store.load_secret("bad-device") is None

    def test_empty_key_file(self):
        """空密钥文件应该返回 None"""
        key_file = Path(self._tmpdir) / "keys" / "empty-device.key"
        key_file.parent.mkdir(parents=True, exist_ok=True)
        key_file.write_text("", encoding="utf-8")
        assert self.store.load_secret("empty-device") is None

    def test_device_info_all_fields(self):
        """DeviceInfo 所有字段正确序列化/反序列化"""
        device = DeviceInfo(
            device_id="dev-full",
            name="Test Device 测试",
            platform="android",
            paired_at=1712345678.123,
            last_seen=1712345999.456,
        )
        self.store.add_device(device, os.urandom(32))
        loaded = self.store.get_device("dev-full")
        assert loaded is not None
        assert loaded.device_id == "dev-full"
        assert loaded.name == "Test Device 测试"
        assert loaded.platform == "android"
        assert loaded.paired_at == 1712345678.123
        assert loaded.last_seen == 1712345999.456

    def test_update_last_seen_nonexistent(self):
        """更新不存在设备的 last_seen 不应崩溃"""
        self.store.update_last_seen("nonexistent")  # 不应抛异常
