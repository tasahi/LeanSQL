"""SQLite Database File Header and B-Tree Page Header Codecs.

Corresponds to `sqlite/src/btree.h` and `sqlite/src/btreeInt.h`.

Implements:
1. `DbHeader`: 100-byte SQLite database file header at offset 0 of page 1.
2. `PageHeader`: 8-byte (leaf) and 12-byte (interior) B-tree page headers.
3. Cell pointer decoding and serialization.
"""

from std.memory import Pointer
from src.core.types import *

# === B-Tree Page Type Flags ===
comptime PTF_INTKEY = 1    # 0x01: Integer keys (Table B-Tree)
comptime PTF_ZERODATA = 2  # 0x02: Keys only, no data (Index B-Tree)
comptime PTF_LEAFDATA = 4  # 0x04: Data stored only on leaves
comptime PTF_LEAF = 8      # 0x08: Leaf page (no children pointers)

comptime PAGE_TYPE_INTERIOR_INDEX = 0x02  # PTF_ZERODATA | PTF_INTKEY (Index Interior)
comptime PAGE_TYPE_INTERIOR_TABLE = 0x05  # PTF_INTKEY | PTF_LEAFDATA (Table Interior)
comptime PAGE_TYPE_LEAF_INDEX = 0x0A      # PTF_ZERODATA | PTF_LEAF (Index Leaf)
comptime PAGE_TYPE_LEAF_TABLE = 0x0D      # PTF_INTKEY | PTF_LEAFDATA | PTF_LEAF (Table Leaf)

# Magic header string: "SQLite format 3\000"
comptime SQLITE_FILE_HEADER_MAGIC = "SQLite format 3\x00"


