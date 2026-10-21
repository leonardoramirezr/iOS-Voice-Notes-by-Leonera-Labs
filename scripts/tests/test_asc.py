import base64
import io
import json
import os
import subprocess
import tempfile
import time
import unittest
import urllib.error

import helpers
import asc


def run(*command, **kwargs):
    return subprocess.run(command, check=True, capture_output=True, **kwargs)


def raw_to_der(raw: bytes) -> bytes:
    """Encodes a JOSE r||s signature back to DER so openssl can verify it."""

    def integer(value: bytes) -> bytes:
        value = value.lstrip(b"\x00") or b"\x00"
        if value[0] & 0x80:
            value = b"\x00" + value
        return b"\x02" + bytes([len(value)]) + value

    body = integer(raw[:32]) + integer(raw[32:])
    return b"\x30" + bytes([len(body)]) + body


class KeyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.key_path = os.path.join(cls.directory.name, "key.p8")
        cls.public_path = os.path.join(cls.directory.name, "public.pem")
        ec_key = run("openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout").stdout
        cls.pem = run("openssl", "pkcs8", "-topk8", "-nocrypt", input=ec_key).stdout.decode()
        with open(cls.key_path, "w") as handle:
            handle.write(cls.pem)
        run("openssl", "pkey", "-in", cls.key_path, "-pubout", "-out", cls.public_path)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_normalize_accepts_pem(self):
        self.assertEqual(asc.normalize_private_key(self.pem), self.pem.strip() + "\n")

    def test_normalize_accepts_literal_backslash_n(self):
        escaped = self.pem.strip().replace("\n", "\\n")
        self.assertEqual(asc.normalize_private_key(escaped), self.pem.strip() + "\n")

    def test_normalize_accepts_base64(self):
        encoded = base64.b64encode(self.pem.encode()).decode()
        self.assertEqual(asc.normalize_private_key(encoded), self.pem.strip() + "\n")

    def test_normalize_rejects_garbage(self):
        with self.assertRaises(ValueError):
            asc.normalize_private_key("not a key")

    def test_token_signature_verifies_with_openssl(self):
        token = asc.make_token("KEY1234567", "issuer-uuid", self.key_path, now=1_700_000_000)
        header_b64, payload_b64, signature_b64 = token.split(".")
        padding = "=" * (-len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64 + padding))
        header = json.loads(base64.urlsafe_b64decode(header_b64 + "=" * (-len(header_b64) % 4)))
        self.assertEqual(header, {"alg": "ES256", "kid": "KEY1234567", "typ": "JWT"})
        self.assertEqual(payload["aud"], "appstoreconnect-v1")
        self.assertEqual(payload["exp"] - payload["iat"], 1200)
        raw = base64.urlsafe_b64decode(signature_b64 + "=" * (-len(signature_b64) % 4))
        self.assertEqual(len(raw), 64)
        signature_path = os.path.join(self.directory.name, "sig.der")
        with open(signature_path, "wb") as handle:
            handle.write(raw_to_der(raw))
        verify = subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", self.public_path, "-signature", signature_path],
            input=f"{header_b64}.{payload_b64}".encode(), capture_output=True,
        )
        self.assertEqual(verify.returncode, 0, verify.stdout + verify.stderr)


class DerTests(unittest.TestCase):
    def test_pads_short_and_strips_sign_bytes(self):
        r = b"\x00" + b"\x80" + b"\x11" * 31  # 33 bytes with a leading sign byte
        s = b"\x22" * 30  # short integer
        der = b"\x30" + bytes([4 + len(r) + len(s)]) + b"\x02" + bytes([len(r)]) + r + b"\x02" + bytes([len(s)]) + s
        raw = asc.der_to_raw_signature(der)
        self.assertEqual(raw[:32], b"\x80" + b"\x11" * 31)
        self.assertEqual(raw[32:], b"\x00\x00" + b"\x22" * 30)

    def test_rejects_non_sequence(self):
        with self.assertRaises(ValueError):
            asc.der_to_raw_signature(b"\x02\x01\x01\x02\x01\x01\x00\x00")


