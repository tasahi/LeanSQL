""" SQLite AST to VDBE Bytecode Compiler and Execution Planner.

Corresponds to `sqlite/src/select.c`, `sqlite/src/insert.c`, `sqlite/src/update.c`,
`sqlite/src/delete.c`, and `sqlite/src/build.c`.

Compiles AST statement trees into executable VDBE programs.
"""

from src.core.types import *
from src.engine.row import Value, Row
from src.engine.schema import SchemaCatalog, TableDef, IndexDef, ColumnDef
from src.sql.parser import (
    ASTStatement,
    SelectStmt,
    InsertStmt,
    UpdateStmt,
    DeleteStmt,
    CreateTableStmt,
    CreateIndexStmt,
    DropIndexStmt,
    TransStmt,
    Expr,
    EXPR_LITERAL,
    EXPR_COLUMN,
    EXPR_BINARY,
    EXPR_UNARY,
    EXPR_FUNC,
    EXPR_CASE,
    EXPR_BETWEEN,
    EXPR_IN,
    EXPR_CAST,
    EXPR_STAR,
    STMT_SELECT,
    STMT_INSERT,
    STMT_UPDATE,
    STMT_DELETE,
    STMT_CREATE_TABLE,
    STMT_CREATE_INDEX,
    STMT_DROP_INDEX,
    STMT_TRANS,
)
from src.vdbe.opcode import *
from src.vdbe.vm import Vdbe
from src.storage.btree import MemBTree
from src.engine.functions import evaluate_scalar_func, sql_cast
from src.ext.json import sql_json_extract
from src.core.utf import nocase_compare


