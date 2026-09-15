""" Pure Mojo SQLite-compatible Spatial / Geometry (OGC WKB) Extension.

Implements SpatiaLite-compatible OpenGIS Well-Known Binary (WKB) format and functions:
- OGC WKB Format for 2D Point (21 bytes):
  - Byte 0: Endianness (1 = Little-Endian)
  - Bytes 1-4: Geometry Type uint32 (1 = Point)
  - Bytes 5-12: X coordinate float64 (little-endian)
  - Bytes 13-20: Y coordinate float64 (little-endian)

Provides SQL functions:
- ST_Point(x, y) -> Hex-encoded WKB BLOB
- ST_X(geom_hex) -> Float64 X coordinate
- ST_Y(geom_hex) -> Float64 Y coordinate
- ST_Distance(g1_hex, g2_hex) -> Euclidean distance
- ST_AsText(geom_hex) -> WKT String e.g. 'POINT(10.5 20.0)'
"""

from src.engine.row import Value
from src.core.types import SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_NULL
from src.ext.crypto import hex_encode, parse_hex_digit
from std.memory import bitcast
from std.math import sqrt

comptime WKB_POINT = 1
comptime WKB_LITTLE_ENDIAN = 1


def _wkb_hex_to_bytes(hex_str: String) -> List[UInt8]:
    var bytes = List[UInt8]()
    var b = hex_str.as_bytes()
    var i = 0
    while i + 1 < len(b):
        var hi = parse_hex_digit(b[i])
        var lo = parse_hex_digit(b[i + 1])
        bytes.append(UInt8((hi << 4) | lo))
        i += 2
    return bytes^


def _wkb_encode_f64_le(val: Float64, mut buf: List[UInt8]):
    var uv = bitcast[DType.uint64](val)
    for i in range(8):
        buf.append(UInt8((uv >> UInt64(i * 8)) & 0xFF))


def _wkb_decode_f64_le(bytes: List[UInt8], offset: Int) -> Float64:
    if offset + 8 > len(bytes):
        return 0.0
    var uv: UInt64 = 0
    for i in range(8):
        uv |= UInt64(bytes[offset + i]) << UInt64(i * 8)
    return bitcast[DType.float64](uv)


def sql_st_point(x: Float64, y: Float64) -> Value:
    """Constructs a 21-byte OGC WKB Point BLOB."""
    var buf = List[UInt8]()
    # Byte 0: Little-endian
    buf.append(1)
    # Bytes 1-4: Geometry Type (1 = Point)
    buf.append(1)
    buf.append(0)
    buf.append(0)
    buf.append(0)
    # Bytes 5-12: X coordinate
    _wkb_encode_f64_le(x, buf)
    # Bytes 13-20: Y coordinate
    _wkb_encode_f64_le(y, buf)

    return Value.of_text(hex_encode(buf))


def sql_st_x(geom_hex: String) -> Value:
    """Extracts X coordinate from a WKB Point geometry BLOB."""
    var bytes = _wkb_hex_to_bytes(geom_hex)
    if len(bytes) < 21:
        return Value.of_null()
    # Check type == 1
    if bytes[1] != 1 or bytes[2] != 0:
        return Value.of_null()
    var x = _wkb_decode_f64_le(bytes, 5)
    return Value.of_float(x)


def sql_st_y(geom_hex: String) -> Value:
    """Extracts Y coordinate from a WKB Point geometry BLOB."""
    var bytes = _wkb_hex_to_bytes(geom_hex)
    if len(bytes) < 21:
        return Value.of_null()
    if bytes[1] != 1 or bytes[2] != 0:
        return Value.of_null()
    var y = _wkb_decode_f64_le(bytes, 13)
    return Value.of_float(y)


def sql_st_distance(g1_hex: String, g2_hex: String) -> Value:
    """Calculates the Euclidean distance between two WKB Point geometries."""
    var b1 = _wkb_hex_to_bytes(g1_hex)
    var b2 = _wkb_hex_to_bytes(g2_hex)
    if len(b1) < 21 or len(b2) < 21:
        return Value.of_null()

    var x1 = _wkb_decode_f64_le(b1, 5)
    var y1 = _wkb_decode_f64_le(b1, 13)
    var x2 = _wkb_decode_f64_le(b2, 5)
    var y2 = _wkb_decode_f64_le(b2, 13)

    var dx = x1 - x2
    var dy = y1 - y2
    return Value.of_float(sqrt(dx * dx + dy * dy))


def sql_st_astext(geom_hex: String) -> Value:
    """Converts a WKB geometry BLOB into Well-Known Text (WKT) representation."""
    var bytes = _wkb_hex_to_bytes(geom_hex)
    if len(bytes) < 21:
        return Value.of_null()
    var x = _wkb_decode_f64_le(bytes, 5)
    var y = _wkb_decode_f64_le(bytes, 13)
    var s = "POINT(" + String(x) + " " + String(y) + ")"
    return Value.of_text(s)