class SerialTests(unittest.TestCase):
    def test_normalize_serial(self):
        self.assertEqual(asc.normalize_serial("00ab:CD"), "ABCD")
        self.assertEqual(asc.normalize_serial("0007A1"), "7A1")
        self.assertEqual(asc.normalize_serial("000"), "0")

    def test_serials_from_pem_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            pems = []
            expected = []
            for index in range(2):
                key = os.path.join(directory, f"k{index}.pem")
                cert = os.path.join(directory, f"c{index}.pem")
                run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                    "-days", "1", "-subj", f"/CN=Apple Development: Test {index}")
                with open(cert) as handle:
                    pems.append(handle.read())
                serial = run("openssl", "x509", "-in", cert, "-noout", "-serial", text=True).stdout
                expected.append(asc.normalize_serial(serial.split("=", 1)[1]))
            self.assertEqual(asc.serials_from_pem_bundle("noise\n" + "\n".join(pems)), sorted(expected))


class FakeResponse:
    def __init__(self, status, body):
        self.status = status
        self._body = json.dumps(body).encode() if body is not None else b""

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeOpener:
    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def __call__(self, request, timeout=None):
        key = (request.get_method(), request.full_url)
        self.calls.append(key)
        status, body = self.routes[key]
        if status >= 400:
            raise urllib.error.HTTPError(request.full_url, status, "error", {}, io.BytesIO(json.dumps(body).encode()))
        return FakeResponse(status, body)


class StaticTokenClient(asc.AppStoreConnect):
    def token(self):
        return "token"


DEVICES_URL = "https://api.appstoreconnect.apple.com/v1/devices?filter[platform]=IOS&filter[status]=ENABLED&limit=200"
CERTS_URL = "https://api.appstoreconnect.apple.com/v1/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200"


class ApiTests(unittest.TestCase):
    def test_check_paginates_and_counts_devices(self):
        opener = FakeOpener({
            ("GET", DEVICES_URL): (200, {"data": [{"attributes": {"deviceClass": "IPHONE"}}],
                                         "links": {"next": "https://api.appstoreconnect.apple.com/v1/devices?cursor=2"}}),
            ("GET", "https://api.appstoreconnect.apple.com/v1/devices?cursor=2"): (
                200, {"data": [{"attributes": {"deviceClass": "IPAD"}}], "links": {}}),
        })
        client = StaticTokenClient("k", "i", "p", opener=opener)
        self.assertEqual(asc.command_check(client), 0)
        self.assertEqual(len(opener.calls), 2)

    def test_check_fails_without_devices(self):
        opener = FakeOpener({("GET", DEVICES_URL): (200, {"data": [], "links": {}})})
        self.assertEqual(asc.command_check(StaticTokenClient("k", "i", "p", opener=opener)), 1)

    def test_check_reports_rejected_key(self):
        opener = FakeOpener({("GET", DEVICES_URL): (401, {"errors": [{"title": "Unauthorized", "detail": "bad"}]})})
        self.assertEqual(asc.command_check(StaticTokenClient("k", "i", "p", opener=opener)), 1)

    def test_revoke_only_new_certificates(self):
        opener = FakeOpener({
            ("GET", CERTS_URL): (200, {"data": [
                {"id": "OLD", "attributes": {"serialNumber": "0AAA", "name": "Old"}},
                {"id": "NEW", "attributes": {"serialNumber": "BBB", "name": "Created via API"}},
            ], "links": {}}),
            ("DELETE", "https://api.appstoreconnect.apple.com/v1/certificates/NEW"): (204, None),
        })
        client = StaticTokenClient("k", "i", "p", opener=opener)
        with tempfile.NamedTemporaryFile("w", delete=False) as handle:
            handle.write("AAA\n")
            before = handle.name
        try:
            self.assertEqual(asc.command_revoke_new(client, before, ["AAA", "BBB"]), 0)
        finally:
            os.remove(before)
        self.assertIn(("DELETE", "https://api.appstoreconnect.apple.com/v1/certificates/NEW"), opener.calls)
        self.assertNotIn(("DELETE", "https://api.appstoreconnect.apple.com/v1/certificates/OLD"), opener.calls)

    def test_revoke_is_a_no_op_without_new_certificates(self):
        opener = FakeOpener({})
        client = StaticTokenClient("k", "i", "p", opener=opener)
        with tempfile.NamedTemporaryFile("w", delete=False) as handle:
            handle.write("AAA\n")
            before = handle.name
        try:
            self.assertEqual(asc.command_revoke_new(client, before, ["AAA"]), 0)
        finally:
            os.remove(before)
        self.assertEqual(opener.calls, [])

    def test_token_is_cached(self):
        client = asc.AppStoreConnect("k", "i", "p")
        client._token = "cached"
        client._token_created = time.time()
        self.assertEqual(client.token(), "cached")



def setUpModule():
    helpers.silence_stdout()


def tearDownModule():
    helpers.restore_stdout()


if __name__ == "__main__":
    unittest.main()