struct DbHeader(ImplicitlyCopyable, Copyable, Movable):
    """Represents the 100-byte SQLite Database File Header."""
    var page_size: UInt32
    var write_version: UInt8
    var read_version: UInt8
    var reserved_space: UInt8
    var max_payload_frac: UInt8
    var min_payload_frac: UInt8
    var leaf_payload_frac: UInt8
    var file_change_counter: UInt32
    var db_size_pages: UInt32
    var first_freelist_page: UInt32
    var num_freelist_pages: UInt32
    var schema_cookie: UInt32
    var schema_format: UInt32
    var default_cache_size: UInt32
    var user_version: UInt32
    var text_encoding: UInt32
    var app_id: UInt32
    var version_valid_for: UInt32
    var sqlite_version_number: UInt32

    def __init__(out self):
        self.page_size = 4096
        self.write_version = 1
        self.read_version = 1
        self.reserved_space = 0
        self.max_payload_frac = 64
        self.min_payload_frac = 32
        self.leaf_payload_frac = 32
        self.file_change_counter = 1
        self.db_size_pages = 1
        self.first_freelist_page = 0
        self.num_freelist_pages = 0
        self.schema_cookie = 1
        self.schema_format = 4
        self.default_cache_size = 0
        self.user_version = 0
        self.text_encoding = 1  # 1 = UTF-8
        self.app_id = 0
        self.version_valid_for = 1
        self.sqlite_version_number = 3045000

    def __init__(out self, *, copy: Self):
        self.page_size = copy.page_size
        self.write_version = copy.write_version
        self.read_version = copy.read_version
        self.reserved_space = copy.reserved_space
        self.max_payload_frac = copy.max_payload_frac
        self.min_payload_frac = copy.min_payload_frac
        self.leaf_payload_frac = copy.leaf_payload_frac
        self.file_change_counter = copy.file_change_counter
        self.db_size_pages = copy.db_size_pages
        self.first_freelist_page = copy.first_freelist_page
        self.num_freelist_pages = copy.num_freelist_pages
        self.schema_cookie = copy.schema_cookie
        self.schema_format = copy.schema_format
        self.default_cache_size = copy.default_cache_size
        self.user_version = copy.user_version
        self.text_encoding = copy.text_encoding
        self.app_id = copy.app_id
        self.version_valid_for = copy.version_valid_for
        self.sqlite_version_number = copy.sqlite_version_number

    def __init__(out self, *, deinit move: Self):
        self.page_size = move.page_size
        self.write_version = move.write_version
        self.read_version = move.read_version
        self.reserved_space = move.reserved_space
        self.max_payload_frac = move.max_payload_frac
        self.min_payload_frac = move.min_payload_frac
        self.leaf_payload_frac = move.leaf_payload_frac
        self.file_change_counter = move.file_change_counter
        self.db_size_pages = move.db_size_pages
        self.first_freelist_page = move.first_freelist_page
        self.num_freelist_pages = move.num_freelist_pages
        self.schema_cookie = move.schema_cookie
        self.schema_format = move.schema_format
        self.default_cache_size = move.default_cache_size
        self.user_version = move.user_version
        self.text_encoding = move.text_encoding
        self.app_id = move.app_id
        self.version_valid_for = move.version_valid_for
        self.sqlite_version_number = move.sqlite_version_number

    @staticmethod
    def read_u16(buf: List[UInt8], offset: Int) -> UInt16:
        return (UInt16(buf[offset]) << 8) | UInt16(buf[offset + 1])

    @staticmethod
    def read_u32(buf: List[UInt8], offset: Int) -> UInt32:
        return (UInt32(buf[offset]) << 24) | (UInt32(buf[offset + 1]) << 16) | (UInt32(buf[offset + 2]) << 8) | UInt32(buf[offset + 3])

    @staticmethod
    def write_u16(mut buf: List[UInt8], offset: Int, v: UInt16):
        buf[offset] = UInt8((v >> 8) & 0xFF)
        buf[offset + 1] = UInt8(v & 0xFF)

    @staticmethod
    def write_u32(mut buf: List[UInt8], offset: Int, v: UInt32):
        buf[offset] = UInt8((v >> 24) & 0xFF)
        buf[offset + 1] = UInt8((v >> 16) & 0xFF)
        buf[offset + 2] = UInt8((v >> 8) & 0xFF)
        buf[offset + 3] = UInt8(v & 0xFF)

    @staticmethod
    def decode(buf: List[UInt8]) raises -> DbHeader:
        """Parses a 100-byte database file header."""
        if len(buf) < 100:
            raise Error("DbHeader too short: expected 100 bytes, got " + String(len(buf)))

        # Verify magic: "SQLite format 3\000"
        var magic_bytes = SQLITE_FILE_HEADER_MAGIC.as_bytes()
        for i in range(16):
            if buf[i] != magic_bytes[i]:
                raise Error("Invalid SQLite header magic string")

        var h = DbHeader()
        var ps_raw = DbHeader.read_u16(buf, 16)
        h.page_size = 65536 if ps_raw == 1 else UInt32(ps_raw)
        h.write_version = buf[18]
        h.read_version = buf[19]
        h.reserved_space = buf[20]
        h.max_payload_frac = buf[21]
        h.min_payload_frac = buf[22]
        h.leaf_payload_frac = buf[23]
        h.file_change_counter = DbHeader.read_u32(buf, 24)
        h.db_size_pages = DbHeader.read_u32(buf, 28)
        h.first_freelist_page = DbHeader.read_u32(buf, 32)
        h.num_freelist_pages = DbHeader.read_u32(buf, 36)
        h.schema_cookie = DbHeader.read_u32(buf, 40)
        h.schema_format = DbHeader.read_u32(buf, 44)
        h.default_cache_size = DbHeader.read_u32(buf, 48)
        h.user_version = DbHeader.read_u32(buf, 60)
        h.text_encoding = DbHeader.read_u32(buf, 56)
        h.app_id = DbHeader.read_u32(buf, 68)
        h.version_valid_for = DbHeader.read_u32(buf, 92)
        h.sqlite_version_number = DbHeader.read_u32(buf, 96)
        return h

    def encode(self) -> List[UInt8]:
        """Serializes the database header into 100 bytes."""
        var res = List[UInt8]()
        for _ in range(100):
            res.append(0)

        # Magic
        var magic_bytes = SQLITE_FILE_HEADER_MAGIC.as_bytes()
        for i in range(16):
            res[i] = magic_bytes[i]

        var ps_field: UInt16 = 1 if self.page_size == 65536 else UInt16(self.page_size)
        DbHeader.write_u16(res, 16, ps_field)
        res[18] = self.write_version
        res[19] = self.read_version
        res[20] = self.reserved_space
        res[21] = self.max_payload_frac
        res[22] = self.min_payload_frac
        res[23] = self.leaf_payload_frac
        DbHeader.write_u32(res, 24, self.file_change_counter)
        DbHeader.write_u32(res, 28, self.db_size_pages)
        DbHeader.write_u32(res, 32, self.first_freelist_page)
        DbHeader.write_u32(res, 36, self.num_freelist_pages)
        DbHeader.write_u32(res, 40, self.schema_cookie)
        DbHeader.write_u32(res, 44, self.schema_format)
        DbHeader.write_u32(res, 48, self.default_cache_size)
        DbHeader.write_u32(res, 56, self.text_encoding)
        DbHeader.write_u32(res, 60, self.user_version)
        DbHeader.write_u32(res, 68, self.app_id)
        DbHeader.write_u32(res, 92, self.version_valid_for)
        DbHeader.write_u32(res, 96, self.sqlite_version_number)
        return res^


