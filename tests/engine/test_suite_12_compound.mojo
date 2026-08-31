from tests.harness import TestHarness
from src.engine.connection import connect


def run_compound_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 12: Compound Queries (union.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE t1(x INT, y TEXT)")
    cur.execute("CREATE TABLE t2(x INT, y TEXT)")

    cur.execute("INSERT INTO t1 VALUES(1, 'A')")
    cur.execute("INSERT INTO t1 VALUES(2, 'B')")
    cur.execute("INSERT INTO t1 VALUES(3, 'C')")

    cur.execute("INSERT INTO t2 VALUES(2, 'B')")
    cur.execute("INSERT INTO t2 VALUES(3, 'C')")
    cur.execute("INSERT INTO t2 VALUES(4, 'D')")

    # 1. union-1.1: UNION (distinct combination)
    cur.execute("SELECT x, y FROM t1 UNION SELECT x, y FROM t2")
    var rows = cur.fetchall()
    h.assert_equal_int("union-1.1", len(rows), 4, "UNION returned 4 distinct rows (1, 2, 3, 4)")

    # 2. union-1.2: UNION ALL (all rows preserved)
    cur.execute("SELECT x, y FROM t1 UNION ALL SELECT x, y FROM t2")
    rows = cur.fetchall()
    h.assert_equal_int("union-1.2", len(rows), 6, "UNION ALL returned 6 total rows (3 + 3)")

    # 3. union-1.3: INTERSECT (common rows)
    cur.execute("SELECT x, y FROM t1 INTERSECT SELECT x, y FROM t2")
    rows = cur.fetchall()
    h.assert_equal_int("union-1.3a", Int64(len(rows)), 2, "INTERSECT returned 2 common rows (2, 3)")
    h.assert_equal_int("union-1.3b", rows[0].get_int(0), 2, "First common is 2")
    h.assert_equal_int("union-1.3c", rows[1].get_int(0), 3, "Second common is 3")

    # 4. union-1.4: EXCEPT (set difference)
    cur.execute("SELECT * FROM t1 EXCEPT SELECT * FROM t2 ORDER BY x")
    rows = cur.fetchall()
    h.assert_equal_int("union-1.4a", Int64(len(rows)), 1, "EXCEPT returned 1 row present in t1 but not t2")
    h.assert_equal_int("union-1.4b", rows[0].get_int(0), 1, "Remaining row is 1")
    h.assert_equal("union-1.4c", rows[0].get_string(1), "A", "Remaining row y is 'A'")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 12 - Compound Queries")
    run_compound_tests(h)
    h.summary()
