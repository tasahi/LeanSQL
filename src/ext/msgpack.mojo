""" Pure Mojo SQLite-compatible MessagePack Binary Serialization and Extraction Engine.

Implements standard MessagePack binary formats:
- Positive FixInt: 0x00 - 0x7F
- FixMap: 0x80 - 0x8F
- FixArray: 0x90 - 0x9F
- FixStr: 0xA0 - 0xBF
- Nil: 0xC0
- False: 0xC2, True: 0xC3
- Float64: 0xCB
- Int64: 0xD3
- Str32: 0xDB
- Array32: 0xDD
- Map32: 0xDF

Provides SQL scalar functions:
- msgpack_pack(arg1, arg2, ...) -> Hex-encoded MessagePack BLOB string (as an array)
- msgpack_map(k1, v1, k2, v2, ...) -> Hex-encoded MessagePack BLOB string (as a map)
- msgpack_extract(msgpack_hex, key_or_index) -> Value
"""

from src.engine.row import Value
from src.core.types import SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_NULL
from src.ext.crypto import hex_encode, parse_hex_digit
from std.memory import bitcast


def _mp_hex_to_bytes(hex_str: String) -> List[UInt8]:
    var bytes = List[UInt8]()
    var b = hex_str.as_bytes()
    var i = 0
    while i + 1 < len(b):
        var hi = parse_hex_digit(b[i])
        var lo = parse_hex_digit(b[i + 1])
        bytes.append(UInt8((hi << 4) | lo))
        i += 2
    return bytes^


def _mp_encode_u32(val: UInt32, mut buf: List[UInt8]):
    buf.append(UInt8((val >> 24) & 0xFF))
    buf.append(UInt8((val >> 16) & 0xFF))
    buf.append(UInt8((val >> 8) & 0xFF))
    buf.append(UInt8(val & 0xFF))


def _mp_decode_u32(bytes: List[UInt8], offset: Int) -> UInt32:
    if offset + 4 > len(bytes):
        return 0
    var b0 = UInt32(bytes[offset])
    var b1 = UInt32(bytes[offset + 1])
    var b2 = UInt32(bytes[offset + 2])
    var b3 = UInt32(bytes[offset + 3])
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3


def _mp_encode_i64(val: Int64, mut buf: List[UInt8]):
    var uv = UInt64(val)
    for i in range(8):
        var shift = (7 - i) * 8
        buf.append(UInt8((uv >> UInt64(shift)) & 0xFF))


def _mp_decode_i64(bytes: List[UInt8], offset: Int) -> Int64:
    if offset + 8 > len(bytes):
        return 0
    var uv: UInt64 = 0
    for i in range(8):
        uv = (uv << 8) | UInt64(bytes[offset + i])
    return Int64(uv)


def _mp_encode_f64(val: Float64, mut buf: List[UInt8]):
    var uv = bitcast[DType.uint64](val)
    for i in range(8):
        var shift = (7 - i) * 8
        buf.append(UInt8((uv >> UInt64(shift)) & 0xFF))


def _mp_decode_f64(bytes: List[UInt8], offset: Int) -> Float64:
    if offset + 8 > len(bytes):
        return 0.0
    var uv: UInt64 = 0
    for i in range(8):
        uv = (uv << 8) | UInt64(bytes[offset + i])
    return bitcast[DType.float64](uv)


def _encode_value_msgpack(val: Value, mut buf: List[UInt8]):
    if val.is_null():
        buf.append(0xC0) # nil
    elif val.type_tag == SQLITE_INTEGER:
        var v = val.int_val
        if v >= 0 and v <= 127:
            buf.append(UInt8(v & 0x7F))
        else:
            buf.append(0xD3) # int 64
            _mp_encode_i64(v, buf)
    elif val.type_tag == SQLITE_FLOAT:
        buf.append(0xCB) # float 64
        _mp_encode_f64(val.float_val, buf)
    elif val.type_tag == SQLITE_TEXT:
        var b = val.text_val.as_bytes()
        var n = len(b)
        if n <= 31:
            buf.append(UInt8(0xA0 | (n & 0x1F)))
        else:
            buf.append(0xDB) # str 32
            _mp_encode_u32(UInt32(n), buf)
        for i in range(n):
            buf.append(b[i])