def eval_expr_row(
    expr: Expr,
    row: Row,
    col_names: List[String],
    alias_names: List[String] = List[String](),
    alias_exprs: List[Expr] = List[Expr](),
) -> Value:
    """ Directly evaluates an expression tree against a given row snapshot."""
    var k = expr.kind

    if k == EXPR_LITERAL:
        return expr.val.copy()

    elif k == EXPR_COLUMN:
        var name = expr.col_name
        # 1. Exact match in col_names (e.g. "u.id" or "id")
        for i in range(len(col_names)):
            if nocase_compare(col_names[i], name) == 0:
                if i < len(row):
                    return row[i].copy()

        # 2. Suffix match (e.g. name is "id", and col_names has "u.id" or "users.id")
        for i in range(len(col_names)):
            var c_item = col_names[i]
            var c_bytes = c_item.as_bytes()
            var dot_pos = -1
            for b in range(len(c_bytes)):
                if c_bytes[b] == 46: # '.'
                    dot_pos = b
                    break
            if dot_pos >= 0 and dot_pos + 1 < len(c_bytes):
                var sub_col = String()
                for b in range(dot_pos + 1, len(c_bytes)):
                    sub_col += chr(Int(c_bytes[b]))
                if nocase_compare(sub_col, name) == 0:
                    if i < len(row):
                        return row[i].copy()

        # 3. Strip prefix if col_names doesn't have table prefix (e.g. name is "users.id", col_names has "id")
        var dot_pos_name = -1
        var n_bytes = name.as_bytes()
        for b in range(len(n_bytes)):
            if n_bytes[b] == 46: # '.'
                dot_pos_name = b
                break
        if dot_pos_name >= 0 and dot_pos_name + 1 < len(n_bytes):
            var stripped_name = String()
            for b in range(dot_pos_name + 1, len(n_bytes)):
                stripped_name += chr(Int(n_bytes[b]))
            for i in range(len(col_names)):
                if nocase_compare(col_names[i], stripped_name) == 0:
                    if i < len(row):
                        return row[i].copy()

        # 4. Check aliases
        for a in range(len(alias_names)):
            if nocase_compare(alias_names[a], name) == 0:
                if a < len(alias_exprs):
                    return eval_expr_row(alias_exprs[a], row, col_names, alias_names, alias_exprs)
        return Value.of_null()

    elif k == EXPR_STAR:
        return Value.of_text("*")

    elif k == EXPR_FUNC:
        # Check if aggregate column is present in row
        for i in range(len(col_names)):
            if nocase_compare(col_names[i], expr.func_name) == 0:
                if i < len(row):
                    return row[i].copy()
        var args = List[Value]()
        for i in range(len(expr.args)):
            args.append(eval_expr_row(expr.args[i], row, col_names, alias_names, alias_exprs))
        return evaluate_scalar_func(expr.func_name, args)

    elif k == EXPR_CAST:
        if len(expr.args) > 0:
            var src = eval_expr_row(expr.args[0], row, col_names, alias_names, alias_exprs)
            return sql_cast(src, expr.col_name)
        return Value.of_null()

    elif k == EXPR_UNARY:
        if len(expr.args) > 0:
            var child = eval_expr_row(expr.args[0], row, col_names, alias_names, alias_exprs)
            if expr.op == "-":
                if child.type_tag == SQLITE_INTEGER:
                    return Value.of_int(-child.int_val)
                elif child.type_tag == SQLITE_FLOAT:
                    return Value.of_float(-child.float_val)
            elif expr.op == "NOT":
                return Value.of_int(Int64(1 if child.to_int() == 0 else 0))
        return Value.of_null()

    elif k == EXPR_BINARY:
        if len(expr.args) >= 2:
            var left = eval_expr_row(expr.args[0], row, col_names, alias_names, alias_exprs)
            var right = eval_expr_row(expr.args[1], row, col_names, alias_names, alias_exprs)
            var op = expr.op

            # NULL logic for IS / IS NOT
            if op == "IS":
                if left.is_null() and right.is_null():
                    return Value.of_int(Int64(1))
                elif left.is_null() or right.is_null():
                    return Value.of_int(Int64(0))
                return Value.of_int(Int64(1 if left.to_string() == right.to_string() else 0))
            elif op == "IS NOT":
                if left.is_null() and right.is_null():
                    return Value.of_int(Int64(0))
                elif left.is_null() or right.is_null():
                    return Value.of_int(Int64(1))
                return Value.of_int(Int64(1 if left.to_string() != right.to_string() else 0))

            # Three-valued logic: other operators return NULL if any operand is NULL
            if left.is_null() or right.is_null():
                return Value.of_null()

            if op == "+":
                if left.type_tag == SQLITE_FLOAT or right.type_tag == SQLITE_FLOAT:
                    return Value.of_float(left.to_float() + right.to_float())
                return Value.of_int(left.to_int() + right.to_int())
            elif op == "-":
                if left.type_tag == SQLITE_FLOAT or right.type_tag == SQLITE_FLOAT:
                    return Value.of_float(left.to_float() - right.to_float())
                return Value.of_int(left.to_int() - right.to_int())
            elif op == "*":
                if left.type_tag == SQLITE_FLOAT or right.type_tag == SQLITE_FLOAT:
                    return Value.of_float(left.to_float() * right.to_float())
                return Value.of_int(left.to_int() * right.to_int())
            elif op == "/":
                if left.type_tag == SQLITE_FLOAT or right.type_tag == SQLITE_FLOAT:
                    var denom = right.to_float()
                    if denom == 0.0:
                        return Value.of_null()
                    return Value.of_float(left.to_float() / denom)
                var idenom = right.to_int()
                if idenom == 0:
                    return Value.of_null()
                return Value.of_int(left.to_int() // idenom)
            elif op == "%":
                var idenom = right.to_int()
                if idenom == 0:
                    return Value.of_null()
                return Value.of_int(left.to_int() % idenom)
            elif op == "||":
                return Value.of_text(left.to_string() + right.to_string())
            elif op == "->":
                return sql_json_extract(left.to_string(), right.to_string(), False)
            elif op == "->>":
                return sql_json_extract(left.to_string(), right.to_string(), True)
            elif op == "=":
                if (left.type_tag == SQLITE_INTEGER or left.type_tag == SQLITE_FLOAT) and (right.type_tag == SQLITE_INTEGER or right.type_tag == SQLITE_FLOAT):
                    return Value.of_int(Int64(1 if left.to_float() == right.to_float() else 0))
                return Value.of_int(Int64(1 if left.to_string() == right.to_string() else 0))
            elif op == "!=":
                if (left.type_tag == SQLITE_INTEGER or left.type_tag == SQLITE_FLOAT) and (right.type_tag == SQLITE_INTEGER or right.type_tag == SQLITE_FLOAT):
                    return Value.of_int(Int64(1 if left.to_float() != right.to_float() else 0))
                return Value.of_int(Int64(1 if left.to_string() != right.to_string() else 0))
            elif op == "<":
                if left.type_tag == SQLITE_TEXT and right.type_tag == SQLITE_TEXT:
                    return Value.of_int(Int64(1 if left.text_val < right.text_val else 0))
                return Value.of_int(Int64(1 if left.to_float() < right.to_float() else 0))
            elif op == "<=":
                if left.type_tag == SQLITE_TEXT and right.type_tag == SQLITE_TEXT:
                    return Value.of_int(Int64(1 if left.text_val <= right.text_val else 0))
                return Value.of_int(Int64(1 if left.to_float() <= right.to_float() else 0))
            elif op == ">":
                if left.type_tag == SQLITE_TEXT and right.type_tag == SQLITE_TEXT:
                    return Value.of_int(Int64(1 if left.text_val > right.text_val else 0))
                return Value.of_int(Int64(1 if left.to_float() > right.to_float() else 0))
            elif op == ">=":
                if left.type_tag == SQLITE_TEXT and right.type_tag == SQLITE_TEXT:
                    return Value.of_int(Int64(1 if left.text_val >= right.text_val else 0))
                return Value.of_int(Int64(1 if left.to_float() >= right.to_float() else 0))
            elif op == "AND":
                var l_bool = left.to_int() != 0
                var r_bool = right.to_int() != 0
                return Value.of_int(Int64(1 if l_bool and r_bool else 0))
            elif op == "OR":
                var l_bool = left.to_int() != 0
                var r_bool = right.to_int() != 0
                return Value.of_int(Int64(1 if l_bool or r_bool else 0))
            elif op == "LIKE":
                var pat = right.to_string()
                var text = left.to_string()
                if pat.byte_length() >= 2 and pat.as_bytes()[0] == 37 and pat.as_bytes()[pat.byte_length() - 1] == 37:
                    var sub = String()
                    var b = pat.as_bytes()
                    for i in range(1, len(b) - 1):
                        sub += chr(Int(b[i]))
                    var instr_args = List[Value]()
                    instr_args.append(Value.of_text(text))
                    instr_args.append(Value.of_text(sub))
                    var matched = False
                    if sub.byte_length() == 0 or evaluate_scalar_func("INSTR", instr_args).to_int() > 0:
                        matched = True
                    return Value.of_int(Int64(1 if matched else 0))
                return Value.of_int(Int64(1 if text == pat else 0))

    elif k == EXPR_BETWEEN:
        if len(expr.args) >= 3:
            var target = eval_expr_row(expr.args[0], row, col_names, alias_names, alias_exprs)
            var low = eval_expr_row(expr.args[1], row, col_names, alias_names, alias_exprs)
            var high = eval_expr_row(expr.args[2], row, col_names, alias_names, alias_exprs)
            if target.is_null() or low.is_null() or high.is_null():
                return Value.of_null()
            var t_val = target.to_float()
            var in_range = t_val >= low.to_float() and t_val <= high.to_float()
            return Value.of_int(Int64(1 if in_range else 0))

    elif k == EXPR_IN:
        if len(expr.args) >= 1:
            var target = eval_expr_row(expr.args[0], row, col_names, alias_names, alias_exprs)
            var has_null = False
            var found = False
            for i in range(1, len(expr.args)):
                var cand = eval_expr_row(expr.args[i], row, col_names, alias_names, alias_exprs)
                if cand.is_null():
                    has_null = True
                elif not target.is_null() and target.to_string() == cand.to_string():
                    found = True
                    break
            
            if expr.op == "NOT IN":
                if target.is_null() or (not found and has_null):
                    return Value.of_null()
                return Value.of_int(Int64(0 if found else 1))
            else:
                if found:
                    return Value.of_int(Int64(1))
                if target.is_null() or has_null:
                    return Value.of_null()
                return Value.of_int(Int64(0))

    elif k == EXPR_CASE:
        var n_args = len(expr.args)
        var i = 0
        while i + 1 < n_args:
            var cond = eval_expr_row(expr.args[i], row, col_names, alias_names, alias_exprs)
            if not cond.is_null() and cond.to_int() != 0:
                return eval_expr_row(expr.args[i + 1], row, col_names, alias_names, alias_exprs)
            i += 2
        if i < n_args:
            return eval_expr_row(expr.args[i], row, col_names, alias_names, alias_exprs)
        return Value.of_null()

    return Value.of_null()
