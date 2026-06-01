"""Self-signed TLS certificate generator for Tunnel mode.

Generates a 2048-bit RSA key pair and self-signed X.509 certificate
for local development and internal network use. Certificates are stored
in ~/.mobileflow/certs/ with restrictive file permissions.

Security notes:
  - Self-signed certs are suitable for dev/internal use only.
  - For production, users should provide their own CA-signed certificates.
  - Private key files are created with 600 permissions (owner-only read/write).
"""

import os
import platform
import datetime
from pathlib import Path
from typing import Any

from loguru import logger


# Certificate storage directory under user home
_CERTS_DIR_NAME = ".mobileflow/certs"

# Certificate validity period
_CERT_VALIDITY_DAYS = 365


def _get_certs_dir() -> Path:
    """Get the certificate storage directory, creating it if needed.

    Returns:
        Path to ~/.mobileflow/certs/ directory.

    Raises:
        OSError: If directory creation fails.
    """
    certs_dir = Path.home() / _CERTS_DIR_NAME
    certs_dir.mkdir(parents=True, exist_ok=True)
    return certs_dir


def _restrict_file_permissions(file_path: Path) -> None:
    """Set restrictive permissions on a private key file.

    On Unix: chmod 600 (owner read/write only).
    On Windows: relies on user home directory ACLs (no chmod equivalent).

    Args:
        file_path: Path to the file to restrict.
    """
    if platform.system() != "Windows":
        os.chmod(file_path, 0o600)


def generate_self_signed_cert(
    common_name: str = "MobileFlow Tunnel",
    san_entries: list[str] | None = None,
) -> dict[str, Any]:
    """Generate a self-signed TLS certificate and private key.

    Creates an RSA 2048-bit key pair and a self-signed X.509 certificate
    with Subject Alternative Names for localhost and common local IPs.
    Files are written to ~/.mobileflow/certs/.

    If certificate files already exist, they are overwritten (user explicitly
    requested regeneration via the Dashboard button).

    Args:
        common_name: Certificate CN field. Defaults to "MobileFlow Tunnel".
        san_entries: Additional SAN DNS/IP entries. If None, uses sensible
            defaults (localhost, 127.0.0.1, local network IPs).

    Returns:
        Dict with keys:
          - cert_path: Absolute path to the generated certificate PEM file.
          - key_path: Absolute path to the generated private key PEM file.
          - expires: ISO format expiration date string.

    Raises:
        ImportError: If the cryptography library is not installed.
        Exception: If certificate generation or file writing fails.
    """
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    import ipaddress

    logger.info(f"生成自签名证书: CN={common_name}")

    # Generate RSA private key
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    # Build Subject Alternative Names
    san_list: list[x509.GeneralName] = [
        x509.DNSName("localhost"),
        x509.IPAddress(ipaddress.IPv4Address("127.0.0.1")),
        x509.IPAddress(ipaddress.IPv6Address("::1")),
    ]

    # Add local network IPs for convenience
    try:
        import socket
        local_ip = socket.gethostbyname(socket.gethostname())
        if local_ip and local_ip != "127.0.0.1":
            san_list.append(x509.IPAddress(ipaddress.IPv4Address(local_ip)))
            logger.debug(f"SAN 添加本机 IP: {local_ip}")
    except Exception:
        pass

    # Add user-specified SAN entries
    if san_entries:
        for entry in san_entries:
            try:
                san_list.append(x509.IPAddress(ipaddress.ip_address(entry)))
            except ValueError:
                san_list.append(x509.DNSName(entry))

    # Build certificate
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "MobileFlow"),
    ])

    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=_CERT_VALIDITY_DAYS))
        .add_extension(x509.SubjectAlternativeName(san_list), critical=False)
        .add_extension(
            x509.BasicConstraints(ca=False, path_length=None), critical=True
        )
        .sign(key, hashes.SHA256())
    )

    # Write files
    certs_dir = _get_certs_dir()
    cert_path = certs_dir / "tunnel-cert.pem"
    key_path = certs_dir / "tunnel-key.pem"

    # Write private key (PEM, no encryption — stored locally)
    key_path.write_bytes(
        key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    _restrict_file_permissions(key_path)

    # Write certificate
    cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))

    expires = (now + datetime.timedelta(days=_CERT_VALIDITY_DAYS)).isoformat()
    logger.info(f"证书已生成: cert={cert_path}, key={key_path}, expires={expires}")

    return {
        "cert_path": str(cert_path),
        "key_path": str(key_path),
        "expires": expires,
    }
