from tests.harness import TestHarness
from src.interop.c_api import (
    sqlite3_libversion,
    sqlite3_sourceid,
    sqlite3_libversion_number,
    CDatabaseContext,
    CStatementContext,
    SQLITE_OK,
    SQLITE_ROW,
    SQLITE_DONE,
)


def run_c_abi_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 20: Complete C-ABI Export (c_api.mojo)   ===")
    print("=======================================================")

    # 1. Library version string and version number
    var ver = sqlite3_libversion()
    h.assert_true("cabi-1.1a", "3.45.0" in ver, "sqlite3_libversion returns valid version string")
    h.assert_equal_int("cabi-1.1b", sqlite3_libversion_number(), 3045000, "sqlite3_libversion_number is 3045000")

    # 2. CDatabaseContext initialization
    var db = CDatabaseContext(":memory:")
    h.assert_equal_int("cabi-1.2", db.err_code, SQLITE_OK, "CDatabaseContext initialized with SQLITE_OK")

    # 3. DDL Execution: CREATE TABLE
    var stmt_create = db.prepare("CREATE TABLE metrics (id INT, tag TEXT, val REAL)")
    var rc_step = stmt_create.step()
    h.assert_equal_int("cabi-1.3", rc_step, SQLITE_DONE, "step on DDL returns SQLITE_DONE")

    # 4. DML Execution: INSERT INTO
    var stmt_ins1 = db.prepare("INSERT INTO metrics VALUES (10, 'cpu', 45.5)")
    _ = stmt_ins1.step()

    var stmt_ins2 = db.prepare("INSERT INTO metrics VALUES (20, 'mem', 82.3)")
    _ = stmt_ins2.step()

    h.assert_equal_int("cabi-1.4a", db.changes(), 1, "db.changes returns 1")
    h.assert_equal_int("cabi-1.4b", Int(db.last_insert_rowid()), 2, "db.last_insert_rowid returns 2")

    # 5. Query Execution: SELECT * FROM metrics ORDER BY id
    var stmt_sel = db.prepare("SELECT id, tag, val FROM metrics ORDER BY id")
    h.assert_equal_int("cabi-1.5a", stmt_sel.column_count(), 3, "stmt.column_count is 3")

    # Row 1
    var rc_r1 = stmt_sel.step()
    h.assert_equal_int("cabi-1.5b", rc_r1, SQLITE_ROW, "First step returns SQLITE_ROW")
    h.assert_equal_int("cabi-1.5c", Int(stmt_sel.column_int64(0)), 10, "Row 1 id is 10")
    h.assert_equal("cabi-1.5d", stmt_sel.column_text(1), "cpu", "Row 1 tag is 'cpu'")
    h.assert_equal_float("cabi-1.5e", stmt_sel.column_double(2), 45.5, 0.001, "Row 1 val is 45.5")

    # Row 2
    var rc_r2 = stmt_sel.step()
    h.assert_equal_int("cabi-1.5f", rc_r2, SQLITE_ROW, "Second step returns SQLITE_ROW")
    h.assert_equal_int("cabi-1.5g", Int(stmt_sel.column_int64(0)), 20, "Row 2 id is 20")
    h.assert_equal("cabi-1.5h", stmt_sel.column_text(1), "mem", "Row 2 tag is 'mem'")
    h.assert_equal_float("cabi-1.5i", stmt_sel.column_double(2), 82.3, 0.001, "Row 2 val is 82.3")

    # End of results
    var rc_end = stmt_sel.step()
    h.assert_equal_int("cabi-1.5j", rc_end, SQLITE_DONE, "Final step returns SQLITE_DONE")

    # 6. Reset statement
    stmt_sel.reset()
    var rc_reset_step = stmt_sel.step()
    h.assert_equal_int("cabi-1.6", rc_reset_step, SQLITE_ROW, "Step after reset yields first row again")


def main() raises:
    var h = TestHarness("Suite 20: C-ABI Export")
    run_c_abi_tests(h)
    h.summary()
