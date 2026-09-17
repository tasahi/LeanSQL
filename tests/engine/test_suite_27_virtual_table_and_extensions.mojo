""" Test Suite 27: Virtual Table Interface, Dynamic Library Loader, and User Functions.

Verifies:
1. Dynamic function registration (register_function) and execution in SQL (SELECT, WHERE).
2. Dynamic library loading (load_extension) with platform shared libraries.
3. Virtual table creation (CREATE VIRTUAL TABLE ... USING ...).
4. Custom virtual table module registration (register_module).
5. Virtual table DML (INSERT, SELECT, WHERE, DELETE).
"""

from tests.harness import TestHarness
from src.core.types import *
from src.engine.row import Value, Row
from src.engine.connection import Connection, connect
from src.engine.vtab import VirtualTableModule, VirtualTable, VirtualTableCursor, DynamicLibrary


def custom_double(args: List[Value]) -> Value:
    if len(args) > 0 and not args[0].is_null():
        return Value.of_int(args[0].to_int() * 2)
    return Value.of_null()


def custom_concat_dash(args: List[Value]) -> Value:
    if len(args) >= 2 and not args[0].is_null() and not args[1].is_null():
        return Value.of_text(args[0].to_string() + "-" + args[1].to_string())
    return Value.of_null()


def run_virtual_table_and_extensions_tests(mut h: TestHarness) raises:
    print("\n=======================================================================")
    print("=== Suite 27: Virtual Tables & Dynamic Extension Interface          ===")
    print("=======================================================================")

    # -------------------------------------------------------------
    # 1. Custom User-Defined Scalar Functions
    # -------------------------------------------------------------
    var conn = connect(":memory:")
    conn.register_function("double_val", custom_double)
    conn.register_function("concat_dash", custom_concat_dash)

    var cur1 = conn.execute("SELECT double_val(21) AS res")
    var row1 = cur1.fetchone()
    h.assert_true("vtab-1.1a", row1.__bool__(), "Custom scalar function returned row")
    h.assert_equal_int("vtab-1.1b", row1.value().get_int(0), 42, "double_val(21) = 42")

    var cur2 = conn.execute("SELECT concat_dash('Mojo', 'LeanSQL') AS res")
    var row2 = cur2.fetchone()
    h.assert_true("vtab-1.2a", row2.__bool__(), "Two-argument custom function returned row")
    h.assert_equal("vtab-1.2b", row2.value().get_string(0), "Mojo-LeanSQL", "concat_dash('Mojo', 'LeanSQL') matches")

    # Test custom function in table query
    _ = conn.execute("CREATE TABLE numbers (id INTEGER, val INTEGER)")
    _ = conn.execute("INSERT INTO numbers VALUES (1, 10)")
    _ = conn.execute("INSERT INTO numbers VALUES (2, 25)")
    _ = conn.execute("INSERT INTO numbers VALUES (3, 50)")

    var cur3 = conn.execute("SELECT id, double_val(val) FROM numbers WHERE double_val(val) > 40 ORDER BY id")
    var rows3 = cur3.fetchall()
    h.assert_equal_int("vtab-1.3a", len(rows3), 2, "Custom function in WHERE and SELECT returned 2 rows")
    h.assert_equal_int("vtab-1.3b", rows3[0].get_int(1), 50, "First doubled val is 50")
    h.assert_equal_int("vtab-1.3c", rows3[1].get_int(1), 100, "Second doubled val is 100")

    # -------------------------------------------------------------
    # 2. Dynamic Library Loader (load_extension)
    # -------------------------------------------------------------
    var loaded_lib = False
    try:
        conn.load_extension("libc.so.6")
        loaded_lib = True
    except:
        loaded_lib = False
    h.assert_true("vtab-2.1", loaded_lib, "load_extension successfully loaded libc.so.6")
    h.assert_equal_int("vtab-2.2", len(conn.loaded_extensions), 1, "Connection tracks loaded extension handle")

    # -------------------------------------------------------------
    # 3. Virtual Table Definition & Module Interface
    # -------------------------------------------------------------
    # Register custom module
    var vmod = VirtualTableModule("temp_series")
    conn.register_module("temp_series", vmod)

    _ = conn.execute("CREATE VIRTUAL TABLE series_data USING temp_series(id INT, label TEXT, score REAL)")
    var tbl_opt = conn.schema.find_table("series_data")
    h.assert_true("vtab-3.1a", tbl_opt.__bool__(), "Virtual table registered in schema")
    var tbl_def = tbl_opt.value()
    h.assert_true("vtab-3.1b", tbl_def.is_virtual, "Table marked as virtual")
    h.assert_equal("vtab-3.1c", tbl_def.virtual_module, "temp_series", "Virtual module name matches")
    h.assert_equal_int("vtab-3.1d", len(tbl_def.columns), 3, "3 columns declared in virtual table")

    # -------------------------------------------------------------
    # 4. Virtual Table Insert & Mutation
    # -------------------------------------------------------------
    _ = conn.execute("INSERT INTO series_data VALUES (101, 'alpha', 88.5)")
    _ = conn.execute("INSERT INTO series_data VALUES (102, 'beta', 92.0)")
    _ = conn.execute("INSERT INTO series_data VALUES (103, 'gamma', 75.2)")

    var cur_v1 = conn.execute("SELECT * FROM series_data")
    var rows_v1 = cur_v1.fetchall()
    h.assert_equal_int("vtab-4.1a", len(rows_v1), 3, "Virtual table contains 3 inserted rows")
    h.assert_equal_int("vtab-4.1b", rows_v1[0].get_int(0), 101, "Row 1 id is 101")
    h.assert_equal("vtab-4.1c", rows_v1[0].get_string(1), "alpha", "Row 1 label is 'alpha'")
    h.assert_equal("vtab-4.1d", rows_v1[1].get_string(1), "beta", "Row 2 label is 'beta'")

    # -------------------------------------------------------------
    # 5. Virtual Table Querying with WHERE, Projections, ORDER BY
    # -------------------------------------------------------------
    var cur_v2 = conn.execute("SELECT label, score FROM series_data WHERE score >= 80.0 ORDER BY score DESC")
    var rows_v2 = cur_v2.fetchall()
    h.assert_equal_int("vtab-5.1a", len(rows_v2), 2, "Filtered query returned 2 rows")
    h.assert_equal("vtab-5.1b", rows_v2[0].get_string(0), "beta", "Top score label is 'beta'")
    h.assert_equal("vtab-5.1c", rows_v2[1].get_string(0), "alpha", "Second score label is 'alpha'")

    # -------------------------------------------------------------
    # 6. Virtual Table DELETE
    # -------------------------------------------------------------
    _ = conn.execute("DELETE FROM series_data WHERE label = 'alpha'")
    var cur_v3 = conn.execute("SELECT * FROM series_data")
    var rows_v3 = cur_v3.fetchall()
    h.assert_equal_int("vtab-6.1a", len(rows_v3), 2, "1 row deleted, 2 remaining")
    h.assert_equal("vtab-6.1b", rows_v3[0].get_string(1), "beta", "Remaining row 1 is 'beta'")
    h.assert_equal("vtab-6.1c", rows_v3[1].get_string(1), "gamma", "Remaining row 2 is 'gamma'")
