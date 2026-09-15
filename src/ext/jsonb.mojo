""" Pure Mojo SQLite-compatible JSONB binary serialization and extraction engine.

SQLite 3.45+ introduced JSONB as a binary format stored in BLOB columns.
In LeanSQL, JSONB provides a self-describing binary encoding for JSON payloads:
- Tag 0: NULL
- Tag 1: TRUE
- Tag 2: FALSE
- Tag 3: INT (stored as 64-bit int)
- Tag 4: REAL (stored as 64-bit float)
- Tag 5: TEXT (stored with length prefix + bytes)
- Tag 6: ARRAY (element count + elements)
- Tag 7: OBJECT (entry count + key/value pairs)

Provides:
- jsonb(json_text) -> Value (JSONB binary representation)
- json(jsonb_val) -> Value (Formatted JSON text)
- jsonb_extract(jsonb_val, path) -> Value
"""

from src.engine.row import Value
from src.core.types import SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_NULL, SQLITE_BLOB
from src.ext.json import parse_json, parse_json_path, extract_json_by_path, JsonValue, JSON_NULL, JSON_BOOL, JSON_INT, JSON_REAL, JSON_TEXT, JSON_ARRAY, JSON_OBJECT
from src.ext.crypto import hex_encode, hex_decode, parse_hex_digit
from std.memory import bitcast

comptime JSONB_NULL = 0
comptime JSONB_TRUE = 1
comptime JSONB_FALSE = 2
comptime JSONB_INT = 3
comptime JSONB_REAL = 4
comptime JSONB_TEXT = 5
comptime JSONB_ARRAY = 6
comptime JSONB_OBJECT = 7


def _encode_u32(val: UInt32, mut buf: List[UInt8]):
    buf.append(UInt8((val >> 24) & 0xFF))
    buf.append(UInt8((val >> 16) & 0xFF))
    buf.append(UInt8((val >> 8) & 0xFF))
    buf.append(UInt8(val & 0xFF))


def _decode_u32(bytes: List[UInt8], offset: Int) -> UInt32:
    if offset + 4 > len(bytes):
        return 0
    var b0 = UInt32(bytes[offset])
    var b1 = UInt32(bytes[offset + 1])
    var b2 = UInt32(bytes[offset + 2])
    var b3 = UInt32(bytes[offset + 3])
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3


def _encode_i64(val: Int64, mut buf: List[UInt8]):
    var uv = UInt64(val)
    for i in range(8):
        var shift = (7 - i) * 8
        buf.append(UInt8((uv >> UInt64(shift)) & 0xFF))


def _decode_i64(bytes: List[UInt8], offset: Int) -> Int64:
    if offset + 8 > len(bytes):
        return 0
    var uv: UInt64 = 0
    for i in range(8):
        uv = (uv << 8) | UInt64(bytes[offset + i])
    return Int64(uv)


def _encode_f64(val: Float64, mut buf: List[UInt8]):
    var uv = bitcast[DType.uint64](val)
    for i in range(8):
        var shift = (7 - i) * 8
        buf.append(UInt8((uv >> UInt64(shift)) & 0xFF))


def _decode_f64(bytes: List[UInt8], offset: Int) -> Float64:
    if offset + 8 > len(bytes):
        return 0.0
    var uv: UInt64 = 0
    for i in range(8):
        uv = (uv << 8) | UInt64(bytes[offset + i])
    return bitcast[DType.float64](uv)


def _encode_json_node(node: JsonValue, mut buf: List[UInt8]):
    var tag = node.tag
    if tag == JSON_NULL:
        buf.append(UInt8(JSONB_NULL))
    elif tag == JSON_BOOL:
        if node.bool_val:
            buf.append(UInt8(JSONB_TRUE))
        else:
            buf.append(UInt8(JSONB_FALSE))
    elif tag == JSON_INT:
        buf.append(UInt8(JSONB_INT))
        _encode_i64(node.int_val, buf)
    elif tag == JSON_REAL:
        buf.append(UInt8(JSONB_REAL))
        _encode_f64(node.float_val, buf)
    elif tag == JSON_TEXT:
        buf.append(UInt8(JSONB_TEXT))
        var b = node.raw_val.as_bytes()
        _encode_u32(UInt32(len(b)), buf)
        for i in range(len(b)):
            buf.append(b[i])
    elif tag == JSON_ARRAY:
        buf.append(UInt8(JSONB_ARRAY))
        var count = len(node.values)
        _encode_u32(UInt32(count), buf)
        for i in range(count):
            _encode_json_node(node.values[i], buf)
    elif tag == JSON_OBJECT:
        buf.append(UInt8(JSONB_OBJECT))
        var count = len(node.keys)
        _encode_u32(UInt32(count), buf)
        for i in range(count):
            var k_bytes = node.keys[i].as_bytes()
            _encode_u32(UInt32(len(k_bytes)), buf)
            for j in range(len(k_bytes)):
                buf.append(k_bytes[j])
            _encode_json_node(node.values[i], buf)


def serialize_json_to_jsonb(json_text: String) -> List[UInt8]:
    var buf = List[UInt8]()
    try:
        var j_node = parse_json(json_text)
        _encode_json_node(j_node, buf)
    except:
        buf.append(UInt8(JSONB_NULL))
    return buf^


def _hex_to_bytes(hex_str: String) -> List[UInt8]:
    var bytes = List[UInt8]()
    var b = hex_str.as_bytes()
    var i = 0
    while i + 1 < len(b):
        var hi = parse_hex_digit(b[i])
        var lo = parse_hex_digit(b[i + 1])
        bytes.append(UInt8((hi << 4) | lo))
        i += 2
    return bytes^


