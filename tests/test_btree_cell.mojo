from std.memory import alloc, UnsafePointer
from src.types import *
from src.btree_cell import TableLeafCell, TableInteriorCell


def test_table_leaf_cell() raises:
    print("=== Testing TableLeafCell Codecs ===")
    
    var payload = List[UInt8]()
    payload.append(0x11)
    payload.append(0x22)
    payload.append(0x33)

    var cell = TableLeafCell(42, payload)
    var enc = cell.encode()
    print("  Encoded Leaf Cell Size:", len(enc), "bytes")

    var p = alloc[UInt8](len(enc))
    for i in range(len(enc)):
        p[i] = enc[i]

    var immut_p = UnsafePointer[UInt8, ImmutAnyOrigin](other=p)
    var res = TableLeafCell.decode(immut_p)
    var dec_cell = res[0]
    var bytes_read = res[1]

    if bytes_read != len(enc):
        p.free()
        raise Error("Leaf cell bytes read mismatch")
    if dec_cell.rowid != 42:
        p.free()
        raise Error("Decoded rowid mismatch")
    if len(dec_cell.payload) != 3 or dec_cell.payload[0] != 0x11 or dec_cell.payload[2] != 0x33:
        p.free()
        raise Error("Decoded payload mismatch")

    p.free()
    print("TableLeafCell test passed successfully!")


def test_table_interior_cell() raises:
    print("=== Testing TableInteriorCell Codecs ===")
    
    var cell = TableInteriorCell(7, 100500)
    var enc = cell.encode()

    var p = alloc[UInt8](len(enc))
    for i in range(len(enc)):
        p[i] = enc[i]

    var immut_p = UnsafePointer[UInt8, ImmutAnyOrigin](other=p)
    var res = TableInteriorCell.decode(immut_p)
    var dec_cell = res[0]
    var bytes_read = res[1]

    if bytes_read != len(enc):
        p.free()
        raise Error("Interior cell bytes read mismatch")
    if dec_cell.left_child != 7:
        p.free()
        raise Error("Decoded left child mismatch")
    if dec_cell.rowid != 100500:
        p.free()
        raise Error("Decoded interior rowid mismatch")

    p.free()
    print("TableInteriorCell test passed successfully!")


def main() raises:
    test_table_leaf_cell()
    test_table_interior_cell()