struct PageHeader(ImplicitlyCopyable, Copyable, Movable):
    """Represents an 8-byte (leaf) or 12-byte (interior) B-Tree Page Header."""
    var page_type: UInt8
    var first_freeblock: UInt16
    var cell_count: UInt16
    var cell_content_offset: UInt16
    var fragmented_free_bytes: UInt8
    var right_child_page: UInt32  # Interior nodes only (0 on leaves)

    def __init__(out self, page_type: UInt8):
        self.page_type = page_type
        self.first_freeblock = 0
        self.cell_count = 0
        self.cell_content_offset = 0
        self.fragmented_free_bytes = 0
        self.right_child_page = 0

    def __init__(out self, *, copy: Self):
        self.page_type = copy.page_type
        self.first_freeblock = copy.first_freeblock
        self.cell_count = copy.cell_count
        self.cell_content_offset = copy.cell_content_offset
        self.fragmented_free_bytes = copy.fragmented_free_bytes
        self.right_child_page = copy.right_child_page

    def __init__(out self, *, deinit move: Self):
        self.page_type = move.page_type
        self.first_freeblock = move.first_freeblock
        self.cell_count = move.cell_count
        self.cell_content_offset = move.cell_content_offset
        self.fragmented_free_bytes = move.fragmented_free_bytes
        self.right_child_page = move.right_child_page

    def is_leaf(self) -> Bool:
        """Returns True if this is a leaf page (0x0A or 0x0D)."""
        return Bool(self.page_type & UInt8(PTF_LEAF))

    def header_size(self) -> Int:
        """Returns the size of this header: 8 bytes for leaf, 12 bytes for interior."""
        return 8 if self.is_leaf() else 12

    @staticmethod
    def decode(p: Pointer[UInt8, ImmutAnyOrigin], offset: Int) -> PageHeader:
        """Decodes a page header from pointer `p` at `offset`."""
        var p_hdr = p.unsafe_offset(offset)
        var pt = p_hdr[unsafe_offset=0]
        var h = PageHeader(pt)
        h.first_freeblock = (UInt16(p_hdr[unsafe_offset=1]) << 8) | UInt16(p_hdr[unsafe_offset=2])
        h.cell_count = (UInt16(p_hdr[unsafe_offset=3]) << 8) | UInt16(p_hdr[unsafe_offset=4])
        h.cell_content_offset = (UInt16(p_hdr[unsafe_offset=5]) << 8) | UInt16(p_hdr[unsafe_offset=6])
        h.fragmented_free_bytes = p_hdr[unsafe_offset=7]
        if not h.is_leaf():
            h.right_child_page = (UInt32(p_hdr[unsafe_offset=8]) << 24) | (UInt32(p_hdr[unsafe_offset=9]) << 16) | (UInt32(p_hdr[unsafe_offset=10]) << 8) | UInt32(p_hdr[unsafe_offset=11])
        return h

    def encode(self, p: Pointer[UInt8, MutAnyOrigin], offset: Int) -> Int:
        """Encodes this page header into `p` at `offset`. Returns bytes written."""
        var p_hdr = p.unsafe_offset(offset)
        p_hdr[unsafe_offset=0] = self.page_type
        p_hdr[unsafe_offset=1] = UInt8((self.first_freeblock >> 8) & 0xFF)
        p_hdr[unsafe_offset=2] = UInt8(self.first_freeblock & 0xFF)
        p_hdr[unsafe_offset=3] = UInt8((self.cell_count >> 8) & 0xFF)
        p_hdr[unsafe_offset=4] = UInt8(self.cell_count & 0xFF)
        p_hdr[unsafe_offset=5] = UInt8((self.cell_content_offset >> 8) & 0xFF)
        p_hdr[unsafe_offset=6] = UInt8(self.cell_content_offset & 0xFF)
        p_hdr[unsafe_offset=7] = self.fragmented_free_bytes
        if not self.is_leaf():
            p_hdr[unsafe_offset=8] = UInt8((self.right_child_page >> 24) & 0xFF)
            p_hdr[unsafe_offset=9] = UInt8((self.right_child_page >> 16) & 0xFF)
            p_hdr[unsafe_offset=10] = UInt8((self.right_child_page >> 8) & 0xFF)
            p_hdr[unsafe_offset=11] = UInt8(self.right_child_page & 0xFF)
            return 12
        return 8


def read_cell_pointer(p: Pointer[UInt8, ImmutAnyOrigin], ptr_offset: Int) -> UInt16:
    """Reads a 2-byte big-endian cell pointer offset."""
    return (UInt16(p[unsafe_offset=ptr_offset]) << 8) | UInt16(p[unsafe_offset=ptr_offset + 1])


def write_cell_pointer(p: Pointer[UInt8, MutAnyOrigin], ptr_offset: Int, cell_offset: UInt16):
    """Writes a 2-byte big-endian cell pointer offset."""
    p[unsafe_offset=ptr_offset] = UInt8((cell_offset >> 8) & 0xFF)
    p[unsafe_offset=ptr_offset + 1] = UInt8(cell_offset & 0xFF)
