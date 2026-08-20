from tests.harness import TestHarness
from src.connection import connect


def run_null_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 5: NULL Logic & 3VL (null.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    # 1. null-1.1: NULL equality is NULL (falsy in WHERE)
    cur.execute("SELECT (NULL = NULL), (NULL != NULL)")
    var r = cur.fetchone()
    h.assert_true("null-1.1a", r.value().is_null(0), "NULL = NULL is NULL")
    h.assert_true("null-1.1b", r.value().is_null(1), "NULL != NULL is NULL")

    # 2. null-1.2: IS NULL and IS NOT NULL
    cur.execute("SELECT NULL IS NULL, 42 IS NULL, NULL IS NOT NULL, 42 IS NOT NULL")
    r = cur.fetchone()
    h.assert_equal_int("null-1.2a", r.value().get_int(0), 1, "NULL IS NULL is 1")
    h.assert_equal_int("null-1.2b", r.value().get_int(1), 0, "42 IS NULL is 0")
    h.assert_equal_int("null-1.2c", r.value().get_int(2), 0, "NULL IS NOT NULL is 0")
    h.assert_equal_int("null-1.2d", r.value().get_int(3), 1, "42 IS NOT NULL is 1")

    # 3. null-1.3: Arithmetic with NULL yields NULL
    cur.execute("SELECT 10 + NULL, 5 * NULL, NULL / 2")
    r = cur.fetchone()
    h.assert_true("null-1.3a", r.value().is_null(0), "10 + NULL is NULL")
    h.assert_true("null-1.3b", r.value().is_null(1), "5 * NULL is NULL")
    h.assert_true("null-1.3c", r.value().is_null(2), "NULL / 2 is NULL")

    # 4. null-1.4: String concatenation with NULL yields NULL
    cur.execute("SELECT 'abc' || NULL")
    r = cur.fetchone()
    h.assert_true("null-1.4", r.value().is_null(0), "'abc' || NULL is NULL")

    # 5. null-1.5: COALESCE function
    cur.execute("SELECT COALESCE(NULL, NULL, 'first_non_null', 'second')")
    r = cur.fetchone()
    h.assert_equal("null-1.5", r.value().get_string(0), "first_non_null", "COALESCE returns first non-null")

    # 6. null-1.6: IFNULL function
    cur.execute("SELECT IFNULL(NULL, 'fallback'), IFNULL('value', 'fallback')")
    r = cur.fetchone()
    h.assert_equal("null-1.6a", r.value().get_string(0), "fallback", "IFNULL on NULL uses fallback")
    h.assert_equal("null-1.6b", r.value().get_string(1), "value", "IFNULL on non-NULL keeps value")

    # 7. null-1.7: NULL in WHERE clause filtering
    cur.execute("CREATE TABLE t_null(id INT, v INT)")
    cur.execute("INSERT INTO t_null VALUES(1, 10)")
    cur.execute("INSERT INTO t_null VALUES(2, NULL)")
    cur.execute("INSERT INTO t_null VALUES(3, 20)")
    cur.execute("SELECT COUNT(*) FROM t_null WHERE v > 0")
    r = cur.fetchone()
    h.assert_equal_int("null-1.7", r.value().get_int(0), 2, "WHERE v > 0 excludes NULL")

    # 8. null-1.8: Querying for IS NULL in table
    cur.execute("SELECT id FROM t_null WHERE v IS NULL")
    r = cur.fetchone()
    h.assert_equal_int("null-1.8", r.value().get_int(0), 2, "Found row with NULL value")

    # 9. null-1.9: NULL ordering (NULLs sort first in ASC)
    cur.execute("SELECT id FROM t_null ORDER BY v ASC")
    var rows = cur.fetchall()
    h.assert_equal_int("null-1.9", rows[0].get_int(0), 2, "NULLs sort first in ASC")

    # 10. null-1.10: NULL in NOT IN clause
    cur.execute("SELECT 1 NOT IN (2, 3, NULL)")
    r = cur.fetchone()
    h.assert_true("null-1.10", r.value().is_null(0), "x NOT IN (..., NULL) evaluates to NULL")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 05 - NULL Logic & 3VL")
    run_null_tests(h)
    h.summary()
