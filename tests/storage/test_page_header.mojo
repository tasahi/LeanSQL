from std.memory import alloc, UnsafePointer
from src.core.types import *
from src.storage.page_header import DbHeader, PageHeader, PAGE_TYPE_LEAF_TABLE, PAGE_TYPE_INTERIOR_TABLE, PAGE_TYPE_LEAF_INDEX, PAGE_TYPE_INTERIOR_INDEX, read_cell_pointer, write_cell_pointer


def test_db_header() raises:
    print("=== Testing SQLite 100-byte Database Header ===")
    
    var h = DbHeader()
    h.page_size = 4096
    h.file_change_counter = 1234
    h.db_size_pages = 42
    h.schema_cookie = 7
    h.user_version = 10

    var encoded = h.encode()
    if len(encoded) != 100:
        raise Error("Encoded DB header length must be exactly 100 bytes, got " + String(len(encoded)))

    var decoded = DbHeader.decode(encoded)
    if decoded.page_size != 4096:
        raise Error("Page size mismatch")
    if decoded.file_change_counter != 1234:
        raise Error("Change counter mismatch")
    if decoded.db_size_pages != 42:
        raise Error("DB size mismatch")
    if decoded.schema_cookie != 7:
        raise Error("Schema cookie mismatch")
    if decoded.user_version != 10:
        raise Error("User version mismatch")

    print("  Page size:", decoded.page_size)
    print("  Change counter:", decoded.file_change_counter)
    print("  DB size (pages):", decoded.db_size_pages)
    print("DbHeader test passed!")


def test_page_headers_and_cell_pointers() raises:
    print("=== Testing B-Tree Page Headers & Cell Pointers ===")
    var p = alloc[UInt8](512)

    # 1. Leaf Table Page Header (0x0D - 8 bytes)
    var leaf_hdr = PageHeader(UInt8(PAGE_TYPE_LEAF_TABLE))
    leaf_hdr.cell_count = 5
    leaf_hdr.cell_content_offset = 400
    leaf_hdr.first_freeblock = 0
    leaf_hdr.fragmented_free_bytes = 0

    var bytes_written = leaf_hdr.encode(p, 0)
    if bytes_written != 8 or not leaf_hdr.is_leaf():
        p.free()
        raise Error("Leaf header should be 8 bytes")

    var immut_p = UnsafePointer[UInt8, ImmutAnyOrigin](other=p)
    var dec_leaf = PageHeader.decode(immut_p, 0)
    if dec_leaf.page_type != UInt8(PAGE_TYPE_LEAF_TABLE) or dec_leaf.cell_count != 5 or dec_leaf.cell_content_offset != 400:
        p.free()
        raise Error("Decoded leaf header mismatch")

    print("  Leaf Table Page Header (0x0D): OK (8 bytes)")

    # 2. Interior Table Page Header (0x05 - 12 bytes)
    var int_hdr = PageHeader(UInt8(PAGE_TYPE_INTERIOR_TABLE))
    int_hdr.cell_count = 12
    int_hdr.cell_content_offset = 256
    int_hdr.right_child_page = 4

    var int_bytes = int_hdr.encode(p, 0)
    if int_bytes != 12 or int_hdr.is_leaf():
        p.free()
        raise Error("Interior header should be 12 bytes")

    var dec_int = PageHeader.decode(immut_p, 0)
    if dec_int.page_type != UInt8(PAGE_TYPE_INTERIOR_TABLE) or dec_int.cell_count != 12 or dec_int.right_child_page != 4:
        p.free()
        raise Error("Decoded interior header mismatch")

    print("  Interior Table Page Header (0x05): OK (12 bytes, right_child=4)")

    # 3. Cell Pointer Array
    var cell_offsets = List[UInt16]()
    cell_offsets.append(490)
    cell_offsets.append(470)
    cell_offsets.append(440)

    # Write cell pointers right after 8-byte leaf header
    for i in range(len(cell_offsets)):
        write_cell_pointer(p, 8 + i * 2, cell_offsets[i])

    for i in range(len(cell_offsets)):
        var read_off = read_cell_pointer(immut_p, 8 + i * 2)
        if read_off != cell_offsets[i]:
            p.free()
            raise Error("Cell pointer mismatch at index " + String(i))

    print("  Cell Pointers (2-byte big endian offsets): OK")

    p.free()
    print("PageHeader tests passed successfully!")


def main() raises:
    test_db_header()
    test_page_headers_and_cell_pointers()
