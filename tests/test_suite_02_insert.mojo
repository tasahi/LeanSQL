from tests.harness import TestHarness
from src.connection import connect


def run_insert_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 2: INSERT Statements (insert.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    # 1. insert-1.1: Basic table creation and insert
    cur.execute("CREATE TABLE t2(id INTEGER PRIMARY KEY, a INT, b TEXT, c REAL)")
    cur.execute("INSERT INTO t2 VALUES(1, 100, 'first', 1.5)")
    h.assert_equal_int("insert-1.1", con.total_changes(), 1, "Total changes is 1 after first insert")

    # 2. insert-1.2: Verify row values inserted
    cur.execute("SELECT a, b, c FROM t2 WHERE id = 1")
    var r = cur.fetchone()
    h.assert_true("insert-1.2", r.__bool__(), "Row exists")
    h.assert_equal_int("insert-1.2a", r.value().get_int(0), 100, "Integer column matches")
    h.assert_equal("insert-1.2b", r.value().get_string(1), "first", "Text column matches")
    h.assert_equal_float("insert-1.2c", r.value().get_float(2), 1.5, 0.001, "Real column matches")

    # 3. insert-1.3: Insert with explicit column list
    cur.execute("INSERT INTO t2(b, a, id) VALUES('second', 200, 2)")
    cur.execute("SELECT a, b, c FROM t2 WHERE id = 2")
    r = cur.fetchone()
    h.assert_equal_int("insert-1.3a", r.value().get_int(0), 200, "Column re-ordered insert matches")
    h.assert_true("insert-1.3b", r.value().is_null(2), "Omitted column defaults to NULL")

    # 4. insert-1.4: Auto-increment rowid on PRIMARY KEY
    cur.execute("INSERT INTO t2(a, b) VALUES(300, 'third')")
    cur.execute("SELECT id FROM t2 WHERE a = 300")
    r = cur.fetchone()
    h.assert_equal_int("insert-1.4", r.value().get_int(0), 3, "Auto-assigned rowid is 3")

    # 5. last_insert_rowid()
    h.assert_equal_int("insert-1.5", con.last_insert_rowid(), 3, "last_insert_rowid is 3")

    # 6. insert-1.6: Multi-row insert via multiple statements
    cur.execute("INSERT INTO t2(a, b) VALUES(400, 'fourth')")
    cur.execute("INSERT INTO t2(a, b) VALUES(500, 'fifth')")
    cur.execute("SELECT COUNT(*) FROM t2")
    r = cur.fetchone()
    h.assert_equal_int("insert-1.6", r.value().get_int(0), 5, "Count after inserts is 5")

    # 7. insert-1.7: Insert with NULL value
    cur.execute("INSERT INTO t2(id, a, b, c) VALUES(6, NULL, NULL, NULL)")
    cur.execute("SELECT a, b, c FROM t2 WHERE id = 6")
    r = cur.fetchone()
    h.assert_true("insert-1.7a", r.value().is_null(0), "a is NULL")
    h.assert_true("insert-1.7b", r.value().is_null(1), "b is NULL")
    h.assert_true("insert-1.7c", r.value().is_null(2), "c is NULL")

    # 8. insert-1.8: Insert with DEFAULT value
    cur.execute("CREATE TABLE t2_def(id INT, status TEXT DEFAULT 'active')")
    cur.execute("INSERT INTO t2_def(id) VALUES(1)")
    cur.execute("SELECT status FROM t2_def WHERE id = 1")
    r = cur.fetchone()
    h.assert_equal("insert-1.8", r.value().get_string(0), "active", "Default value used")

    # 9. insert-1.9: INSERT into table from SELECT
    cur.execute("CREATE TABLE t2_copy(id INT, a INT)")
    cur.execute("INSERT INTO t2_copy SELECT id, a FROM t2 WHERE id <= 2")
    cur.execute("SELECT COUNT(*) FROM t2_copy")
    r = cur.fetchone()
    h.assert_equal_int("insert-1.9", r.value().get_int(0), 2, "INSERT INTO ... SELECT inserted 2 rows")

    # 10. insert-1.10: Total changes tracking
    cur.execute("INSERT INTO t2(a, b) VALUES(600, 'sixth')")
    h.assert_equal_int("insert-1.10", con.changes(), 1, "con.changes() is 1 for latest insert")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 02 - INSERT Statements")
    run_insert_tests(h)
    h.summary()
