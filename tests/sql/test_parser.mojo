from src.core.types import *
from src.engine.row import Value
from src.storage.record import encode_record
from src.storage.btree import MemBTree
from src.sql.tokenizer import tokenize_sql
from src.sql.parser import parse_select, compile_select_to_vdbe
from src.vdbe import VDBE_RESULT_ROW, VDBE_RESULT_DONE


def test_sql_parser_and_code_generation() raises:
    print("=== Testing SQL Parser & End-to-End Query Execution ===")
    
    # 1. Populate a B-Tree table with mock user records
    var btree = MemBTree()
    var u1_vals = List[Value]()
    u1_vals.append(Value.of_int(1))
    u1_vals.append(Value.of_text("Alice"))
    btree.insert(1, encode_record(u1_vals))

    var u2_vals = List[Value]()
    u2_vals.append(Value.of_int(2))
    u2_vals.append(Value.of_text("Bob"))
    btree.insert(2, encode_record(u2_vals))

    # 2. Tokenize and parse SQL query: `SELECT id, name FROM users`
    var sql = "SELECT id, name FROM users"
    var tokens = tokenize_sql(sql)
    var ast = parse_select(tokens)

    if ast.table_name != "users":
        raise Error("Expected table name 'users', got: " + ast.table_name)
    if len(ast.columns) != 2 or ast.columns[0] != "id" or ast.columns[1] != "name":
        raise Error("Columns parsing mismatch")

    print("  SQL successfully parsed to AST node!")

    # 3. Generate VDBE bytecode program
    var vm = compile_select_to_vdbe(ast, 0)
    _ = vm.attach_btree(btree)

    # 4. Execute VDBE program and collect rows
    var results = List[List[Value]]()
    while True:
        var rc = vm.step()
        if rc == VDBE_RESULT_ROW:
            results.append(vm.current_result_row())
        elif rc == VDBE_RESULT_DONE:
            break
        else:
            raise Error("VDBE execution error: " + String(rc))

    if len(results) != 2:
        raise Error("Expected 2 query result rows, got: " + String(len(results)))

    if results[0][0].to_int() != 1 or results[0][1].to_string() != "Alice":
        raise Error("Row 0 projection mismatch")
    if results[1][0].to_int() != 2 or results[1][1].to_string() != "Bob":
        raise Error("Row 1 projection mismatch")

    print("  Query results executed directly from SQL text:")
    print("    [1] ID: 1, Name: Alice")
    print("    [2] ID: 2, Name: Bob")
    print("End-to-End SQL Parser & VDBE query test passed successfully!")


def main() raises:
    test_sql_parser_and_code_generation()