def deserialize_jsonb_node(bytes: List[UInt8], mut offset: Int) -> JsonValue:
    if offset >= len(bytes):
        return JsonValue(JSON_NULL, "null")
    var tag = Int(bytes[offset])
    offset += 1

    if tag == JSONB_NULL:
        return JsonValue(JSON_NULL, "null")
    elif tag == JSONB_TRUE:
        var jv = JsonValue(JSON_BOOL, "true")
        jv.bool_val = True
        return jv^
    elif tag == JSONB_FALSE:
        var jv = JsonValue(JSON_BOOL, "false")
        jv.bool_val = False
        return jv^
    elif tag == JSONB_INT:
        var val = _decode_i64(bytes, offset)
        offset += 8
        var jv = JsonValue(JSON_INT, String(val))
        jv.int_val = val
        return jv^
    elif tag == JSONB_REAL:
        var val = _decode_f64(bytes, offset)
        offset += 8
        var jv = JsonValue(JSON_REAL, String(val))
        jv.float_val = val
        return jv^
    elif tag == JSONB_TEXT:
        var length = Int(_decode_u32(bytes, offset))
        offset += 4
        var s = String()
        for i in range(length):
            if offset + i < len(bytes):
                s += chr(Int(bytes[offset + i]))
        offset += length
        var jv = JsonValue(JSON_TEXT, s)
        return jv^
    elif tag == JSONB_ARRAY:
        var count = Int(_decode_u32(bytes, offset))
        offset += 4
        var jv = JsonValue(JSON_ARRAY, "")
        for _ in range(count):
            jv.values.append(deserialize_jsonb_node(bytes, offset))
        return jv^
    elif tag == JSONB_OBJECT:
        var count = Int(_decode_u32(bytes, offset))
        offset += 4
        var jv = JsonValue(JSON_OBJECT, "")
        for _ in range(count):
            var k_len = Int(_decode_u32(bytes, offset))
            offset += 4
            var k_str = String()
            for j in range(k_len):
                if offset + j < len(bytes):
                    k_str += chr(Int(bytes[offset + j]))
            offset += k_len
            jv.keys.append(k_str)
            jv.values.append(deserialize_jsonb_node(bytes, offset))
        return jv^
    return JsonValue(JSON_NULL, "null")


def jsonb_to_json_text(node: JsonValue) -> String:
    var tag = node.tag
    if tag == JSON_NULL:
        return "null"
    elif tag == JSON_BOOL:
        return "true" if node.bool_val else "false"
    elif tag == JSON_INT:
        return String(node.int_val)
    elif tag == JSON_REAL:
        return String(node.float_val)
    elif tag == JSON_TEXT:
        return "\"" + node.raw_val + "\""
    elif tag == JSON_ARRAY:
        var s = String("[")
        for i in range(len(node.values)):
            if i > 0:
                s += ", "
            s += jsonb_to_json_text(node.values[i])
        s += "]"
        return s
    elif tag == JSON_OBJECT:
        var s = String("{")
        for i in range(len(node.keys)):
            if i > 0:
                s += ", "
            s += "\"" + node.keys[i] + "\": " + jsonb_to_json_text(node.values[i])
        s += "}"
        return s
    return "null"


def sql_jsonb(text: String) -> Value:
    """SQL function: jsonb(json_text) -> hex-encoded binary JSONB string."""
    var bytes = serialize_json_to_jsonb(text)
    return Value.of_text(hex_encode(bytes))


def sql_json_from_jsonb(jsonb_or_json: String) -> Value:
    """SQL function: json(jsonb_blob_or_text) -> standard JSON text."""
    # Check if input is hex JSONB
    var is_hex = True
    var b = jsonb_or_json.as_bytes()
    if len(b) < 2 or (len(b) % 2 != 0):
        is_hex = False
    else:
        for i in range(len(b)):
            var c = b[i]
            var valid_hex = (c >= 48 and c <= 57) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70)
            if not valid_hex:
                is_hex = False
                break

    if is_hex:
        var bytes = _hex_to_bytes(jsonb_or_json)
        var offset = 0
        var node = deserialize_jsonb_node(bytes, offset)
        return Value.of_text(jsonb_to_json_text(node))

    # Fallback to direct json parser
    try:
        var node = parse_json(jsonb_or_json)
        return Value.of_text(jsonb_to_json_text(node))
    except:
        return Value.of_null()


def sql_jsonb_extract(jsonb_str: String, path_str: String) -> Value:
    """SQL function: jsonb_extract(jsonb_str, path)."""
    # Check if raw hex
    var is_hex = True
    var b = jsonb_str.as_bytes()
    if len(b) < 2 or (len(b) % 2 != 0):
        is_hex = False
    else:
        for i in range(len(b)):
            var c = b[i]
            var valid_hex = (c >= 48 and c <= 57) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70)
            if not valid_hex:
                is_hex = False
                break

    var root: JsonValue
    if is_hex:
        var bytes = _hex_to_bytes(jsonb_str)
        var offset = 0
        root = deserialize_jsonb_node(bytes, offset)
    else:
        try:
            root = parse_json(jsonb_str)
        except:
            return Value.of_null()

    try:
        var steps = parse_json_path(path_str)
        var res = extract_json_by_path(root, steps)
        if not res:
            return Value.of_null()
        return res.value().to_sqlite_value(True)
    except:
        return Value.of_null()
