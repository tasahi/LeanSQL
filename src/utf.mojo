"""UTF-8 String Codecs and Collation Utilities.

Corresponds to `sqlite/src/utf.c`.

Provides UTF-8 character encoding/decoding and SQLite's standard
`NOCASE` case-insensitive ASCII comparison.
"""

from std.memory import UnsafePointer, alloc
from src.types import *


def write_utf8(p: UnsafePointer[UInt8, MutAnyOrigin], c: UInt32) -> Int:
    """ Encodes a Unicode codepoint `c` into 1 to 4 UTF-8 bytes at `p`.
    Returns the number of bytes written.
    """
    if c < 0x80:
        p[0] = UInt8(c & 0xFF)
        return 1
    elif c < 0x800:
        p[0] = UInt8(0xC0 | ((c >> 6) & 0x1F))
        p[1] = UInt8(0x80 | (c & 0x3F))
        return 2
    elif c < 0x10000:
        p[0] = UInt8(0xE0 | ((c >> 12) & 0x0F))
        p[1] = UInt8(0x80 | ((c >> 6) & 0x3F))
        p[2] = UInt8(0x80 | (c & 0x3F))
        return 3
    else:
        p[0] = UInt8(0xF0 | ((c >> 18) & 0x07))
        p[1] = UInt8(0x80 | ((c >> 12) & 0x3F))
        p[2] = UInt8(0x80 | ((c >> 6) & 0x3F))
        p[3] = UInt8(0x80 | (c & 0x3F))
        return 4


def read_utf8(p: UnsafePointer[UInt8, ImmutAnyOrigin], mut cp: UInt32) -> Int:
    """ Decodes a single Unicode codepoint from UTF-8 byte stream `p` into `cp`.
    Returns the number of bytes consumed (1..4).
    """
    var b0 = UInt32(p[0])
    if b0 < 0x80:
        cp = b0
        return 1
    elif (b0 & 0xE0) == 0xC0:
        var b1 = UInt32(p[1])
        cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
        return 2
    elif (b0 & 0xF0) == 0xE0:
        var b1 = UInt32(p[1])
        var b2 = UInt32(p[2])
        cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
        return 3
    elif (b0 & 0xF8) == 0xF0:
        var b1 = UInt32(p[1])
        var b2 = UInt32(p[2])
        var b3 = UInt32(p[3])
        cp = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
        return 4
    else:
        cp = 0xFFFD # Unicode replacement character for invalid bytes
        return 1


def utf8_char_length(p: UnsafePointer[UInt8, ImmutAnyOrigin], num_bytes: Int) -> Int:
    """ Returns the number of logical UTF-8 characters across `num_bytes`."""
    var count: Int = 0
    var offset: Int = 0
    while offset < num_bytes:
        var b = p[offset]
        if (b & 0xC0) != 0x80: # Not a continuation byte
            count += 1
        offset += 1
    return count


def to_lower_ascii(c: UInt8) -> UInt8:
    """ Converts uppercase ASCII character [A-Z] to lowercase [a-z]."""
    if c >= UInt8(ord('A')) and c <= UInt8(ord('Z')):
        return c + 32
    return c


def nocase_compare(s1: String, s2: String) -> Int:
    """ SQLite `NOCASE` collation: case-insensitive comparison for ASCII characters.
    Returns <0 if s1 < s2, 0 if s1 == s2, and >0 if s1 > s2.
    """
    var b1 = s1.as_bytes()
    var b2 = s2.as_bytes()
    var len1 = len(b1)
    var len2 = len(b2)
    var min_len = len1 if len1 < len2 else len2
    for i in range(min_len):
        var c1 = to_lower_ascii(b1[i])
        var c2 = to_lower_ascii(b2[i])
        if c1 != c2:
            return Int(c1) - Int(c2)
    return len1 - len2
