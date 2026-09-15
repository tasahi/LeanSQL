""" Pure Mojo SQLite-compatible Protocol Buffers Binary Wire-Format Reader Engine.

Implements reading Google Protocol Buffers wire format directly from BLOBs without
requiring a pre-compiled `.proto` descriptor.

Protobuf Wire Types:
- 0: Varint (int32, int64, uint32, uint64, sint32, sint64, bool, enum)
- 1: 64-bit (fixed64, sfixed64, double)
- 2: Length-delimited (string, bytes, embedded messages, packed repeated fields)
- 5: 32-bit (fixed32, sfixed32, float)

Provides SQL functions:
- pb_extract_int(blob_hex, field_number) -> Value (Int64)
- pb_extract_float(blob_hex, field_number) -> Value (Float64)
- pb_extract_string(blob_hex, field_number) -> Value (String)
"""

from src.engine.row import Value
from src.core.types import SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_NULL
from src.ext.crypto import parse_hex_digit
from std.memory import bitcast


def _pb_hex_to_bytes(hex_str: String) -> List[UInt8]:
    var bytes = List[UInt8]()
    var b = hex_str.as_bytes()
    var i = 0
    while i + 1 < len(b):
        var hi = parse_hex_digit(b[i])
        var lo = parse_hex_digit(b[i + 1])
        bytes.append(UInt8((hi << 4) | lo))
        i += 2
    return bytes^


def _read_pb_varint(bytes: List[UInt8], mut offset: Int) -> UInt64:
    var result: UInt64 = 0
    var shift: UInt64 = 0
    while offset < len(bytes):
        var b = UInt64(bytes[offset])
        offset += 1
        result |= (b & 0x7F) << shift
        if (b & 0x80) == 0:
            break
        shift += 7
        if shift >= 64:
            break
    return result


def _read_pb_f64_le(bytes: List[UInt8], mut offset: Int) -> Float64:
    if offset + 8 > len(bytes):
        return 0.0
    var uv: UInt64 = 0
    for i in range(8):
        uv |= UInt64(bytes[offset + i]) << UInt64(i * 8)
    offset += 8
    return bitcast[DType.float64](uv)


def _read_pb_f32_le(bytes: List[UInt8], mut offset: Int) -> Float32:
    if offset + 4 > len(bytes):
        return 0.0
    var uv: UInt32 = 0
    for i in range(4):
        uv |= UInt32(bytes[offset + i]) << UInt32(i * 8)
    offset += 4
    return bitcast[DType.float32](uv)


def sql_pb_extract_int(blob_hex: String, target_field: Int) -> Value:
    """Extracts an integer field (wire type 0 or fixed) by tag from a Protobuf wire buffer."""
    var bytes = _pb_hex_to_bytes(blob_hex)
    var offset = 0
    var n = len(bytes)

    while offset < n:
        var key = _read_pb_varint(bytes, offset)
        var field_number = Int(key >> 3)
        var wire_type = Int(key & 0x07)

        if wire_type == 0: # Varint
            var val = _read_pb_varint(bytes, offset)
            if field_number == target_field:
                return Value.of_int(Int64(val))
        elif wire_type == 1: # 64-bit
            if field_number == target_field:
                var uv: UInt64 = 0
                for i in range(8):
                    if offset + i < n:
                        uv |= UInt64(bytes[offset + i]) << UInt64(i * 8)
                offset += 8
                return Value.of_int(Int64(uv))
            offset += 8
        elif wire_type == 2: # Length-delimited
            var length = Int(_read_pb_varint(bytes, offset))
            offset += length
        elif wire_type == 5: # 32-bit
            if field_number == target_field:
                var uv: UInt32 = 0
                for i in range(4):
                    if offset + i < n:
                        uv |= UInt32(bytes[offset + i]) << UInt32(i * 8)
                offset += 4
                return Value.of_int(Int64(uv))
            offset += 4
        else:
            # Unknown wire type, cannot proceed safely
            break

    return Value.of_null()


def sql_pb_extract_float(blob_hex: String, target_field: Int) -> Value:
    """Extracts a floating-point field (double or float) by tag from a Protobuf wire buffer."""
    var bytes = _pb_hex_to_bytes(blob_hex)
    var offset = 0
    var n = len(bytes)

    while offset < n:
        var key = _read_pb_varint(bytes, offset)
        var field_number = Int(key >> 3)
        var wire_type = Int(key & 0x07)

        if wire_type == 0:
            _ = _read_pb_varint(bytes, offset)
        elif wire_type == 1: # 64-bit double
            var d = _read_pb_f64_le(bytes, offset)
            if field_number == target_field:
                return Value.of_float(d)
        elif wire_type == 2: # Length-delimited
            var length = Int(_read_pb_varint(bytes, offset))
            offset += length
        elif wire_type == 5: # 32-bit float
            var f = _read_pb_f32_le(bytes, offset)
            if field_number == target_field:
                return Value.of_float(Float64(f))
        else:
            break

    return Value.of_null()


def sql_pb_extract_string(blob_hex: String, target_field: Int) -> Value:
    """Extracts a string / bytes field (wire type 2) by tag from a Protobuf wire buffer."""
    var bytes = _pb_hex_to_bytes(blob_hex)
    var offset = 0
    var n = len(bytes)

    while offset < n:
        var key = _read_pb_varint(bytes, offset)
        var field_number = Int(key >> 3)
        var wire_type = Int(key & 0x07)

        if wire_type == 0:
            _ = _read_pb_varint(bytes, offset)
        elif wire_type == 1:
            offset += 8
        elif wire_type == 2:
            var length = Int(_read_pb_varint(bytes, offset))
            if field_number == target_field:
                var s = String()
                for i in range(length):
                    if offset + i < n:
                        s += chr(Int(bytes[offset + i]))
                return Value.of_text(s)
            offset += length
        elif wire_type == 5:
            offset += 4
        else:
            break

    return Value.of_null()

