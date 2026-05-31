"""
Relay Server authentication module.

Ed25519 signature challenge-response authentication.
"""

from __future__ import annotations

import base64
import secrets
import time
from dataclasses import dataclass, field

import nacl.signing
from nacl.exceptions import CryptoError


@dataclass
class AuthToken:
    """Authentication token."""
    token: str
    device_id: str
    public_key: str  # Base64-encoded Ed25519 public key
    created_at: float = field(default_factory=time.time)
    expires_at: float = 0.0

    def __post_init__(self):
        if self.expires_at == 0.0:
            self.expires_at = self.created_at + 3600  # 1 hour expiry


def verify_ed25519_challenge(
    challenge_b64: str,
    public_key_b64: str,
    signature_b64: str,
) -> bool:
    """Verify an Ed25519 signature challenge.

    Args:
        challenge_b64: Base64-encoded challenge.
        public_key_b64: Base64-encoded Ed25519 public key.
        signature_b64: Base64-encoded signature.

    Returns:
        True if the signature is valid.
    """
    try:
        challenge = base64.b64decode(challenge_b64)
        public_key = base64.b64decode(public_key_b64)
        signature = base64.b64decode(signature_b64)

        verify_key = nacl.signing.VerifyKey(public_key)
        verify_key.verify(challenge, signature)
        return True
    except (CryptoError, ValueError, Exception):
        return False


def generate_auth_token(device_id: str, public_key_b64: str) -> AuthToken:
    """Generate an authentication token."""
    return AuthToken(
        token=secrets.token_urlsafe(32),
        device_id=device_id,
        public_key=public_key_b64,
    )
