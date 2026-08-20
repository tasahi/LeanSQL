from tests.harness import TestHarness
from src.connection import connect


def run_expr_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 4: Expressions & Operators (expr.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    # 1. expr-1.1: Integer addition and subtraction
    cur.execute("SELECT 10 + 20, 100 - 35")
    var r = cur.fetchone()
    h.assert_equal_int("expr-1.1a", r.value().get_int(0), 30, "10 + 20 = 30")
    h.assert_equal_int("expr-1.1b", r.value().get_int(1), 65, "100 - 35 = 65")

    # 2. expr-1.2: Multiplication and integer division
    cur.execute("SELECT 12 * 5, 100 / 4")
    r = cur.fetchone()
    h.assert_equal_int("expr-1.2a", r.value().get_int(0), 60, "12 * 5 = 60")
    h.assert_equal_int("expr-1.2b", r.value().get_int(1), 25, "100 / 4 = 25")

    # 3. expr-1.3: Modulo operator (%)
    cur.execute("SELECT 17 % 5, 20 % 4")
    r = cur.fetchone()
    h.assert_equal_int("expr-1.3a", r.value().get_int(0), 2, "17 % 5 = 2")
    h.assert_equal_int("expr-1.3b", r.value().get_int(1), 0, "20 % 4 = 0")

    # 4. expr-1.4: Floating point arithmetic
    cur.execute("SELECT 1.5 * 2.0, 7.5 / 2.5")
    r = cur.fetchone()
    h.assert_equal_float("expr-1.4a", r.value().get_float(0), 3.0, 0.001, "1.5 * 2.0 = 3.0")
    h.assert_equal_float("expr-1.4b", r.value().get_float(1), 3.0, 0.001, "7.5 / 2.5 = 3.0")

    # 5. expr-1.5: Comparison operators (<, <=, >, >=, =, !=)
    cur.execute("SELECT 10 < 20, 20 <= 20, 30 > 50, 40 >= 40, 50 = 50, 60 != 70")
    r = cur.fetchone()
    h.assert_equal_int("expr-1.5a", r.value().get_int(0), 1, "10 < 20 is TRUE (1)")
    h.assert_equal_int("expr-1.5b", r.value().get_int(1), 1, "20 <= 20 is TRUE (1)")
    h.assert_equal_int("expr-1.5c", r.value().get_int(2), 0, "30 > 50 is FALSE (0)")
    h.assert_equal_int("expr-1.5d", r.value().get_int(3), 1, "40 >= 40 is TRUE (1)")
    h.assert_equal_int("expr-1.5e", r.value().get_int(4), 1, "50 = 50 is TRUE (1)")
    h.assert_equal_int("expr-1.5f", r.value().get_int(5), 1, "60 != 70 is TRUE (1)")

    # 6. expr-1.6: String concatenation operator (||)
    cur.execute("SELECT 'Hello' || ' ' || 'World'")
    r = cur.fetchone()
    h.assert_equal("expr-1.6", r.value().get_string(0), "Hello World", "String concatenation with ||")

    # 7. expr-1.7: Operator precedence (multiplication before addition)
    cur.execute("SELECT 2 + 3 * 4, (2 + 3) * 4")
    r = cur.fetchone()
    h.assert_equal_int("expr-1.7a", r.value().get_int(0), 14, "2 + 3 * 4 = 14")
    h.assert_equal_int("expr-1.7b", r.value().get_int(1), 20, "(2 + 3) * 4 = 20")

    # 8. expr-1.8: BETWEEN operator
    cur.execute("SELECT 15 BETWEEN 10 AND 20, 25 BETWEEN 10 AND 20")
    r = cur.fetchone()
    h.assert_equal_int("expr-1.8a", r.value().get_int(0), 1, "15 BETWEEN 10 AND 20 is 1")
    h.assert_equal_int("expr-1.8b", r.value().get_int(1), 0, "25 BETWEEN 10 AND 20 is 0")

    # 9. expr-1.9: IN (...) set membership
    cur.execute("SELECT 3 IN (1, 2, 3, 4), 9 IN (1, 2, 3, 4)")
    r = cur.fetchone()
    h.assert_equal_int("expr-1.9a", r.value().get_int(0), 1, "3 IN (1,2,3,4) is 1")
    h.assert_equal_int("expr-1.9b", r.value().get_int(1), 0, "9 IN (1,2,3,4) is 0")

    # 10. expr-1.10: CASE ... WHEN ... THEN ... ELSE ... END
    cur.execute("SELECT CASE WHEN 1 > 2 THEN 'no' WHEN 2 > 1 THEN 'yes' ELSE 'other' END")
    r = cur.fetchone()
    h.assert_equal("expr-1.10", r.value().get_string(0), "yes", "CASE expression evaluated correctly")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 04 - Expressions & Operators")
    run_expr_tests(h)
    h.summary()
