"""End-to-end encryption module using NaCl (libsodium).

Module: crypto/
Responsibility:
    1. Message encryption / decryption (NaCl secretbox, XSalsa20-Poly1305).
    2. Ed25519 signature authentication (Relay Server challenge-response).
    3. X25519 key exchange (public-key encryption during pairing).
    4. Key derivation (from a 32-byte secret to signing and encryption keys).

Called by:
    - server/connection_manager.py (Relay mode message encrypt/decrypt).
    - daemon/manager.py (Relay authentication).

Reference implementations:
    - Happy ``encryption.ts`` ``encryptLegacy`` / ``decryptLegacy`` (secretbox).
    - Happy ``encryption.ts`` ``authChallenge`` (Ed25519 signing).
    - Happy ``encryption.ts`` ``libsodiumEncryptForPublicKey`` (box).

Wire formats (compatible with Happy legacy mode):
    secretbox: ``nonce(24B) + ciphertext``
    box:       ``ephemeral_pubkey(32B) + nonce(24B) + ciphertext``
"""

from __future__ import annotations

import base64
import json
import os
from dataclasses import dataclass
from typing import Any, Optional

import nacl.secret
import nacl.signing
import nacl.public
import nacl.utils
from nacl.exceptions import CryptoError

from loguru import logger


@dataclass
class AuthChallenge:
    """Ed25519 signed authentication challenge (Happy ``auth.ts`` pattern).

    Attributes:
        challenge: Base64-encoded 32-byte random challenge.
        public_key: Base64-encoded Ed25519 public (verify) key.
        signature: Base64-encoded Ed25519 signature over the challenge.
    """
    challenge: str
    public_key: str
    signature: str


