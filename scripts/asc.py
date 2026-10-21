#!/usr/bin/env python3
"""App Store Connect API helpers (Python standard library plus the openssl CLI).

Subcommands:
  write-key             Write ASC_KEY_P8 to a .p8 file (accepts real newlines, literal "\\n" or base64).
  check                 Verify that the API key works and that at least one iOS device is registered.
  keychain-serials      Print the serial numbers of the "Apple Development" certificates in the keychains.
  revoke-new-dev-certs  Revoke the development certificates created since a keychain-serials snapshot.

Environment: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the file written by write-key).
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Callable, Dict, List, Optional, Tuple

API_ROOT = "https://api.appstoreconnect.apple.com"
TOKEN_LIFETIME = 20 * 60
DEVELOPMENT_CERTIFICATE_TYPES = "DEVELOPMENT,IOS_DEVELOPMENT"
CERTIFICATE_PATTERN = re.compile(r"-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----", re.S)


class AscError(Exception):
    def __init__(self, status: int, detail: str) -> None:
        super().__init__(f"HTTP {status}: {detail}")
        self.status = status
        self.detail = detail


# MARK: - Key handling


def normalize_private_key(raw: str) -> str:
    """Returns the PEM text of an App Store Connect .p8 key stored in a secret."""
    text = raw.strip()
    if "\\n" in text and "\n" not in text:
        text = text.replace("\\n", "\n")
    if "BEGIN" not in text:
        try:
            decoded = base64.b64decode(text, validate=False).decode("utf-8")
        except (binascii.Error, UnicodeDecodeError) as error:
            raise ValueError("ASC_KEY_P8 is neither a PEM key nor base64 of one") from error
        text = decoded.strip()
    if "-----BEGIN PRIVATE KEY-----" not in text or "-----END PRIVATE KEY-----" not in text:
        raise ValueError("ASC_KEY_P8 must contain the full .p8 file, including the BEGIN/END PRIVATE KEY lines")
    return text + "\n"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _read_der_length(data: bytes, index: int) -> Tuple[int, int]:
    first = data[index]
    index += 1
    if first < 0x80:
        return first, index
    count = first & 0x7F
    return int.from_bytes(data[index:index + count], "big"), index + count


def der_to_raw_signature(der: bytes, size: int = 32) -> bytes:
    """Converts an ASN.1 DER ECDSA signature (openssl output) into the JOSE r||s form."""
    if len(der) < 8 or der[0] != 0x30:
        raise ValueError("signature is not a DER sequence")
    _, index = _read_der_length(der, 1)
    parts = []
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("signature sequence does not contain two integers")
        length, index = _read_der_length(der, index + 1)
        value = der[index:index + length].lstrip(b"\x00")
        index += length
        if len(value) > size:
            raise ValueError("signature integer is too large")
        parts.append(value.rjust(size, b"\x00"))
    return b"".join(parts)


def make_token(key_id: str, issuer_id: str, key_path: str, now: Optional[int] = None) -> str:
    """Builds an ES256 JWT for the App Store Connect API, signing with the openssl CLI."""
    issued_at = int(time.time()) if now is None else now
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": issued_at, "exp": issued_at + TOKEN_LIFETIME, "aud": "appstoreconnect-v1"}
    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode("utf-8")) for part in (header, payload)
    )
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode("ascii"),
        capture_output=True,
        check=True,
    )
    return signing_input + "." + b64url(der_to_raw_signature(result.stdout))


# MARK: - API client

Opener = Callable[..., Any]


class AppStoreConnect:
    def __init__(self, key_id: str, issuer_id: str, key_path: str, opener: Optional[Opener] = None) -> None:
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.key_path = key_path
        self.opener = opener or urllib.request.urlopen
        self._token: Optional[str] = None
        self._token_created = 0.0

    def token(self) -> str:
        if self._token is None or time.time() - self._token_created > TOKEN_LIFETIME / 2:
            self._token = make_token(self.key_id, self.issuer_id, self.key_path)
            self._token_created = time.time()
        return self._token

    def request(self, method: str, path: str, query: Optional[Dict[str, str]] = None) -> Tuple[int, Any]:
        url = path if path.startswith("https://") else API_ROOT + path
        if query:
            url += "?" + urllib.parse.urlencode(query, safe="[],")
        request = urllib.request.Request(
            url,
            method=method,
            headers={"Authorization": f"Bearer {self.token()}", "Accept": "application/json"},
        )
        try:
            with self.opener(request, timeout=60) as response:
                status, body = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, body = error.code, error.read()
            error.close()
        data = None
        if body:
            try:
                data = json.loads(body)
            except ValueError:
                data = {"raw": body.decode("utf-8", "replace")}
        return status, data

    def get_all(self, path: str, query: Dict[str, str]) -> List[Dict[str, Any]]:
        items: List[Dict[str, Any]] = []
        next_url: Optional[str] = path
        next_query: Optional[Dict[str, str]] = query
        while next_url:
            status, data = self.request("GET", next_url, next_query)
            if status != 200:
                raise AscError(status, error_detail(data))
            items.extend(data.get("data", []))
            next_url = (data.get("links") or {}).get("next")
            next_query = None
        return items


def error_detail(data: Any) -> str:
    if isinstance(data, dict):
        errors = data.get("errors") or []
        if errors:
            first = errors[0]
            return f"{first.get('title', '')} {first.get('detail', '')}".strip()
        if "raw" in data:
            return str(data["raw"])[:300]
    return "no details"


def client_from_env() -> AppStoreConnect:
    missing = [name for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH") if not os.environ.get(name)]
    if missing:
        raise SystemExit(f"::error::Missing environment variables: {', '.join(missing)}")
    return AppStoreConnect(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_PATH"])


# MARK: - Certificates in the keychain


def normalize_serial(value: str) -> str:
    cleaned = value.strip().replace(":", "").replace(" ", "").upper().lstrip("0")
    return cleaned or "0"


def serials_from_pem_bundle(text: str) -> List[str]:
    serials = []
    for pem in CERTIFICATE_PATTERN.findall(text):
        result = subprocess.run(
            ["openssl", "x509", "-noout", "-serial"], input=pem, capture_output=True, text=True, check=True
        )
        serials.append(normalize_serial(result.stdout.strip().split("=", 1)[-1]))
    return sorted(set(serials))


def keychain_development_serials() -> List[str]:
    result = subprocess.run(
        ["security", "find-certificate", "-a", "-c", "Apple Development", "-p"], capture_output=True, text=True
    )
    if result.returncode != 0:
        # Exit code 44 means that no matching certificate exists.
        return []
    return serials_from_pem_bundle(result.stdout)


# MARK: - Commands


def command_write_key(out_path: str) -> int:
    raw = os.environ.get("ASC_KEY_P8", "")
    try:
        pem = normalize_private_key(raw)
    except ValueError as error:
        print(f"::error title=Invalid ASC_KEY_P8::{error}")
        return 1
    descriptor = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(pem)
    check = subprocess.run(["openssl", "pkey", "-in", out_path, "-noout"], capture_output=True, text=True)
    if check.returncode != 0:
        print("::error title=Invalid ASC_KEY_P8::openssl cannot read the private key: " + check.stderr.strip())
        return 1
    env_path = os.environ.get("GITHUB_ENV")
    if env_path:
        with open(env_path, "a", encoding="utf-8") as handle:
            handle.write(f"ASC_KEY_PATH={out_path}\n")
    print(f"Wrote App Store Connect key to {out_path}")
    return 0


def command_check(client: AppStoreConnect) -> int:
    try:
        devices = client.get_all(
            "/v1/devices", {"filter[platform]": "IOS", "filter[status]": "ENABLED", "limit": "200"}
        )
    except AscError as error:
        if error.status == 401:
            print("::error title=App Store Connect::The API key was rejected (HTTP 401). "
                  "Check ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8.")
        elif error.status == 403:
            print("::error title=App Store Connect::The API key is not allowed to read devices (HTTP 403). "
                  "Use a Team Key with the Admin role.")
        else:
            print(f"::error title=App Store Connect::Device lookup failed: {error}")
        return 1
    classes: Dict[str, int] = {}
    for device in devices:
        device_class = (device.get("attributes") or {}).get("deviceClass") or "UNKNOWN"
        classes[device_class] = classes.get(device_class, 0) + 1
    summary = ", ".join(f"{count} {name}" for name, count in sorted(classes.items())) or "none"
    print(f"App Store Connect key works. Enabled iOS devices: {len(devices)} ({summary}).")
    if not devices:
        print("::error title=No devices::No enabled iOS device is registered in the Apple Developer portal; "
              "Ad Hoc builds need at least one registered UDID.")
        return 1
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as handle:
            handle.write(f"registered_devices={len(devices)}\n")
    return 0


def read_serials(path: str) -> List[str]:
    with open(path, encoding="utf-8") as handle:
        return sorted({normalize_serial(line) for line in handle if line.strip()})


def command_revoke_new(client: AppStoreConnect, before_path: str, current: List[str]) -> int:
    before = set(read_serials(before_path))
    new_serials = sorted(set(current) - before)
    if not new_serials:
        print("No new Apple Development certificate was created during this run.")
        return 0
    print(f"New Apple Development certificates in the keychain: {len(new_serials)}")
    try:
        certificates = client.get_all(
            "/v1/certificates", {"filter[certificateType]": DEVELOPMENT_CERTIFICATE_TYPES, "limit": "200"}
        )
    except AscError as error:
        print(f"::error title=Certificate revocation::Listing certificates failed: {error}")
        return 1
    by_serial = {
        normalize_serial((cert.get("attributes") or {}).get("serialNumber") or ""): cert for cert in certificates
    }
    failures = 0
    for serial in new_serials:
        certificate = by_serial.get(serial)
        if certificate is None:
            print(f"::warning::Certificate {serial} is in the keychain but not in App Store Connect; nothing to revoke.")
            continue
        name = (certificate.get("attributes") or {}).get("name", "")
        status, data = client.request("DELETE", f"/v1/certificates/{certificate['id']}")
        if status in (200, 204):
            print(f"Revoked {name} (serial {serial}).")
        else:
            failures += 1
            print(f"::error title=Certificate revocation::Could not revoke {serial}: HTTP {status} {error_detail(data)}")
    return 1 if failures else 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    write_key = sub.add_parser("write-key")
    write_key.add_argument("--out", required=True)
    sub.add_parser("check")
    sub.add_parser("keychain-serials")
    revoke = sub.add_parser("revoke-new-dev-certs")
    revoke.add_argument("--before", required=True)
    args = parser.parse_args(argv)

    if args.command == "write-key":
        return command_write_key(args.out)
    if args.command == "check":
        return command_check(client_from_env())
    if args.command == "keychain-serials":
        for serial in keychain_development_serials():
            print(serial)
        return 0
    if args.command == "revoke-new-dev-certs":
        return command_revoke_new(client_from_env(), args.before, keychain_development_serials())
    return 2


if __name__ == "__main__":
    sys.exit(main())
