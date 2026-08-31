from src.core.types import *
from src.engine.row import Value
from src.storage.record import encode_record
from src.storage.btree import MemBTree, BTreeCursor


def test_btree_insertion_and_cursor() raises:
    print("=== Testing B-Tree Insertion, Range Scans & Cursor Traversal ===")
    
    var btree = MemBTree()

    # 1. Insert 5 out-of-order records: rowids (10, 30, 20, 50, 40)
    var rowids = List[Int64]()
    rowids.append(10)
    rowids.append(30)
    rowids.append(20)
    rowids.append(50)
    rowids.append(40)

    for i in range(len(rowids)):
        var rid = rowids[i]
        var vals = List[Value]()
        vals.append(Value.of_int(rid))
        vals.append(Value.of_text("Item #" + String(rid)))
        var payload = encode_record(vals)
        btree.insert(rid, payload)

    if btree.cell_count() != 5:
        raise Error("Expected 5 cells in BTree, got: " + String(btree.cell_count()))

    print("  Inserted 5 records out of order.")

    # 2. Sequential forward scan via BTreeCursor (should be sorted by rowid: 10, 20, 30, 40, 50)
    var cur = BTreeCursor(btree)
    if not cur.first():
        raise Error("Cursor first() failed")

    var expected_rowids = List[Int64]()
    expected_rowids.append(10)
    expected_rowids.append(20)
    expected_rowids.append(30)
    expected_rowids.append(40)
    expected_rowids.append(50)

    var count = 0
    while cur.is_valid():
        var rid = cur.get_rowid()
        var rec = cur.get_record()
        if rid != expected_rowids[count]:
            raise Error("Rowid out of order! Expected " + String(expected_rowids[count]) + ", got " + String(rid))
        if rec[1].to_string() != "Item #" + String(rid):
            raise Error("Payload value mismatch at rowid: " + String(rid))

        count += 1
        _ = cur.next()

    if count != 5:
        raise Error("Cursor did not traverse all 5 items")
    print("  Forward scan verified: sorted order (10, 20, 30, 40, 50) OK!")

    # 3. Seek exact and range boundary (seek rowid 30)
    var cur_seek = BTreeCursor(btree)
    var found = cur_seek.seek_rowid(30)
    if not found or cur_seek.get_rowid() != 30:
        raise Error("Seek rowid 30 failed")
    print("  Exact seek for rowid 30: OK!")

    # 4. Seek non-existent key (seek 25 -> should land on 30)
    var found_ge = cur_seek.seek_rowid(25)
    if found_ge or cur_seek.get_rowid() != 30:
        raise Error("Range seek for 25 failed (should point to 30)")
    print("  Range seek for rowid 25 -> landed on 30: OK!")

    # 5. Delete operation
    var deleted = btree.delete(30)
    if not deleted or btree.cell_count() != 4:
        raise Error("Delete rowid 30 failed")

    var check_find = btree.find(30)
    if check_find:
        raise Error("Deleted rowid 30 should not exist")
    print("  Delete rowid 30 verified OK!")

    print("B-Tree and Cursor tests passed successfully!")


def main() raises:
    test_btree_insertion_and_cursor()
