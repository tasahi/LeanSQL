from tests.harness import TestHarness
from src.engine.connection import connect


def run_select_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 1: SELECT Statements (select1.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE t1(f1 INT, f2 INT, name TEXT)")
    cur.execute("INSERT INTO t1 VALUES(10, 20, 'alpha')")
    cur.execute("INSERT INTO t1 VALUES(30, 40, 'beta')")
    cur.execute("INSERT INTO t1 VALUES(50, 60, 'gamma')")

    # 1. select1-1.1: Projection of single column
    cur.execute("SELECT f1 FROM t1 WHERE name = 'alpha'")
    var r = cur.fetchone()
    h.assert_true("select1-1.1", r.__bool__(), "Fetch single column row")
    h.assert_equal_int("select1-1.1b", r.value().get_int(0), 10, "f1 value matches 10")

    # 2. select1-1.2: Projection of multiple columns in order
    cur.execute("SELECT f2, f1, name FROM t1 WHERE f1 = 30")
    r = cur.fetchone()
    h.assert_equal_int("select1-1.2a", r.value().get_int(0), 40, "First projected column is f2")
    h.assert_equal_int("select1-1.2b", r.value().get_int(1), 30, "Second projected column is f1")
    h.assert_equal("select1-1.2c", r.value().get_string(2), "beta", "Third projected column is name")

    # 3. select1-1.3: Literal value projection
    cur.execute("SELECT 100, 'hello'")
    r = cur.fetchone()
    h.assert_equal_int("select1-1.3a", r.value().get_int(0), 100, "Literal integer projection")
    h.assert_equal("select1-1.3b", r.value().get_string(1), "hello", "Literal string projection")

    # 4. select1-1.4: ORDER BY ASC
    cur.execute("SELECT f1 FROM t1 ORDER BY f1 ASC")
    var rows = cur.fetchall()
    h.assert_equal_int("select1-1.4a", len(rows), 3, "Rows count is 3")
    h.assert_equal_int("select1-1.4b", rows[0].get_int(0), 10, "First row is 10")
    h.assert_equal_int("select1-1.4c", rows[2].get_int(0), 50, "Third row is 50")

    # 5. select1-1.5: ORDER BY DESC
    cur.execute("SELECT f1 FROM t1 ORDER BY f1 DESC")
    rows = cur.fetchall()
    h.assert_equal_int("select1-1.5", rows[0].get_int(0), 50, "First row DESC is 50")

    # 6. select1-1.6: LIMIT clause
    cur.execute("SELECT f1 FROM t1 ORDER BY f1 ASC LIMIT 2")
    rows = cur.fetchall()
    h.assert_equal_int("select1-1.6", len(rows), 2, "LIMIT 2 returns 2 rows")

    # 7. select1-1.7: LIMIT with OFFSET
    cur.execute("SELECT f1 FROM t1 ORDER BY f1 ASC LIMIT 1 OFFSET 1")
    rows = cur.fetchall()
    h.assert_equal_int("select1-1.7a", len(rows), 1, "LIMIT 1 OFFSET 1 returns 1 row")
    h.assert_equal_int("select1-1.7b", rows[0].get_int(0), 30, "Offset skips 10 and yields 30")

    # 8. select1-1.8: Column aliasing
    cur.execute("SELECT f1 AS alias_col FROM t1 WHERE alias_col = 10")
    rows = cur.fetchall()
    h.assert_equal_int("select1-1.8", len(rows), 1, "Alias in query matches")

    # 9. select1-1.9: DISTINCT values
    cur.execute("INSERT INTO t1 VALUES(10, 99, 'delta')")
    cur.execute("SELECT DISTINCT f1 FROM t1 ORDER BY f1")
    rows = cur.fetchall()
    h.assert_equal_int("select1-1.9", len(rows), 3, "DISTINCT collapses duplicated 10")

    # 10. select1-1.10: Empty result set
    cur.execute("SELECT * FROM t1 WHERE f1 = 99999")
    r = cur.fetchone()
    h.assert_true("select1-1.10", not r.__bool__(), "Non-existent row returns empty")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 01 - SELECT Statements")
    run_select_tests(h)
    h.summary()
