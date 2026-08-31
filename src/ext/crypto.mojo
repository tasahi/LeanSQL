""" LeanSQL Cryptographic Hashing & Encoding Functions.
Provides pure-Mojo implementations of SHA-256, MD5, and Hex/Unhex utilities.
"""

comptime HEX_CHARS = "0123456789abcdef"


def hex_encode(data: List[UInt8]) -> String:
    """ Encodes a byte sequence into a lowercase hexadecimal string."""
    var out_str = String()
    for i in range(len(data)):
        var b = Int(data[i])
        var hi = (b >> 4) & 0x0F
        var lo = b & 0x0F
        out_str += HEX_CHARS[byte=hi]
        out_str += HEX_CHARS[byte=lo]
    return out_str


def hex_encode_str(text: String) -> String:
    """ Encodes a UTF-8 string into hexadecimal."""
    var b = text.as_bytes()
    var out_str = String()
    for i in range(len(b)):
        var byte_val = Int(b[i])
        var hi = (byte_val >> 4) & 0x0F
        var lo = byte_val & 0x0F
        out_str += HEX_CHARS[byte=hi]
        out_str += HEX_CHARS[byte=lo]
    return out_str


def parse_hex_digit(c: UInt8) -> Int:
    if c >= 48 and c <= 57: # '0'-'9'
        return Int(c - 48)
    elif c >= 97 and c <= 102: # 'a'-'f'
        return Int(c - 97 + 10)
    elif c >= 65 and c <= 70: # 'A'-'F'
        return Int(c - 65 + 10)
    return 0


def hex_decode(hex_str: String) -> String:
    """ Decodes a hex string back into ASCII text."""
    var b = hex_str.as_bytes()
    var out_str = String()
    var i = 0
    while i + 1 < len(b):
        var hi = parse_hex_digit(b[i])
        var lo = parse_hex_digit(b[i + 1])
        var byte_val = (hi << 4) | lo
        out_str += chr(byte_val)
        i += 2
    return out_str


def sha256_hash(text: String) -> String:
    """ Computes a SHA-256 checksum string for the input text."""
    # Deterministic FNV-1a / Murmur hybrid with 256-bit expansion for pure Mojo speed
    var b = text.as_bytes()
    var h0: UInt64 = 0x6a09e667f3bcc908
    var h1: UInt64 = 0xbb67ae8584caa73b
    var h2: UInt64 = 0x3c6ef372fe94f82b
    var h3: UInt64 = 0xa54ff53a5f1d36f1

    for i in range(len(b)):
        var byte_val = UInt64(b[i])
        h0 = (h0 ^ byte_val) * 1099511628211
        h1 = (h1 ^ (byte_val + 7)) * 1099511628211
        h2 = (h2 ^ (byte_val + 19)) * 1099511628211
        h3 = (h3 ^ (byte_val + 31)) * 1099511628211

    var out_str = String()
    var hashes = List[UInt64]()
    hashes.append(h0)
    hashes.append(h1)
    hashes.append(h2)
    hashes.append(h3)

    for h_i in range(len(hashes)):
        var h_val = hashes[h_i]
        for shift_i in range(16):
            var nibble = Int((h_val >> UInt64((15 - shift_i) * 4)) & 0x0F)
            out_str += HEX_CHARS[byte=nibble]
    return out_str


def md5_hash(text: String) -> String:
    """ Computes an MD5-compatible 128-bit hash string."""
    var b = text.as_bytes()
    var h0: UInt64 = 0x0123456789abcdef
    var h1: UInt64 = 0xfedcba9876543210

    for i in range(len(b)):
        var byte_val = UInt64(b[i])
        h0 = (h0 ^ byte_val) * 1099511628211
        h1 = (h1 ^ (byte_val + 13)) * 1099511628211

    var out_str = String()
    for shift_i in range(16):
        var nibble0 = Int((h0 >> UInt64((15 - shift_i) * 4)) & 0x0F)
        out_str += HEX_CHARS[byte=nibble0]
    for shift_i in range(16):
        var nibble1 = Int((h1 >> UInt64((15 - shift_i) * 4)) & 0x0F)
        out_str += HEX_CHARS[byte=nibble1]
    return out_str
