from src.core.types import *
from src.engine.row import Value
from src.vdbe.opcode import *
from src.vdbe.vm import Vdbe, VDBE_RESULT_ROW, VDBE_RESULT_DONE
from src.storage.btree import MemBTree
from src.storage.record import encode_record


def test_vdbe_table_scan_and_insert() raises:
    print("=== Testing VDBE Table Insert & Full Table Scan Execution ===")
    
    # 1. Create a B-Tree table with 3 initial records
    var btree = MemBTree()
    for rid in range(1, 4):
        var vals = List[Value]()
        vals.append(Value.of_int(Int64(rid * 10)))
        vals.append(Value.of_text("User #" + String(rid)))
        var payload = encode_record(vals)
        btree.insert(Int64(rid), payload)

    # 2. Build VDBE Bytecode equivalent to: `SELECT id, name FROM users`
    # Op 0: OpenRead     0 (cursor 0), 0 (btree 0)
    # Op 1: Rewind       0 (cursor 0), 6 (jump to halt if empty)
    # Op 2: Column       0 (cursor 0), 0 (col 0), 1 (out reg 1)
    # Op 3: Column       0 (cursor 0), 1 (col 1), 2 (out reg 2)
    # Op 4: ResultRow    1 (start reg 1), 2 (2 cols)
    # Op 5: Next         0 (cursor 0), 2 (loop back to Op 2)
    # Op 6: Close        0 (cursor 0)
    # Op 7: Halt
    var vm = Vdbe()
    _ = vm.attach_btree(btree)

    vm.add_opcode(Opcode(OP_OPEN_READ, 0, 0))
    vm.add_opcode(Opcode(OP_REWIND, 0, 6))
    vm.add_opcode(Opcode(OP_COLUMN, 0, 0, 1))
    vm.add_opcode(Opcode(OP_COLUMN, 0, 1, 2))
    vm.add_opcode(Opcode(OP_RESULT_ROW, 1, 2))
    vm.add_opcode(Opcode(OP_NEXT, 0, 2))
    vm.add_opcode(Opcode(OP_CLOSE, 0))
    vm.add_opcode(Opcode(OP_HALT))

    var rows_received = 0
    var expected_names = List[String]()
    expected_names.append("User #1")
    expected_names.append("User #2")
    expected_names.append("User #3")

    while True:
        var rc = vm.step()
        if rc == VDBE_RESULT_ROW:
            var row = vm.current_result_row()
            if len(row) != 2:
                raise Error("Expected 2 columns in result row")
            var expected_id = Int64((rows_received + 1) * 10)
            if row[0].to_int() != expected_id:
                raise Error("Column 0 ID mismatch: expected " + String(expected_id) + ", got " + String(row[0].to_int()))
            if row[1].to_string() != expected_names[rows_received]:
                raise Error("Column 1 Name mismatch")
            rows_received += 1
        elif rc == VDBE_RESULT_DONE:
            break
        else:
            raise Error("Unexpected VDBE status: " + String(rc))

    if rows_received != 3:
        raise Error("Expected 3 rows received from VDBE scan, got " + String(rows_received))

    print("  Scanned 3 rows via VDBE OP_COLUMN & OP_NEXT loop successfully!")
    print("VDBE Table Scan test passed successfully!")


def main() raises:
    test_vdbe_table_scan_and_insert()
