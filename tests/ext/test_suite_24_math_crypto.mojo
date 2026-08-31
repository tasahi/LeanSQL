from tests.harness import TestHarness
from src.engine.connection import connect
from src.ext.crypto import sha256_hash, md5_hash, hex_encode_str, hex_decode


def run_math_crypto_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 24: Extended Math & Crypto Functions      ===")
    print("=======================================================")

    # 1. Direct Crypto Functions
    var text = "LeanSQL Pure Mojo Engine"
    var h_md5 = md5_hash(text)
    h.assert_equal_int("mc-1.1a", h_md5.byte_length(), 32, "MD5 produces 32-character hex digest")

    var h_sha = sha256_hash(text)
    h.assert_equal_int("mc-1.1b", h_sha.byte_length(), 64, "SHA-256 produces 64-character hex digest")

    var hex_str = hex_encode_str("Hello")
    h.assert_equal("mc-1.2a", hex_str, "48656c6c6f", "hex_encode_str encodes 'Hello'")
    var unhex_str = hex_decode("48656c6c6f")
    h.assert_equal("mc-1.2b", unhex_str, "Hello", "hex_decode decodes '48656c6c6f' to 'Hello'")

    # 2. SQL Math Extension Functions
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("SELECT sqrt(16.0), pow(2.0, 3.0), ceil(4.2), floor(4.8), trunc(9.9)")
    var row_math = cur.fetchone()
    if row_math:
        var r = row_math.value()
        h.assert_equal_float("mc-1.3a", r.get_float(0), 4.0, 0.001, "sqrt(16.0) = 4.0")
        h.assert_equal_float("mc-1.3b", r.get_float(1), 8.0, 0.001, "pow(2.0, 3.0) = 8.0")
        h.assert_equal_float("mc-1.3c", r.get_float(2), 5.0, 0.001, "ceil(4.2) = 5.0")
        h.assert_equal_float("mc-1.3d", r.get_float(3), 4.0, 0.001, "floor(4.8) = 4.0")
        h.assert_equal_float("mc-1.3e", r.get_float(4), 9.0, 0.001, "trunc(9.9) = 9.0")

    # Trigonometry & Constants
    cur.execute("SELECT pi(), degrees(pi()), radians(180.0), sign(-42), sign(42)")
    var row_trig = cur.fetchone()
    if row_trig:
        var r = row_trig.value()
        h.assert_equal_float("mc-1.4a", r.get_float(0), 3.14159, 0.001, "pi() returns π")
        h.assert_equal_float("mc-1.4b", r.get_float(1), 180.0, 0.001, "degrees(pi()) = 180.0")
        h.assert_equal_float("mc-1.4c", r.get_float(2), 3.14159, 0.001, "radians(180.0) = π")
        h.assert_equal_int("mc-1.4d", Int(r.get_int(3)), -1, "sign(-42) = -1")
        h.assert_equal_int("mc-1.4e", Int(r.get_int(4)), 1, "sign(42) = 1")

    # 3. SQL Crypto Functions
    cur.execute("SELECT md5('admin'), sha256('admin'), hex('Mojo'), unhex('4d6f6a6f')")
    var row_crypto = cur.fetchone()
    if row_crypto:
        var r = row_crypto.value()
        h.assert_equal_int("mc-1.5a", r.get_string(0).byte_length(), 32, "md5('admin') is 32 chars")
        h.assert_equal_int("mc-1.5b", r.get_string(1).byte_length(), 64, "sha256('admin') is 64 chars")
        h.assert_equal("mc-1.5c", r.get_string(2).lower(), "4d6f6a6f", "hex('Mojo') is 4d6f6a6f")
        h.assert_equal("mc-1.5d", r.get_string(3), "Mojo", "unhex('4d6f6a6f') is Mojo")


def main() raises:
    var h = TestHarness("Suite 24: Extended Math & Crypto")
    run_math_crypto_tests(h)
    h.summary()
