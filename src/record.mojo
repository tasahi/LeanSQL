""" SQLite Record Format Serialization and Deserialization.

Corresponds to `sqlite3VdbeRecordUnpack` and `sqlite3VdbeRecordPack`
in `sqlite/src/vdbeaux.c`.
"""

from std.memory import Pointer
from src.types import *
from src.row import Value
from src.varint import encode_varint, get_varint
from src.serial import get_serial_type, serial_type_len, encode_value, decode_value


def encode_record(values: List[Value]) -> List[UInt8]:
    """Serializes a list of `Value`s into standard SQLite record format."""
    var num_cols = len(values)
    var serial_types = List[UInt32]()
    var body_size: Int = 0

    # 1. Compute serial types and total body size
    for i in range(num_cols):
        var st = get_serial_type(values[i])
        serial_types.append(st)
        body_size += serial_type_len(st)

    # 2. Compute serial types varints
    var st_bytes = List[UInt8]()
    for i in range(num_cols):
        var enc_st = encode_varint(UInt64(serial_types[i]))
        for j in range(len(enc_st)):
            st_bytes.append(enc_st[j])

    # 3. Header size includes itself (as a varint) + all serial type varints
    var header_payload_len = len(st_bytes)
    var header_size_varint_len = 1
    if header_payload_len + 1 >= 0x80:
        header_size_varint_len = 2
    var total_header_size = UInt64(header_size_varint_len + header_payload_len)

    var enc_hdr_size = encode_varint(total_header_size)

    var result = List[UInt8]()
    # 1. Header size
    for i in range(len(enc_hdr_size)):
        result.append(enc_hdr_size[i])
    # 2. Serial types
    for i in range(len(st_bytes)):
        result.append(st_bytes[i])

    # 3. Body values
    var val_buf = List[UInt8]()
    for _ in range(body_size + 64):
        val_buf.append(0)
    var val_offset: Int = 0
    for i in range(num_cols):
        var p_dest = val_buf.unsafe_ptr().unsafe_offset(val_offset)
        var n_written = encode_value(values[i], p_dest)
        val_offset += n_written

    for i in range(val_offset):
        result.append(val_buf[i])

    return result^


def decode_record(payload: List[UInt8]) -> List[Value]:
    """Deserializes a raw SQLite record payload into a list of `Value`s."""
    var n_payload = len(payload)
    if n_payload == 0:
        return List[Value]()

    var p_buf = payload.unsafe_ptr()
    
    # 1. Read header size
    var hdr_size_val: UInt64 = 0
    var hdr_varint_len = get_varint(p_buf, hdr_size_val)
    var total_hdr_size = Int(hdr_size_val)

    # 2. Read serial types
    var offset = hdr_varint_len
    var serial_types = List[UInt32]()
    while offset < total_hdr_size and offset < n_payload:
        var p_curr = p_buf.unsafe_offset(offset)
        var st_val: UInt64 = 0
        var n_st = get_varint(p_curr, st_val)
        serial_types.append(UInt32(st_val))
        offset += n_st

    # 3. Read body values
    var body_offset = total_hdr_size
    var values = List[Value]()
    for i in range(len(serial_types)):
        var st = serial_types[i]
        var v_len = serial_type_len(st)
        var p_val = p_buf.unsafe_offset(body_offset)
        var val = decode_value(st, p_val)
        values.append(val)
        body_offset += v_len

    return values^
