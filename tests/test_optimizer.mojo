from src.types import *
from src.row import Value
from src.record import encode_record
from src.btree import MemBTree
from src.tokenizer import tokenize_sql
from src.parser import parse_select
from src.optimizer import optimize_where_clause, compile_optimized_select, PLAN_ROWID_SEEK, PLAN_FULL_SCAN
from src.vdbe import VDBE_RESULT_ROW, VDBE_RESULT_DONE


def test_query_optimizer_rowid_seek() raises:
    print("=== Testing WhereScan Query Optimization (RowID Seek) ===")
    
    # 1. Populate table with 10 records: rowid 1..10
    var btree = MemBTree()
    for rid in range(1, 11):
        var vals = List[Value]()
        vals.append(Value.of_int(Int64(rid)))
        vals.append(Value.of_text("Record #" + String(rid)))
        btree.insert(Int64(rid), encode_record(vals))

    # 2. Query with Primary Key equality: `SELECT id, name FROM users WHERE id = 7`
    var sql = "SELECT id, name FROM users WHERE id = 7"
    var tokens = tokenize_sql(sql)
    var ast = parse_select(tokens)

    # 3. Check Query Plan
    var plan = optimize_where_clause(ast)
    if plan.plan_type != PLAN_ROWID_SEEK or plan.seek_rowid != 7:
        raise Error("Optimizer failed to select PLAN_ROWID_SEEK for 'id = 7'")

    print("  Optimizer successfully selected PLAN_ROWID_SEEK (O(log N))!")

    # 4. Compile optimized VDBE bytecode
    var vm = compile_optimized_select(ast, 0)
    _ = vm.attach_btree(btree)

    # 5. Execute VDBE program
    var rc = vm.step()
    if rc != VDBE_RESULT_ROW:
        raise Error("Expected VDBE_RESULT_ROW")

    var row = vm.current_result_row()
    if row[0].to_int() != 7 or row[1].to_string() != "Record #7":
        raise Error("RowID seek result mismatch")

    var rc_done = vm.step()
    if rc_done != VDBE_RESULT_DONE:
        raise Error("Expected VDBE_RESULT_DONE")

    print("  Optimized RowID seek returned exact record: ID: 7, Name: Record #7")
    print("WhereScan Query Optimizer tests passed successfully!")


def main() raises:
    test_query_optimizer_rowid_seek()
