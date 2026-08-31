from tests.harness import TestHarness
from src.engine.connection import connect


def run_types_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 6: Types & Affinities (types.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE t6(i INTEGER, r REAL, t TEXT, b BLOB)")

    # 1. types-1.1: typeof() built-in function
    cur.execute("SELECT typeof(123), typeof(3.14159), typeof('hello'), typeof(NULL)")
    var r = cur.fetchone()
    h.assert_equal("types-1.1a", r.value().get_string(0), "integer", "typeof(123) is integer")
    h.assert_equal("types-1.1b", r.value().get_string(1), "real", "typeof(3.14) is real")
    h.assert_equal("types-1.1c", r.value().get_string(2), "text", "typeof('hello') is text")
    h.assert_equal("types-1.1d", r.value().get_string(3), "null", "typeof(NULL) is null")

    # 2. types-1.2: 64-bit large integer storage and retrieval
    cur.execute("INSERT INTO t6(i) VALUES(9223372036854775807)")
    cur.execute("SELECT i FROM t6 WHERE i > 9000000000000000000")
    r = cur.fetchone()
    h.assert_true("types-1.2", r.__bool__(), "Large 64-bit int fetched")

    # 3. types-1.3: Negative integer
    cur.execute("INSERT INTO t6(i) VALUES(-123456789)")
    cur.execute("SELECT i FROM t6 WHERE i = -123456789")
    r = cur.fetchone()
    h.assert_equal_int("types-1.3", r.value().get_int(0), -123456789, "Negative integer stored correctly")

    # 4. types-1.4: Floating point precision
    cur.execute("INSERT INTO t6(r) VALUES(1.23456789012345)")
    cur.execute("SELECT r FROM t6 WHERE r > 1.2345")
    r = cur.fetchone()
    h.assert_equal_float("types-1.4", r.value().get_float(0), 1.23456789012345, 0.000001, "Float precision matches")

    # 5. types-1.5: String with Unicode characters
    cur.execute("INSERT INTO t6(t) VALUES('SQLite in Mojo: \u2705 \U0001F525')")
    cur.execute("SELECT t FROM t6 WHERE t LIKE '%Mojo%'")
    r = cur.fetchone()
    h.assert_true("types-1.5", r.__bool__(), "Unicode text matched and fetched")

    # 6. types-1.6: CAST(text AS integer)
    cur.execute("SELECT CAST('456' AS INTEGER), CAST('123abc' AS INTEGER)")
    r = cur.fetchone()
    h.assert_equal_int("types-1.6a", r.value().get_int(0), 456, "CAST('456' AS INTEGER) = 456")
    h.assert_equal_int("types-1.6b", r.value().get_int(1), 123, "CAST('123abc' AS INTEGER) = 123")

    # 7. types-1.7: CAST(real AS text)
    cur.execute("SELECT CAST(2.5 AS TEXT)")
    r = cur.fetchone()
    h.assert_equal("types-1.7", r.value().get_string(0), "2.5", "CAST(2.5 AS TEXT) = '2.5'")

    # 8. types-1.8: Dynamic column typing (storing text in integer affinity column)
    cur.execute("INSERT INTO t6(i) VALUES('not_an_int')")
    cur.execute("SELECT typeof(i), i FROM t6 WHERE i = 'not_an_int'")
    r = cur.fetchone()
    h.assert_equal("types-1.8a", r.value().get_string(0), "text", "SQLite allows text in int column")
    h.assert_equal("types-1.8b", r.value().get_string(1), "not_an_int", "Read back exact text")

    # 9. types-1.9: Zero value representations (0 vs 0.0)
    cur.execute("SELECT typeof(0), typeof(0.0)")
    r = cur.fetchone()
    h.assert_equal("types-1.9a", r.value().get_string(0), "integer", "0 is integer")
    h.assert_equal("types-1.9b", r.value().get_string(1), "real", "0.0 is real")

    # 10. types-1.10: Empty string vs NULL
    cur.execute("SELECT '' IS NULL, LENGTH('')")
    r = cur.fetchone()
    h.assert_equal_int("types-1.10a", r.value().get_int(0), 0, "Empty string is NOT NULL")
    h.assert_equal_int("types-1.10b", r.value().get_int(1), 0, "LENGTH('') is 0")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 06 - Types & Affinities")
    run_types_tests(h)
    h.summary()