def decode_msgpack_value(bytes: List[UInt8], mut offset: Int) -> Value:
    if offset >= len(bytes):
        return Value.of_null()

    var tag = bytes[offset]
    offset += 1

    # 1. Positive FixInt: 0x00 - 0x7F
    if tag <= 0x7F:
        return Value.of_int(Int64(tag))

    # 2. Nil: 0xC0
    if tag == 0xC0:
        return Value.of_null()

    # 3. False: 0xC2, True: 0xC3
    if tag == 0xC2:
        return Value.of_int(0)
    if tag == 0xC3:
        return Value.of_int(1)

    # 4. Float64: 0xCB
    if tag == 0xCB:
        var f = _mp_decode_f64(bytes, offset)
        offset += 8
        return Value.of_float(f)

    # 5. Int64: 0xD3
    if tag == 0xD3:
        var i = _mp_decode_i64(bytes, offset)
        offset += 8
        return Value.of_int(i)

    # 6. FixStr: 0xA0 - 0xBF
    if tag >= 0xA0 and tag <= 0xBF:
        var str_len = Int(tag & 0x1F)
        var s = String()
        for j in range(str_len):
            if offset + j < len(bytes):
                s += chr(Int(bytes[offset + j]))
        offset += str_len
        return Value.of_text(s)

    # 7. Str 32: 0xDB
    if tag == 0xDB:
        var str_len = Int(_mp_decode_u32(bytes, offset))
        offset += 4
        var s = String()
        for j in range(str_len):
            if offset + j < len(bytes):
                s += chr(Int(bytes[offset + j]))
        offset += str_len
        return Value.of_text(s)

    # 8. FixArray: 0x90 - 0x9F (skip or decode first)
    if tag >= 0x90 and tag <= 0x9F:
        var arr_len = Int(tag & 0x0F)
        var s = String("[")
        for idx in range(arr_len):
            if idx > 0:
                s += ", "
            var elem = decode_msgpack_value(bytes, offset)
            s += elem.to_string()
        s += "]"
        return Value.of_text(s)

    return Value.of_null()


def sql_msgpack_pack(args: List[Value]) -> Value:
    """Encodes arguments into a MessagePack array BLOB."""
    var buf = List[UInt8]()
    var n = len(args)
    if n <= 15:
        buf.append(UInt8(0x90 | (n & 0x0F)))
    else:
        buf.append(0xDD) # array 32
        _mp_encode_u32(UInt32(n), buf)

    for i in range(n):
        _encode_value_msgpack(args[i], buf)

    return Value.of_text(hex_encode(buf))


def sql_msgpack_map(args: List[Value]) -> Value:
    """Encodes key/value pairs into a MessagePack map BLOB."""
    var buf = List[UInt8]()
    var n_pairs = len(args) // 2
    if n_pairs <= 15:
        buf.append(UInt8(0x80 | (n_pairs & 0x0F)))
    else:
        buf.append(0xDF) # map 32
        _mp_encode_u32(UInt32(n_pairs), buf)

    var i = 0
    while i + 1 < len(args):
        _encode_value_msgpack(args[i], buf)
        _encode_value_msgpack(args[i + 1], buf)
        i += 2

    return Value.of_text(hex_encode(buf))


def sql_msgpack_extract(msgpack_hex: String, key_or_index: String) -> Value:
    """Extracts a value by key or array index from a MessagePack hex BLOB."""
    var bytes = _mp_hex_to_bytes(msgpack_hex)
    if len(bytes) == 0:
        return Value.of_null()

    var offset = 0
    var tag = bytes[offset]
    offset += 1

    # Map extraction
    if (tag >= 0x80 and tag <= 0x8F) or tag == 0xDF:
        var map_len = Int(tag & 0x0F) if tag != 0xDF else Int(_mp_decode_u32(bytes, offset))
        if tag == 0xDF:
            offset += 4
        for _ in range(map_len):
            var k_val = decode_msgpack_value(bytes, offset)
            var v_val = decode_msgpack_value(bytes, offset)
            if k_val.to_string() == key_or_index:
                return v_val.copy()
        return Value.of_null()

    # Array extraction
    if (tag >= 0x90 and tag <= 0x9F) or tag == 0xDD:
        var arr_len = Int(tag & 0x0F) if tag != 0xDD else Int(_mp_decode_u32(bytes, offset))
        if tag == 0xDD:
            offset += 4
        try:
            var target_idx = Int(atol(key_or_index))
            for cur_idx in range(arr_len):
                var elem = decode_msgpack_value(bytes, offset)
                if cur_idx == target_idx:
                    return elem^
            return Value.of_null()
        except:
            return Value.of_null()

    return Value.of_null()