class CryptoModule:
    """End-to-end encryption module backed by NaCl (libsodium).

    Provides three cryptographic primitives:
        - secretbox: XSalsa20-Poly1305 symmetric encryption (message traffic).
        - box: X25519 ECDH + XSalsa20-Poly1305 (key exchange during pairing).
        - sign: Ed25519 signatures (Relay Server authentication).

    Initialised from a 32-byte shared secret that serves as both the
    symmetric encryption key and the Ed25519 signing key seed.

    Attributes:
        public_key_b64: Base64-encoded X25519 public key.
        verify_key_b64: Base64-encoded Ed25519 verification key.
    """

    def __init__(self, secret: bytes):
        """Initialise the crypto module from a 32-byte shared secret.

        Args:
            secret: 32-byte key seed shared between Agent and App during pairing.

        Raises:
            ValueError: If ``secret`` is not exactly 32 bytes.
        """
        if len(secret) != 32:
            raise ValueError(f"secret 必须是 32 字节，实际 {len(secret)} 字节")

        self._secret = secret

        # Symmetric encryption (message traffic)
        self._secretbox = nacl.secret.SecretBox(secret)

        # Ed25519 signing key (Relay authentication)
        self._signing_key = nacl.signing.SigningKey(seed=secret)
        self._verify_key = self._signing_key.verify_key

        # X25519 encryption key (pairing key exchange)
        # Derived via Ed25519 → X25519 conversion
        self._private_key = self._signing_key.to_curve25519_private_key()
        self._public_key = self._private_key.public_key

        logger.debug(
            f"CryptoModule 初始化完成: "
            f"verify_key={base64.b64encode(self._verify_key.encode()).decode()[:16]}..."
        )

    # ── Symmetric encryption (secretbox — message traffic) ──

    def encrypt(self, message: dict[str, Any]) -> str:
        """Encrypt a MobileFlow message dict to a Base64 string.

        Pipeline: JSON serialise → UTF-8 encode → secretbox encrypt → Base64 encode.
        Output format: ``Base64(nonce(24B) + ciphertext)``.

        Args:
            message: MobileFlow message dict (e.g. ``{"type": "chat.send", ...}``).

        Returns:
            Base64-encoded encrypted payload.

        Raises:
            TypeError: If ``message`` is not JSON-serialisable.
        """
        plaintext = json.dumps(message, ensure_ascii=False).encode("utf-8")
        # SecretBox.encrypt() auto-generates a random nonce and prepends it
        encrypted = self._secretbox.encrypt(plaintext)
        # logger.debug(f"消息加密完成: size={len(plaintext)}B → {len(encrypted)}B")
        return base64.b64encode(bytes(encrypted)).decode("ascii")

    def decrypt(self, ciphertext_b64: str) -> dict[str, Any]:
        """Decrypt a Base64 string back to a MobileFlow message dict.

        Pipeline: Base64 decode → secretbox decrypt → UTF-8 decode → JSON parse.

        Args:
            ciphertext_b64: Base64-encoded encrypted payload.

        Returns:
            Decrypted MobileFlow message dict.

        Raises:
            CryptoError: If decryption fails (tampered ciphertext or wrong key).
            json.JSONDecodeError: If the decrypted data is not valid JSON.
        """
        encrypted = base64.b64decode(ciphertext_b64)
        plaintext = self._secretbox.decrypt(encrypted)
        # logger.debug(f"消息解密完成: size={len(encrypted)}B → {len(plaintext)}B")
        return json.loads(plaintext.decode("utf-8"))

    # ── Ed25519 signature authentication (Relay Server) ──

    def auth_challenge(self) -> AuthChallenge:
        """Generate a signed authentication challenge for the Relay Server.

        Follows the Happy ``auth.ts`` ``authChallenge`` pattern:
        1. Generate a 32-byte random challenge.
        2. Sign it with the Ed25519 private key.
        3. Return challenge + public key + signature (all Base64-encoded).

        The Relay Server verifies the signature, confirms the public key is
        registered, and returns an auth token.

        Returns:
            An AuthChallenge dataclass.
        """
        challenge = os.urandom(32)
        signed = self._signing_key.sign(challenge)
        signature = signed.signature

        return AuthChallenge(
            challenge=base64.b64encode(challenge).decode("ascii"),
            public_key=base64.b64encode(
                self._verify_key.encode()
            ).decode("ascii"),
            signature=base64.b64encode(signature).decode("ascii"),
        )

    @staticmethod
    def verify_challenge(
        challenge_b64: str,
        public_key_b64: str,
        signature_b64: str,
    ) -> bool:
        """Verify a signed authentication challenge (used by the Relay Server).

        Args:
            challenge_b64: Base64-encoded 32-byte challenge.
            public_key_b64: Base64-encoded Ed25519 public key.
            signature_b64: Base64-encoded Ed25519 signature.

        Returns:
            True if the signature is valid, False otherwise.
        """
        try:
            challenge = base64.b64decode(challenge_b64)
            public_key_bytes = base64.b64decode(public_key_b64)
            signature = base64.b64decode(signature_b64)

            verify_key = nacl.signing.VerifyKey(public_key_bytes)
            verify_key.verify(challenge, signature)
            logger.debug("签名验证成功")
            return True
        except (CryptoError, ValueError, Exception) as e:
            logger.warning(f"签名验证失败: {e}")
            return False

    # ── Public-key encryption (box — pairing phase) ──

    def encrypt_for_public_key(
        self, data: bytes, recipient_public_key: bytes
    ) -> bytes:
        """Encrypt data for a recipient using their X25519 public key.

        Uses an ephemeral key pair for forward secrecy (Happy
        ``libsodiumEncryptForPublicKey`` pattern).

        Output format: ``ephemeral_pubkey(32B) + nonce(24B) + ciphertext``.

        Args:
            data: Raw data to encrypt.
            recipient_public_key: Recipient's X25519 public key (32 bytes).

        Returns:
            Encrypted bytes: ephemeral public key + nonce + ciphertext.
        """
        # Ephemeral key pair for forward secrecy
        ephemeral_key = nacl.public.PrivateKey.generate()
        recipient_key = nacl.public.PublicKey(recipient_public_key)

        # Box encryption (X25519 ECDH + XSalsa20-Poly1305)
        box = nacl.public.Box(ephemeral_key, recipient_key)
        encrypted = box.encrypt(data)  # Auto-generates nonce

        # Concatenate: ephemeral public key + encrypted data (includes nonce)
        return bytes(ephemeral_key.public_key) + bytes(encrypted)

    def decrypt_from_public_key(self, data: bytes) -> bytes:
        """Decrypt data that was encrypted with our public key.

        Input format: ``ephemeral_pubkey(32B) + nonce(24B) + ciphertext``.

        Args:
            data: Encrypted bytes.

        Returns:
            Decrypted raw data.

        Raises:
            CryptoError: If decryption fails.
            ValueError: If the data is too short.
        """
        if len(data) < 32 + 24 + 16:  # pubkey + nonce + min ciphertext (MAC)
            raise ValueError(
                f"加密数据太短: {len(data)} 字节，最少需要 72 字节"
            )

        ephemeral_pubkey = nacl.public.PublicKey(data[:32])
        encrypted = data[32:]

        box = nacl.public.Box(self._private_key, ephemeral_pubkey)
        return box.decrypt(encrypted)

    # ── Utility methods ──

    @property
    def public_key_b64(self) -> str:
        """Return the X25519 public key as a Base64 string."""
        return base64.b64encode(bytes(self._public_key)).decode("ascii")

    @property
    def verify_key_b64(self) -> str:
        """Return the Ed25519 verification key as a Base64 string."""
        return base64.b64encode(self._verify_key.encode()).decode("ascii")

    @staticmethod
    def generate_secret() -> bytes:
        """Generate a random 32-byte secret for a new pairing.

        Returns:
            32 random bytes.
        """
        return os.urandom(32)

    @staticmethod
    def secret_to_base64url(secret: bytes) -> str:
        """Encode a secret as Base64URL (for QR codes / deep links).

        Args:
            secret: 32-byte secret.

        Returns:
            Base64URL-encoded string (no padding).
        """
        return base64.urlsafe_b64encode(secret).decode("ascii").rstrip("=")

    @staticmethod
    def base64url_to_secret(b64url: str) -> bytes:
        """Decode a Base64URL string back to a secret.

        Args:
            b64url: Base64URL-encoded string (with or without padding).

        Returns:
            Decoded bytes.
        """
        # Restore padding
        padding = 4 - len(b64url) % 4
        if padding != 4:
            b64url += "=" * padding
        return base64.urlsafe_b64decode(b64url)
