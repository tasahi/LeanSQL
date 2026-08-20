from tests.harness import TestHarness
from src.connection import connect


def run_aggregate_func_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 9: Aggregate Functions (aggerror.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE t9(id INT, category TEXT, amount REAL)")
    cur.execute("INSERT INTO t9 VALUES(1, 'tech', 100.0)")
    cur.execute("INSERT INTO t9 VALUES(2, 'tech', 200.0)")
    cur.execute("INSERT INTO t9 VALUES(3, 'food', 50.0)")
    cur.execute("INSERT INTO t9 VALUES(4, 'food', 150.0)")
    cur.execute("INSERT INTO t9 VALUES(5, 'other', NULL)")

    # 1. agg-1.1: COUNT(*) vs COUNT(column)
    cur.execute("SELECT COUNT(*), COUNT(amount) FROM t9")
    var r = cur.fetchone()
    h.assert_equal_int("agg-1.1a", r.value().get_int(0), 5, "COUNT(*) is 5")
    h.assert_equal_int("agg-1.1b", r.value().get_int(1), 4, "COUNT(amount) excludes NULL and is 4")

    # 2. agg-1.2: SUM() and TOTAL()
    cur.execute("SELECT SUM(amount), TOTAL(amount) FROM t9")
    r = cur.fetchone()
    h.assert_equal_float("agg-1.2a", r.value().get_float(0), 500.0, 0.001, "SUM(amount) = 500.0")
    h.assert_equal_float("agg-1.2b", r.value().get_float(1), 500.0, 0.001, "TOTAL(amount) = 500.0")

    # 3. agg-1.3: AVG() function
    cur.execute("SELECT AVG(amount) FROM t9")
    r = cur.fetchone()
    h.assert_equal_float("agg-1.3", r.value().get_float(0), 125.0, 0.001, "AVG(amount) is 125.0 (500 / 4)")

    # 4. agg-1.4: MIN() and MAX() functions
    cur.execute("SELECT MIN(amount), MAX(amount) FROM t9")
    r = cur.fetchone()
    h.assert_equal_float("agg-1.4a", r.value().get_float(0), 50.0, 0.001, "MIN(amount) = 50.0")
    h.assert_equal_float("agg-1.4b", r.value().get_float(1), 200.0, 0.001, "MAX(amount) = 200.0")

    # 5. agg-1.5: GROUP BY aggregation
    cur.execute("SELECT category, SUM(amount) FROM t9 GROUP BY category ORDER BY category")
    var rows = cur.fetchall()
    h.assert_equal_int("agg-1.5a", len(rows), 3, "GROUP BY yielded 3 distinct categories")
    h.assert_equal("agg-1.5b", rows[0].get_string(0), "food", "First category is food")
    h.assert_equal_float("agg-1.5c", rows[0].get_float(1), 200.0, 0.01, "Food sum is 200.0")
    h.assert_equal("agg-1.5d", rows[2].get_string(0), "tech", "Third category is tech")
    h.assert_equal_float("agg-1.5e", rows[2].get_float(1), 300.0, 0.01, "Tech sum is 300.0")

    # 6. agg-1.6: HAVING filter on aggregated result
    cur.execute("SELECT category, SUM(amount) FROM t9 GROUP BY category HAVING SUM(amount) > 250")
    rows = cur.fetchall()
    h.assert_equal_int("agg-1.6a", len(rows), 1, "HAVING filtered down to 1 group")
    h.assert_equal("agg-1.6b", rows[0].get_string(0), "tech", "Selected group is tech")

    # 7. agg-1.7: Aggregate over empty table
    cur.execute("CREATE TABLE t9_empty(x INT)")
    cur.execute("SELECT COUNT(*), SUM(x), TOTAL(x) FROM t9_empty")
    r = cur.fetchone()
    h.assert_equal_int("agg-1.7a", r.value().get_int(0), 0, "COUNT(*) on empty table is 0")
    h.assert_true("agg-1.7b", r.value().is_null(1), "SUM(x) on empty table is NULL")
    h.assert_equal_float("agg-1.7c", r.value().get_float(2), 0.0, 0.001, "TOTAL(x) on empty table is 0.0")

    # 8. agg-1.8: COUNT(DISTINCT column)
    cur.execute("SELECT COUNT(DISTINCT category) FROM t9")
    r = cur.fetchone()
    h.assert_equal_int("agg-1.8", r.value().get_int(0), 3, "COUNT(DISTINCT category) is 3")

    # 9. agg-1.9: GROUP_CONCAT() function
    cur.execute("SELECT GROUP_CONCAT(category, ',') FROM t9 WHERE category != 'other' ORDER BY id")
    r = cur.fetchone()
    h.assert_true("agg-1.9", r.__bool__(), "GROUP_CONCAT returned valid result")

    # 10. agg-1.10: Aggregates with expressions
    cur.execute("SELECT SUM(amount * 2) FROM t9")
    r = cur.fetchone()
    h.assert_equal_float("agg-1.10", r.value().get_float(0), 1000.0, 0.001, "SUM(amount * 2) = 1000.0")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 09 - Aggregate Functions")
    run_aggregate_func_tests(h)
    h.summary()
