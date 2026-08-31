from src.core.types import *
from src.sql.tokenizer import tokenize_sql
from src.sql.parser import parse_select
from src.sql.uast import UASTPool, UAST_SQL_SELECT, UAST_SQL_FROM, UAST_SQL_WHERE, UAST_NAME, UAST_LITERAL_NUM


def test_unimo_uast_compatibility() raises:
    print("=== Testing Unimo Universal AST Compatibility for LeanSQL ===")
    
    var sql = "SELECT id, name FROM users WHERE id = 42"
    var tokens = tokenize_sql(sql)
    var ast = parse_select(tokens)

    # Convert to Unimo UAST
    var pool = UASTPool()
    var root_idx = ast.to_uast(pool)

    var root_node = pool.get(root_idx)
    if root_node.kind != UAST_SQL_SELECT:
        raise Error("Expected root node kind UAST_SQL_SELECT (100), got: " + String(root_node.kind))

    if root_node.num_children() != 4:
        raise Error("Expected 4 children (id, name, from, where), got: " + String(root_node.num_children()))

    # Child 0: 'id' (UAST_NAME)
    var c0 = pool.get(root_node.children[0])
    if c0.kind != UAST_NAME or c0.value != "id":
        raise Error("Child 0 mismatch: expected UAST_NAME 'id'")

    # Child 1: 'name' (UAST_NAME)
    var c1 = pool.get(root_node.children[1])
    if c1.kind != UAST_NAME or c1.value != "name":
        raise Error("Child 1 mismatch: expected UAST_NAME 'name'")

    # Child 2: 'users' (UAST_SQL_FROM)
    var c2 = pool.get(root_node.children[2])
    if c2.kind != UAST_SQL_FROM or c2.value != "users":
        raise Error("Child 2 mismatch: expected UAST_SQL_FROM 'users'")

    # Child 3: where clause (UAST_SQL_WHERE)
    var c3 = pool.get(root_node.children[3])
    if c3.kind != UAST_SQL_WHERE:
        raise Error("Child 3 mismatch: expected UAST_SQL_WHERE")
    if c3.num_children() != 2:
        raise Error("Where clause should have 2 operands")

    var w_left = pool.get(c3.children[0])
    var w_right = pool.get(c3.children[1])
    if w_left.kind != UAST_NAME or w_left.value != "id":
        raise Error("Where left operand mismatch")
    if w_right.kind != UAST_LITERAL_NUM or w_right.value != "42":
        raise Error("Where right operand mismatch")

    print("  Root node kind: UAST_SQL_SELECT (" + String(root_node.kind) + ")")
    print("  Columns: " + c0.value + " (" + String(c0.kind) + "), " + c1.value + " (" + String(c1.kind) + ")")
    print("  From: " + c2.value + " (" + String(c2.kind) + ")")
    print("  Where: " + w_left.value + " = " + w_right.value)
    print("Unimo Universal AST compatibility test passed successfully!")


def main() raises:
    test_unimo_uast_compatibility()
