"""Relay pairing payload encode/decode tests.

Tests cover:
  1. Round-trip property: encode then decode produces the original triple.
  2. Example-based tests for known values, invalid inputs, and edge cases.

# Feature: connection-architecture-overhaul
"""

from __future__ import annotations

import os

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from mobileflow_agent.crypto.relay_pairing import encode_relay_pairing, decode_relay_pairing


# ═══════════════════════════════════════════════════════════════
# Property-based tests (Hypothesis)
# ═══════════════════════════════════════════════════════════════


# Feature: connection-architecture-overhaul, Property 3: Relay pairing payload round-trip
class TestRelayPairingRoundTripProperty:
    """Property: for any valid (relay_url, device_id, shared_secret),
    encode then decode produces the original triple."""

    @given(
        relay_url=st.text(
            min_size=1,
            max_size=200,
            alphabet=st.characters(whitelist_categories=("L", "N", "P", "S")),
        ),
        device_id=st.binary(min_size=16, max_size=16),
        shared_secret=st.binary(min_size=32, max_size=32),
    )
    @settings(max_examples=100)
    def test_encode_decode_roundtrip(
        self, relay_url: str, device_id: bytes, shared_secret: bytes
    ):
        encoded = encode_relay_pairing(relay_url, device_id, shared_secret)
        decoded = decode_relay_pairing(encoded)

        assert decoded.relay_url == relay_url
        assert decoded.device_id == device_id
        assert decoded.shared_secret == shared_secret


# ═══════════════════════════════════════════════════════════════
# Example-based unit tests
# ═══════════════════════════════════════════════════════════════


class TestRelayPairingExamples:
    """Concrete example tests for relay pairing encode/decode."""

    def test_encode_decode_basic(self):
        """Basic round-trip with known values."""
        url = "wss://relay.example.com"
        device_id = b"\x01" * 16
        secret = b"\xab" * 32

        encoded = encode_relay_pairing(url, device_id, secret)
        decoded = decode_relay_pairing(encoded)

        assert decoded.relay_url == url
        assert decoded.device_id == device_id
        assert decoded.shared_secret == secret

    def test_decode_invalid_version(self):
        """Wrong version byte raises ValueError."""
        import base64
        import struct

        url_bytes = b"wss://relay.example.com"
        # Version 0xFF instead of 0x01
        payload = (
            struct.pack(">BH", 0xFF, len(url_bytes))
            + url_bytes
            + b"\x00" * 16
            + b"\x00" * 32
        )
        encoded = base64.urlsafe_b64encode(payload).rstrip(b"=").decode("ascii")

        with pytest.raises(ValueError, match="版本"):
            decode_relay_pairing(encoded)

    def test_decode_too_short(self):
        """Truncated payload raises ValueError."""
        import base64

        # Only 10 bytes — way too short for the minimum payload
        short_payload = b"\x01" + b"\x00" * 9
        encoded = base64.urlsafe_b64encode(short_payload).rstrip(b"=").decode("ascii")

        with pytest.raises(ValueError):
            decode_relay_pairing(encoded)

    def test_decode_invalid_base64(self):
        """Garbage input raises ValueError."""
        with pytest.raises(ValueError):
            decode_relay_pairing("!!!not-base64-at-all!!!")

    def test_encode_empty_url_raises(self):
        """Empty relay_url raises ValueError."""
        with pytest.raises(ValueError, match="empty"):
            encode_relay_pairing("", b"\x00" * 16, b"\x00" * 32)

    def test_encode_wrong_device_id_length(self):
        """Wrong device_id length raises ValueError."""
        with pytest.raises(ValueError, match="16 bytes"):
            encode_relay_pairing("wss://relay.example.com", b"\x00" * 8, b"\x00" * 32)

    def test_encode_wrong_secret_length(self):
        """Wrong secret length raises ValueError."""
        with pytest.raises(ValueError, match="32 bytes"):
            encode_relay_pairing("wss://relay.example.com", b"\x00" * 16, b"\x00" * 16)
