from tests.harness import TestHarness
from src.engine.connection import connect


def run_scalar_func_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 8: Scalar Functions (func.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    # 1. func-1.1: ABS() function
    cur.execute("SELECT ABS(-42), ABS(42), ABS(0)")
    var r = cur.fetchone()
    h.assert_equal_int("func-1.1a", r.value().get_int(0), 42, "ABS(-42) = 42")
    h.assert_equal_int("func-1.1b", r.value().get_int(1), 42, "ABS(42) = 42")
    h.assert_equal_int("func-1.1c", r.value().get_int(2), 0, "ABS(0) = 0")

    # 2. func-1.2: LENGTH() function
    cur.execute("SELECT LENGTH('SQLean'), LENGTH(''), LENGTH(NULL)")
    r = cur.fetchone()
    h.assert_equal_int("func-1.2a", r.value().get_int(0), 6, "LENGTH('SQLean') = 6")
    h.assert_equal_int("func-1.2b", r.value().get_int(1), 0, "LENGTH('') = 0")
    h.assert_true("func-1.2c", r.value().is_null(2), "LENGTH(NULL) is NULL")

    # 3. func-1.3: UPPER() and LOWER()
    cur.execute("SELECT UPPER('sqlite in mojo'), LOWER('SQLITE IN MOJO')")
    r = cur.fetchone()
    h.assert_equal("func-1.3a", r.value().get_string(0), "SQLITE IN MOJO", "UPPER() converts to uppercase")
    h.assert_equal("func-1.3b", r.value().get_string(1), "sqlite in mojo", "LOWER() converts to lowercase")

    # 4. func-1.4: SUBSTR()
    cur.execute("SELECT SUBSTR('Hello World', 1, 5), SUBSTR('Hello World', 7)")
    r = cur.fetchone()
    h.assert_equal("func-1.4a", r.value().get_string(0), "Hello", "SUBSTR('Hello World', 1, 5) = 'Hello'")
    h.assert_equal("func-1.4b", r.value().get_string(1), "World", "SUBSTR('Hello World', 7) = 'World'")

    # 5. func-1.5: TRIM(), LTRIM(), RTRIM()
    cur.execute("SELECT TRIM('  abc  '), LTRIM('  abc'), RTRIM('abc  ')")
    r = cur.fetchone()
    h.assert_equal("func-1.5a", r.value().get_string(0), "abc", "TRIM removes surrounding spaces")
    h.assert_equal("func-1.5b", r.value().get_string(1), "abc", "LTRIM removes left spaces")
    h.assert_equal("func-1.5c", r.value().get_string(2), "abc", "RTRIM removes right spaces")

    # 6. func-1.6: ROUND()
    cur.execute("SELECT ROUND(3.14159, 2), ROUND(3.5)")
    r = cur.fetchone()
    h.assert_equal_float("func-1.6a", r.value().get_float(0), 3.14, 0.001, "ROUND(3.14159, 2) = 3.14")
    h.assert_equal_float("func-1.6b", r.value().get_float(1), 4.0, 0.001, "ROUND(3.5) = 4.0")

    # 7. func-1.7: HEX()
    cur.execute("SELECT HEX('Mojo')")
    r = cur.fetchone()
    h.assert_equal("func-1.7", r.value().get_string(0), "4D6F6A6F", "HEX('Mojo') = 4D6F6A6F")

    # 8. func-1.8: INSTR()
    cur.execute("SELECT INSTR('banana', 'na'), INSTR('banana', 'xyz')")
    r = cur.fetchone()
    h.assert_equal_int("func-1.8a", r.value().get_int(0), 3, "INSTR('banana', 'na') = 3")
    h.assert_equal_int("func-1.8b", r.value().get_int(1), 0, "INSTR('banana', 'xyz') = 0")

    # 9. func-1.9: PRINTF() / FORMAT()
    cur.execute("SELECT PRINTF('Item %04d: %.2f', 7, 19.5)")
    r = cur.fetchone()
    h.assert_equal("func-1.9", r.value().get_string(0), "Item 0007: 19.50", "PRINTF formatted string correctly")

    # 10. func-1.10: RANDOM() returns valid integer
    cur.execute("SELECT typeof(RANDOM())")
    r = cur.fetchone()
    h.assert_equal("func-1.10", r.value().get_string(0), "integer", "RANDOM() yields integer type")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 08 - Scalar Functions")
    run_scalar_func_tests(h)
    h.summary()
