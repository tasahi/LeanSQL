""" Variable-Length Integer (Varint) Codecs.

Corresponds to `sqlite3PutVarint`, `sqlite3GetVarint`, and `sqlite3GetVarint32`
in `sqlite/src/util.c`.

SQLite variable-length integers store 64-bit unsigned integers using 1 to 9
bytes:
- Bytes 1..8 use the high bit (0x80) as a continuation flag and 7 bits for data.
- The 9th byte stores all 8 bits without a continuation flag.
"""

from std.memory import Pointer
from src.types import *


def put_varint64[origin: Origin[mut=True]](p: Pointer[UInt8, origin], val: UInt64) -> Int:
    """ Encodes a 64-bit integer into 1 to 9 bytes starting at pointer `p`.
    Returns the number of bytes written (1..9).
    """
    var v = val
    # If high 8 bits are set, write full 9 bytes
    if Bool(v & (UInt64(0xFF000000) << 32)):
        p[unsafe_offset=8] = UInt8(v & 0xFF)
        v >>= 8
        for i in range(7, -1, -1):
            p[unsafe_offset=i] = UInt8((v & 0x7F) | 0x80)
            v >>= 7
        return 9

    var temp = List[UInt8]()
    while True:
        temp.append(UInt8((v & 0x7F) | 0x80))
        v >>= 7
        if v == 0:
            break

    temp[0] &= 0x7F
    var n = len(temp)
    for i in range(n):
        p[unsafe_offset=i] = temp[n - 1 - i]
    return n


def put_varint[origin: Origin[mut=True]](p: Pointer[UInt8, origin], v: UInt64) -> Int:
    """ Fast-path varint encoder for small values (1 or 2 bytes).
    Falls back to `put_varint64` for larger values.
    """
    if v <= 0x7F:
        p[unsafe_offset=0] = UInt8(v & 0x7F)
        return 1
    if v <= 0x3FFF:
        p[unsafe_offset=0] = UInt8(((v >> 7) & 0x7F) | 0x80)
        p[unsafe_offset=1] = UInt8(v & 0x7F)
        return 2
    return put_varint64(p, v)


def get_varint[origin: Origin](p: Pointer[UInt8, origin], mut v: UInt64) -> Int:
    """ Decodes a variable-length integer from `p` into `v`.
    Returns the number of bytes consumed (1..9). Uses SQLite's fast XOR
    bit-cancellation technique.
    """
    var i_key: UInt64 = UInt64(p[unsafe_offset=0])
    if i_key < 0x80:
        v = i_key
        return 1

    var offset: Int = 1
    var x: UInt64 = UInt64(p[unsafe_offset=offset])
    i_key = (i_key << 7) ^ x
    if x < 0x80:
        i_key ^= UInt64(0x4000)
        v = i_key
        return 2

    offset += 1
    x = UInt64(p[unsafe_offset=offset])
    i_key = (i_key << 7) ^ x
    if x < 0x80:
        i_key ^= UInt64(0x204000)
        v = i_key
        return 3

    offset += 1
    x = UInt64(p[unsafe_offset=offset])
    i_key = (i_key << 7) ^ UInt64(0x10204000) ^ x
    if x < 0x80:
        v = i_key
        return 4

    offset += 1
    x = UInt64(p[unsafe_offset=offset])
    i_key = (i_key << 7) ^ UInt64(0x4000) ^ x
    if x < 0x80:
        v = i_key
        return 5

    offset += 1
    x = UInt64(p[unsafe_offset=offset])
    i_key = (i_key << 7) ^ UInt64(0x4000) ^ x
    if x < 0x80:
        v = i_key
        return 6

    offset += 1
    x = UInt64(p[unsafe_offset=offset])
    i_key = (i_key << 7) ^ UInt64(0x4000) ^ x
    if x < 0x80:
        v = i_key
        return 7

    offset += 1
    x = UInt64(p[unsafe_offset=offset])
    i_key = (i_key << 7) ^ UInt64(0x4000) ^ x
    if x < 0x80:
        v = i_key
        return 8

    offset += 1
    x = UInt64(p[unsafe_offset=offset])
    i_key = (i_key << 8) ^ UInt64(0x8000) ^ x
    v = i_key
    return 9


def get_varint_value[origin: Origin](p: Pointer[UInt8, origin]) -> Int64:
    """ Reads a varint value directly when the byte length is not needed."""
    var v: UInt64 = 0
    _ = get_varint(p, v)
    return Int64(v)


def get_varint32[origin: Origin](p: Pointer[UInt8, origin], mut v: UInt32) -> Int:
    """ Decodes a 32-bit varint. If value exceeds 32 bits, clamps to 0xFFFFFFFF."""
    var b0 = p[unsafe_offset=0]
    if (b0 & 0x80) == 0:
        v = UInt32(b0)
        return 1

    var b1 = p[unsafe_offset=1]
    if (b1 & 0x80) == 0:
        v = (UInt32(b0 & 0x7F) << 7) | UInt32(b1)
        return 2

    var b2 = p[unsafe_offset=2]
    if (b2 & 0x80) == 0:
        v = (UInt32(b0 & 0x7F) << 14) | (UInt32(b1 & 0x7F) << 7) | UInt32(b2)
        return 3

    var v64: UInt64 = 0
    var n = get_varint(p, v64)
    if v64 > UInt64(0xFFFFFFFF):
        v = UInt32(0xFFFFFFFF)
    else:
        v = UInt32(v64)
    return n


def put_varint32[origin: Origin[mut=True]](p: Pointer[UInt8, origin], v: UInt32) -> Int:
    """ Encodes a 32-bit integer as a varint."""
    return put_varint(p, UInt64(v))


def encode_varint(v: UInt64) -> List[UInt8]:
    """ Convenience helper: encodes integer `v` into a byte list."""
    var res = List[UInt8]()
    if v <= 0x7F:
        res.append(UInt8(v & 0x7F))
        return res^
    if v <= 0x3FFF:
        res.append(UInt8(((v >> 7) & 0x7F) | 0x80))
        res.append(UInt8(v & 0x7F))
        return res^
    var temp = List[UInt8]()
    var cur = v
    while True:
        temp.append(UInt8((cur & 0x7F) | 0x80))
        cur >>= 7
        if cur == 0:
            break
    temp[0] &= 0x7F
    for i in range(len(temp) - 1, -1, -1):
        res.append(temp[i])
    return res^


def decode_varint(bytes: List[UInt8]) -> Tuple[UInt64, Int]:
    """ Convenience helper: decodes a varint from a List[UInt8]."""
    var v: UInt64 = 0
    var n = get_varint(bytes.unsafe_ptr(), v)
    return Tuple(v, n)
