"""Relay pairing payload encode/decode.

Versioned binary format for exchanging relay connection parameters
between Agent and App via QR code or manual text entry.

Version 1 wire format:
  Byte 0:     version (0x01)
  Bytes 1-2:  relay_url length (uint16 big-endian)
  Bytes 3-N:  relay_url (UTF-8)
  Bytes N+1 to N+16: device_id (16 bytes raw)
  Bytes N+17 to N+48: shared_secret (32 bytes raw)

The entire payload is Base64URL-encoded (no padding) for compact
representation in QR codes and manual text entry.
"""

import base64
import struct
from dataclasses import dataclass

from loguru import logger

# Current payload format version — increment when wire format changes
_PAYLOAD_VERSION = 0x01

# Fixed field sizes (bytes)
_DEVICE_ID_LEN = 16
_SHARED_SECRET_LEN = 32

# Minimum payload: version(1) + url_len(2) + url(>=1) + device_id(16) + secret(32)
_MIN_PAYLOAD_LEN = 1 + 2 + 1 + _DEVICE_ID_LEN + _SHARED_SECRET_LEN


@dataclass(frozen=True)
class RelayPairingPayload:
    """Decoded relay pairing payload.

    Attributes:
        relay_url: Relay server WebSocket URL (e.g. "wss://relay.example.com").
        device_id: 16-byte device identifier (raw bytes).
        shared_secret: 32-byte shared secret for E2E encryption.
    """

    relay_url: str
    device_id: bytes  # 16 bytes
    shared_secret: bytes  # 32 bytes


def encode_relay_pairing(
    relay_url: str,
    device_id: bytes,
    shared_secret: bytes,
) -> str:
    """Encode relay pairing parameters into a Base64URL string.

    Packs (relay_url, device_id, shared_secret) into the versioned binary
    format and returns a Base64URL-encoded string without padding, suitable
    for embedding in QR codes or displaying as copyable text.

    Args:
        relay_url: Relay server URL (e.g. "wss://relay.example.com").
            Must be a non-empty UTF-8 string whose encoded length fits
            in a uint16 (≤ 65535 bytes).
        device_id: 16-byte device identifier.
        shared_secret: 32-byte shared secret for E2E encryption.

    Returns:
        Base64URL-encoded string (no padding).

    Raises:
        ValueError: If device_id is not 16 bytes, shared_secret is not
            32 bytes, or relay_url is empty / too long.
    """
    if len(device_id) != _DEVICE_ID_LEN:
        raise ValueError(
            f"device_id must be {_DEVICE_ID_LEN} bytes, got {len(device_id)}"
        )
    if len(shared_secret) != _SHARED_SECRET_LEN:
        raise ValueError(
            f"shared_secret must be {_SHARED_SECRET_LEN} bytes, got {len(shared_secret)}"
        )

    url_bytes = relay_url.encode("utf-8")
    if len(url_bytes) == 0:
        raise ValueError("relay_url must not be empty")
    if len(url_bytes) > 0xFFFF:
        raise ValueError(
            f"relay_url too long: {len(url_bytes)} bytes (max 65535)"
        )

    # Pack: version(1B) + url_len(2B big-endian) + url + device_id + secret
    payload = (
        struct.pack(">BH", _PAYLOAD_VERSION, len(url_bytes))
        + url_bytes
        + device_id
        + shared_secret
    )

    # Base64URL without padding — compact for QR codes
    encoded = base64.urlsafe_b64encode(payload).rstrip(b"=").decode("ascii")
    logger.debug(
        f"Relay 配对码已编码: url_len={len(url_bytes)}, "
        f"payload_len={len(payload)}, encoded_len={len(encoded)}"
    )
    return encoded


def decode_relay_pairing(encoded: str) -> RelayPairingPayload:
    """Decode a Base64URL relay pairing string.

    Parses the versioned binary format and returns the extracted
    (relay_url, device_id, shared_secret) triple.

    Args:
        encoded: Base64URL-encoded pairing string (with or without padding).

    Returns:
        RelayPairingPayload with relay_url, device_id, shared_secret.

    Raises:
        ValueError: If the payload is invalid, wrong version, or too short.
    """
    # Restore padding — Base64 requires length to be a multiple of 4
    remainder = len(encoded) % 4
    padded = encoded + "=" * ((4 - remainder) % 4)

    try:
        raw = base64.urlsafe_b64decode(padded)
    except Exception as e:
        raise ValueError(f"Base64URL 解码失败: {e}") from e

    if len(raw) < _MIN_PAYLOAD_LEN:
        raise ValueError(
            f"配对码载荷过短: 最少 {_MIN_PAYLOAD_LEN} 字节, 实际 {len(raw)}"
        )

    version = raw[0]
    if version != _PAYLOAD_VERSION:
        raise ValueError(f"不支持的配对码版本: {version}")

    url_len = struct.unpack(">H", raw[1:3])[0]
    expected_len = 3 + url_len + _DEVICE_ID_LEN + _SHARED_SECRET_LEN
    if len(raw) < expected_len:
        raise ValueError(
            f"配对码载荷长度不匹配: 期望 {expected_len}, 实际 {len(raw)}"
        )

    # Extract fields
    offset = 3
    relay_url = raw[offset : offset + url_len].decode("utf-8")
    offset += url_len
    device_id = bytes(raw[offset : offset + _DEVICE_ID_LEN])
    offset += _DEVICE_ID_LEN
    shared_secret = bytes(raw[offset : offset + _SHARED_SECRET_LEN])

    logger.debug(
        f"Relay 配对码已解码: version={version}, "
        f"relay_url={relay_url[:40]}{'...' if len(relay_url) > 40 else ''}, "
        f"device_id_len={len(device_id)}"
    )
    return RelayPairingPayload(
        relay_url=relay_url,
        device_id=device_id,
        shared_secret=shared_secret,
    )
