"""
加密模块（crypto）

模块职责：
  1. 端到端加密/解密（TweetNaCl secretbox）
  2. Ed25519 签名认证（用于 Relay Server 认证）
  3. 密钥生成、派生、持久化存储

被谁调用：
  - server/connection_manager.py（Relay 模式消息加密/解密）
  - daemon/manager.py（Relay 认证）
  - CLI 命令（pair、devices、keys）

参考实现：
  - Happy encryption.ts：secretbox + box + Ed25519 authChallenge
  - Happy auth.ts：签名 challenge-response 认证

依赖：
  - PyNaCl（libsodium Python 绑定）
  - keyring（系统密钥存储）
"""

from .crypto_module import CryptoModule
from .key_store import KeyStore, DeviceInfo
from .relay_pairing import (
    RelayPairingPayload,
    encode_relay_pairing,
    decode_relay_pairing,
)

__all__ = [
    "CryptoModule",
    "KeyStore",
    "DeviceInfo",
    "RelayPairingPayload",
    "encode_relay_pairing",
    "decode_relay_pairing",
]
