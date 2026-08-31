from tests.harness import TestHarness
from src.engine.connection import connect


def run_update_delete_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 3: UPDATE & DELETE (update.test, delete.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE t3(id INTEGER PRIMARY KEY, val INT, tag TEXT)")
    cur.execute("INSERT INTO t3 VALUES(1, 10, 'A')")
    cur.execute("INSERT INTO t3 VALUES(2, 20, 'B')")
    cur.execute("INSERT INTO t3 VALUES(3, 30, 'A')")
    cur.execute("INSERT INTO t3 VALUES(4, 40, 'C')")
    cur.execute("INSERT INTO t3 VALUES(5, 50, 'B')")

    # 1. update-1.1: Single row update
    cur.execute("UPDATE t3 SET val = 15 WHERE id = 1")
    h.assert_equal_int("update-1.1a", con.changes(), 1, "Single row updated")
    cur.execute("SELECT val FROM t3 WHERE id = 1")
    var r = cur.fetchone()
    h.assert_equal_int("update-1.1b", r.value().get_int(0), 15, "Value updated to 15")

    # 2. update-1.2: Multi-row update with WHERE clause
    cur.execute("UPDATE t3 SET val = val + 5 WHERE tag = 'A'")
    h.assert_equal_int("update-1.2a", con.changes(), 2, "Two rows updated with tag='A'")
    cur.execute("SELECT val FROM t3 WHERE id = 1")
    r = cur.fetchone()
    h.assert_equal_int("update-1.2b", r.value().get_int(0), 20, "id=1 updated to 20")
    cur.execute("SELECT val FROM t3 WHERE id = 3")
    r = cur.fetchone()
    h.assert_equal_int("update-1.2c", r.value().get_int(0), 35, "id=3 updated to 35")

    # 3. update-1.3: Update multiple columns simultaneously
    cur.execute("UPDATE t3 SET val = 99, tag = 'Z' WHERE id = 4")
    cur.execute("SELECT val, tag FROM t3 WHERE id = 4")
    r = cur.fetchone()
    h.assert_equal_int("update-1.3a", r.value().get_int(0), 99, "val updated to 99")
    h.assert_equal("update-1.3b", r.value().get_string(1), "Z", "tag updated to Z")

    # 4. update-1.4: Update with non-matching WHERE clause (0 changes)
    cur.execute("UPDATE t3 SET val = 0 WHERE id = 999")
    h.assert_equal_int("update-1.4", con.changes(), 0, "No rows updated for missing id")

    # 5. update-1.5: Update setting column to NULL
    cur.execute("UPDATE t3 SET tag = NULL WHERE id = 2")
    cur.execute("SELECT tag FROM t3 WHERE id = 2")
    r = cur.fetchone()
    h.assert_true("update-1.5", r.value().is_null(0), "tag set to NULL")

    # 6. delete-1.1: Single row delete by primary key
    cur.execute("DELETE FROM t3 WHERE id = 5")
    h.assert_equal_int("delete-1.1a", con.changes(), 1, "1 row deleted")
    cur.execute("SELECT COUNT(*) FROM t3 WHERE id = 5")
    r = cur.fetchone()
    h.assert_equal_int("delete-1.1b", r.value().get_int(0), 0, "Deleted row not found")

    # 7. delete-1.2: Multi-row delete with condition
    cur.execute("DELETE FROM t3 WHERE tag = 'A' OR tag = 'Z'")
    h.assert_equal_int("delete-1.2a", con.changes(), 3, "3 rows deleted (id=1,3,4)")
    cur.execute("SELECT COUNT(*) FROM t3")
    r = cur.fetchone()
    h.assert_equal_int("delete-1.2b", r.value().get_int(0), 1, "Only id=2 remains")

    # 8. delete-1.3: Delete with non-matching WHERE clause
    cur.execute("DELETE FROM t3 WHERE id = 100")
    h.assert_equal_int("delete-1.3", con.changes(), 0, "0 rows deleted for non-matching where")

    # 9. delete-1.4: Delete all rows (Truncate table)
    cur.execute("DELETE FROM t3")
    cur.execute("SELECT COUNT(*) FROM t3")
    r = cur.fetchone()
    h.assert_equal_int("delete-1.4", r.value().get_int(0), 0, "Table is completely empty")

    # 10. delete-1.5: Delete on empty table
    cur.execute("DELETE FROM t3")
    h.assert_equal_int("delete-1.5", con.changes(), 0, "Deleting from empty table changes 0 rows")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 03 - UPDATE & DELETE Statements")
    run_update_delete_tests(h)
    h.summary()
