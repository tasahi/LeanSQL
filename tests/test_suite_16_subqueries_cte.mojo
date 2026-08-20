from tests.harness import TestHarness
from src.connection import connect


def run_subqueries_cte_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 16: Derived Tables & CTEs (cte.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE employees (id INT, name TEXT, salary REAL, dept TEXT)")
    cur.execute("INSERT INTO employees VALUES (1, 'Alice', 90000.0, 'Engineering')")
    cur.execute("INSERT INTO employees VALUES (2, 'Bob', 60000.0, 'Marketing')")
    cur.execute("INSERT INTO employees VALUES (3, 'Charlie', 80000.0, 'Engineering')")
    cur.execute("INSERT INTO employees VALUES (4, 'David', 50000.0, 'Marketing')")

    # 1. Derived Table in FROM: SELECT ... FROM (SELECT ...) AS sub
    cur.execute("SELECT name, salary FROM (SELECT * FROM employees WHERE salary > 55000) AS high_earners ORDER BY salary DESC")
    var q1 = cur.fetchall()
    h.assert_equal_int("cte-1.1a", Int64(len(q1)), 3, "Derived table filtered 3 rows")
    h.assert_equal("cte-1.1b", q1[0].get_string(0), "Alice", "Top earner is Alice")

    # 2. Non-recursive Common Table Expression (CTE)
    cur.execute("WITH eng AS (SELECT name, salary FROM employees WHERE dept = 'Engineering') SELECT name FROM eng WHERE salary >= 85000")
    var q2 = cur.fetchall()
    h.assert_equal_int("cte-1.2a", Int64(len(q2)), 1, "CTE query returned 1 matching row")
    h.assert_equal("cte-1.2b", q2[0].get_string(0), "Alice", "CTE selected Alice")

    # 3. Projection and ordering from CTE
    cur.execute("WITH dept_avg AS (SELECT dept, salary FROM employees) SELECT dept, salary FROM dept_avg ORDER BY salary ASC LIMIT 1")
    var q3 = cur.fetchall()
    h.assert_equal_int("cte-1.3a", Int64(len(q3)), 1, "CTE with ORDER BY and LIMIT returned 1 row")
    h.assert_equal_float("cte-1.3b", q3[0].get_float(1), 50000.0, 0.0001, "Lowest salary is 50000.0")

    # 4. Recursive CTE: Generate numbers 1 to 5
    cur.execute("WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM cnt WHERE x < 5) SELECT x FROM cnt")
    var q4 = cur.fetchall()
    h.assert_equal_int("cte-1.4a", Int64(len(q4)), 5, "Recursive CTE generated 5 iterations")
    h.assert_equal_int("cte-1.4b", q4[0].get_int(0), 1, "Start number is 1")
    h.assert_equal_int("cte-1.4c", q4[4].get_int(0), 5, "End number is 5")

    # 5. Recursive CTE: Powers of 2 up to 32
    cur.execute("WITH RECURSIVE pwr(n) AS (SELECT 1 UNION ALL SELECT n * 2 FROM pwr WHERE n < 32) SELECT n FROM pwr")
    var q5 = cur.fetchall()
    h.assert_equal_int("cte-1.5a", Int64(len(q5)), 6, "Powers of 2 returned 6 rows (1, 2, 4, 8, 16, 32)")
    h.assert_equal_int("cte-1.5b", q5[5].get_int(0), 32, "Final power of 2 is 32")


def main() raises:
    var h = TestHarness("Suite 16: Derived Tables & CTEs")
    run_subqueries_cte_tests(h)
    h.summary()
