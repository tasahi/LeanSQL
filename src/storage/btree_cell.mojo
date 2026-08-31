""" SQLite B-Tree Cell Structures and Binary Codecs.

Corresponds to cell formatting routines in `sqlite/src/btree.c`.

SQLite B-Tree cells vary depending on whether the page is a Table or Index,
and whether it is a Leaf or Interior node:

1. Leaf Table Cell (Page Type 0x0D):
   - payload_size: Varint
   - rowid: Varint (64-bit integer key)
   - payload: bytes[payload_size]

2. Interior Table Cell (Page Type 0x05):
   - left_child_pgno: 4-byte big-endian integer
   - rowid: Varint (64-bit integer key)

3. Leaf Index Cell (Page Type 0x0A):
   - payload_size: Varint
   - payload: bytes[payload_size]

4. Interior Index Cell (Page Type 0x02):
   - left_child_pgno: 4-byte big-endian integer
   - payload_size: Varint
   - payload: bytes[payload_size]
"""

from std.memory import Pointer
from src.core.types import *
from src.core.varint import put_varint, get_varint, encode_varint, decode_varint


struct TableLeafCell(ImplicitlyCopyable, Copyable, Movable):
    """ Represents a single key-value record stored on a B-Tree table leaf page."""
    var rowid: Int64
    var payload: List[UInt8]

    def __init__(out self, rowid: Int64, payload: List[UInt8]):
        self.rowid = rowid
        self.payload = payload.copy()

    def __init__(out self, *, copy: Self):
        self.rowid = copy.rowid
        self.payload = copy.payload.copy()

    def __init__(out self, *, deinit move: Self):
        self.rowid = move.rowid
        self.payload = move.payload^

    def encode(self) -> List[UInt8]:
        """ Serializes a leaf table cell into binary format."""
        var payload_len = len(self.payload)
        var enc_payload_len = encode_varint(UInt64(payload_len))
        var enc_rowid = encode_varint(UInt64(self.rowid))

        var res = List[UInt8]()
        for i in range(len(enc_payload_len)):
            res.append(enc_payload_len[i])
        for i in range(len(enc_rowid)):
            res.append(enc_rowid[i])
        for i in range(payload_len):
            res.append(self.payload[i])
        return res^

    @staticmethod
    def decode[origin: Origin](p: Pointer[UInt8, origin]) -> Tuple[TableLeafCell, Int]:
        """ Deserializes a TableLeafCell from pointer `p`. Returns (cell, bytes_consumed)."""
        var p_len: UInt64 = 0
        var n1 = get_varint(p, p_len)
        var p_rowid: UInt64 = 0
        var n2 = get_varint(p.unsafe_offset(n1), p_rowid)

        var payload_bytes = List[UInt8]()
        var offset = n1 + n2
        for i in range(Int(p_len)):
            payload_bytes.append(p[unsafe_offset=offset + i])

        var cell = TableLeafCell(Int64(p_rowid), payload_bytes)
        return Tuple(cell^, offset + Int(p_len))


struct TableInteriorCell(ImplicitlyCopyable, Copyable, Movable):
    """ Represents a branch pointer cell stored on a B-Tree table interior page."""
    var left_child: UInt32
    var rowid: Int64

    def __init__(out self, left_child: UInt32, rowid: Int64):
        self.left_child = left_child
        self.rowid = rowid

    def __init__(out self, *, copy: Self):
        self.left_child = copy.left_child
        self.rowid = copy.rowid

    def __init__(out self, *, deinit move: Self):
        self.left_child = move.left_child
        self.rowid = move.rowid

    def encode(self) -> List[UInt8]:
        """ Serializes an interior table cell (4-byte child page + varint rowid)."""
        var res = List[UInt8]()
        res.append(UInt8((self.left_child >> 24) & 0xFF))
        res.append(UInt8((self.left_child >> 16) & 0xFF))
        res.append(UInt8((self.left_child >> 8) & 0xFF))
        res.append(UInt8(self.left_child & 0xFF))

        var enc_rowid = encode_varint(UInt64(self.rowid))
        for i in range(len(enc_rowid)):
            res.append(enc_rowid[i])
        return res^

    @staticmethod
    def decode(bytes: List[UInt8]) -> TableInteriorCell:
        """ Deserializes an interior table cell from a byte buffer."""
        var left_child = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        var p = bytes.unsafe_ptr().unsafe_offset(4)
        var rowid_val: UInt64 = 0
        _ = get_varint(p, rowid_val)
        return TableInteriorCell(left_child, Int64(rowid_val))
