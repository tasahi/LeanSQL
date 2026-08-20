"""SQLite Serial Type Encoding and Decoding.

Corresponds to `sqlite3VdbeSerialTypeLen`, `sqlite3VdbeSerialGet`, and `sqlite3VdbeSerialPut`
in `sqlite/src/vdbeaux.c`.

SQLite encodes datatypes and content lengths into integer serial types:
- 0: NULL (0 bytes)
- 1: 8-bit signed int (1 byte)
- 2: 16-bit big-endian signed int (2 bytes)
- 3: 24-bit big-endian signed int (3 bytes)
- 4: 32-bit big-endian signed int (4 bytes)
- 5: 48-bit big-endian signed int (6 bytes)
- 6: 64-bit big-endian signed int (8 bytes)
- 7: 64-bit IEEE 754 float (8 bytes)
- 8: Constant integer 0 (0 bytes)
- 9: Constant integer 1 (0 bytes)
- N >= 12 (even): BLOB of length (N-12)/2
- N >= 13 (odd): TEXT of length (N-13)/2
"""

from std.memory import Pointer, bitcast
from src.types import *
from src.row import Value


def serial_type_len(serial_type: UInt32) -> Int:
    """Returns the payload byte length for a given SQLite serial type."""
    if serial_type >= 12:
        return Int((serial_type - 12) // 2)
    if serial_type == 0 or serial_type == 8 or serial_type == 9 or serial_type == 10 or serial_type == 11:
        return 0
    if serial_type == 1:
        return 1
    if serial_type == 2:
        return 2
    if serial_type == 3:
        return 3
    if serial_type == 4:
        return 4
    if serial_type == 5:
        return 6
    if serial_type == 6 or serial_type == 7:
        return 8
    return 0


def get_serial_type(val: Value) -> UInt32:
    """Determines the most compact SQLite serial type for a Value."""
    if val.is_null():
        return 0
    if val.type_tag == SQLITE_INTEGER:
        var v = val.int_val
        if v == 0:
            return 8
        if v == 1:
            return 9
        if v >= -128 and v <= 127:
            return 1
        if v >= -32768 and v <= 32767:
            return 2
        if v >= -8388608 and v <= 8388607:
            return 3
        if v >= -2147483648 and v <= 2147483647:
            return 4
        if v >= -140737488355328 and v <= 140737488355327:
            return 5
        return 6
    if val.type_tag == SQLITE_FLOAT:
        return 7
    if val.type_tag == SQLITE_TEXT:
        var n_bytes = UInt32(len(val.text_val.as_bytes()))
        return 13 + 2 * n_bytes
    return 0


def encode_value[origin: Origin[mut=True]](val: Value, p: Pointer[UInt8, origin]) -> Int:
    """Encodes a Value into binary format at pointer `p`.
    
    Returns the number of bytes written.
    """
    if val.is_null():
        return 0
    if val.type_tag == SQLITE_INTEGER:
        var v = val.int_val
        if v == 0 or v == 1:
            return 0
        if v >= -128 and v <= 127:
            p[unsafe_offset=0] = UInt8(Int(v) & 0xFF)
            return 1
        if v >= -32768 and v <= 32767:
            var uv = UInt16(Int(v) & 0xFFFF)
            p[unsafe_offset=0] = UInt8((uv >> 8) & 0xFF)
            p[unsafe_offset=1] = UInt8(uv & 0xFF)
            return 2
        if v >= -8388608 and v <= 8388607:
            var uv = UInt32(Int(v) & 0xFFFFFF)
            p[unsafe_offset=0] = UInt8((uv >> 16) & 0xFF)
            p[unsafe_offset=1] = UInt8((uv >> 8) & 0xFF)
            p[unsafe_offset=2] = UInt8(uv & 0xFF)
            return 3
        if v >= -2147483648 and v <= 2147483647:
            var uv = UInt32(Int(v) & 0xFFFFFFFF)
            p[unsafe_offset=0] = UInt8((uv >> 24) & 0xFF)
            p[unsafe_offset=1] = UInt8((uv >> 16) & 0xFF)
            p[unsafe_offset=2] = UInt8((uv >> 8) & 0xFF)
            p[unsafe_offset=3] = UInt8(uv & 0xFF)
            return 4
        if v >= -140737488355328 and v <= 140737488355327:
            var uv = UInt64(v) & UInt64(0xFFFFFFFFFFFF)
            p[unsafe_offset=0] = UInt8((uv >> 40) & 0xFF)
            p[unsafe_offset=1] = UInt8((uv >> 32) & 0xFF)
            p[unsafe_offset=2] = UInt8((uv >> 24) & 0xFF)
            p[unsafe_offset=3] = UInt8((uv >> 16) & 0xFF)
            p[unsafe_offset=4] = UInt8((uv >> 8) & 0xFF)
            p[unsafe_offset=5] = UInt8(uv & 0xFF)
            return 6
        var uv = UInt64(v)
        p[unsafe_offset=0] = UInt8((uv >> 56) & 0xFF)
        p[unsafe_offset=1] = UInt8((uv >> 48) & 0xFF)
        p[unsafe_offset=2] = UInt8((uv >> 40) & 0xFF)
        p[unsafe_offset=3] = UInt8((uv >> 32) & 0xFF)
        p[unsafe_offset=4] = UInt8((uv >> 24) & 0xFF)
        p[unsafe_offset=5] = UInt8((uv >> 16) & 0xFF)
        p[unsafe_offset=6] = UInt8((uv >> 8) & 0xFF)
        p[unsafe_offset=7] = UInt8(uv & 0xFF)
        return 8

    if val.type_tag == SQLITE_FLOAT:
        var f = val.float_val
        var uv = bitcast[DType.uint64](f)
        p[unsafe_offset=0] = UInt8((uv >> 56) & 0xFF)
        p[unsafe_offset=1] = UInt8((uv >> 48) & 0xFF)
        p[unsafe_offset=2] = UInt8((uv >> 40) & 0xFF)
        p[unsafe_offset=3] = UInt8((uv >> 32) & 0xFF)
        p[unsafe_offset=4] = UInt8((uv >> 24) & 0xFF)
        p[unsafe_offset=5] = UInt8((uv >> 16) & 0xFF)
        p[unsafe_offset=6] = UInt8((uv >> 8) & 0xFF)
        p[unsafe_offset=7] = UInt8(uv & 0xFF)
        return 8

    if val.type_tag == SQLITE_TEXT:
        var bytes = val.text_val.as_bytes()
        var n = len(bytes)
        for i in range(n):
            p[unsafe_offset=i] = bytes[i]
        return n

    return 0


def decode_value[origin: Origin](serial_type: UInt32, p: Pointer[UInt8, origin]) -> Value:
    """Deserializes a raw byte buffer at `p` according to `serial_type`."""
    if serial_type == 0 or serial_type == 10 or serial_type == 11:
        return Value.of_null()
    if serial_type == 8:
        return Value.of_int(0)
    if serial_type == 9:
        return Value.of_int(1)
    if serial_type == 1:
        var b = Int(p[unsafe_offset=0])
        if (b & 0x80) != 0:
            b -= 0x100
        return Value.of_int(Int64(b))
    if serial_type == 2:
        var uv = (Int(p[unsafe_offset=0]) << 8) | Int(p[unsafe_offset=1])
        if (uv & 0x8000) != 0:
            uv -= 0x10000
        return Value.of_int(Int64(uv))
    if serial_type == 3:
        var uv = (Int(p[unsafe_offset=0]) << 16) | (Int(p[unsafe_offset=1]) << 8) | Int(p[unsafe_offset=2])
        if (uv & 0x800000) != 0:
            uv -= 0x1000000
        return Value.of_int(Int64(uv))
    if serial_type == 4:
        var uv = (Int(p[unsafe_offset=0]) << 24) | (Int(p[unsafe_offset=1]) << 16) | (Int(p[unsafe_offset=2]) << 8) | Int(p[unsafe_offset=3])
        if (uv & 0x80000000) != 0:
            uv -= 0x100000000
        return Value.of_int(Int64(uv))
    if serial_type == 5:
        var uv = (UInt64(p[unsafe_offset=0]) << 40) | (UInt64(p[unsafe_offset=1]) << 32) | (UInt64(p[unsafe_offset=2]) << 24) | (UInt64(p[unsafe_offset=3]) << 16) | (UInt64(p[unsafe_offset=4]) << 8) | UInt64(p[unsafe_offset=5])
        if (uv & (UInt64(1) << 47)) != 0:
            uv |= UInt64(0xFFFF000000000000)
        return Value.of_int(Int64(uv))
    if serial_type == 6:
        var uv = (UInt64(p[unsafe_offset=0]) << 56) | (UInt64(p[unsafe_offset=1]) << 48) | (UInt64(p[unsafe_offset=2]) << 40) | (UInt64(p[unsafe_offset=3]) << 32) | (UInt64(p[unsafe_offset=4]) << 24) | (UInt64(p[unsafe_offset=5]) << 16) | (UInt64(p[unsafe_offset=6]) << 8) | UInt64(p[unsafe_offset=7])
        return Value.of_int(Int64(uv))
    if serial_type == 7:
        var uv = (UInt64(p[unsafe_offset=0]) << 56) | (UInt64(p[unsafe_offset=1]) << 48) | (UInt64(p[unsafe_offset=2]) << 40) | (UInt64(p[unsafe_offset=3]) << 32) | (UInt64(p[unsafe_offset=4]) << 24) | (UInt64(p[unsafe_offset=5]) << 16) | (UInt64(p[unsafe_offset=6]) << 8) | UInt64(p[unsafe_offset=7])
        var f_val = bitcast[DType.float64](uv)
        return Value.of_float(f_val)
    if serial_type >= 13 and (serial_type % 2 == 1):
        # UTF-8 Text string
        var str_len = Int((serial_type - 13) // 2)
        var s = String()
        var offset = 0
        while offset < str_len:
            var b0 = UInt32(p[unsafe_offset=offset])
            if b0 < 0x80:
                s += chr(Int(b0))
                offset += 1
            elif (b0 & 0xE0) == 0xC0:
                var cp = ((b0 & 0x1F) << 6) | (UInt32(p[unsafe_offset=offset + 1]) & 0x3F)
                s += chr(Int(cp))
                offset += 2
            elif (b0 & 0xF0) == 0xE0:
                var cp = ((b0 & 0x0F) << 12) | ((UInt32(p[unsafe_offset=offset + 1]) & 0x3F) << 6) | (UInt32(p[unsafe_offset=offset + 2]) & 0x3F)
                s += chr(Int(cp))
                offset += 3
            elif (b0 & 0xF8) == 0xF0:
                var cp = ((b0 & 0x07) << 18) | ((UInt32(p[unsafe_offset=offset + 1]) & 0x3F) << 12) | ((UInt32(p[unsafe_offset=offset + 2]) & 0x3F) << 6) | (UInt32(p[unsafe_offset=offset + 3]) & 0x3F)
                s += chr(Int(cp))
                offset += 4
            else:
                offset += 1
        return Value.of_text(s)

    return Value.of_null()
