from tests.harness import TestHarness
from src.engine.connection import connect


def run_join_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 11: Multi-Table JOINs (join.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE users(id INT, name TEXT, dept_id INT)")
    cur.execute("CREATE TABLE depts(id INT, dept_name TEXT)")

    cur.execute("INSERT INTO users VALUES(1, 'Alice', 10)")
    cur.execute("INSERT INTO users VALUES(2, 'Bob', 20)")
    cur.execute("INSERT INTO users VALUES(3, 'Charlie', 10)")
    cur.execute("INSERT INTO users VALUES(4, 'David', 99)")  # No matching dept

    cur.execute("INSERT INTO depts VALUES(10, 'Engineering')")
    cur.execute("INSERT INTO depts VALUES(20, 'Marketing')")
    cur.execute("INSERT INTO depts VALUES(30, 'Sales')")

    # 1. join-1.1: Basic INNER JOIN
    cur.execute("SELECT users.name, depts.dept_name FROM users JOIN depts ON users.dept_id = depts.id")
    var rows = cur.fetchall()
    h.assert_equal_int("join-1.1a", len(rows), 3, "INNER JOIN returned 3 matched rows")
    h.assert_equal("join-1.1b", rows[0].get_string(0), "Alice", "First row is Alice")
    h.assert_equal("join-1.1c", rows[0].get_string(1), "Engineering", "Alice is in Engineering")

    # 2. join-1.2: INNER JOIN with Table Aliases
    cur.execute("SELECT u.name, d.dept_name FROM users AS u JOIN depts AS d ON u.dept_id = d.id WHERE d.dept_name = 'Marketing'")
    var r = cur.fetchone()
    h.assert_true("join-1.2a", r.__bool__(), "Row found for Marketing filter")
    h.assert_equal("join-1.2b", r.value().get_string(0), "Bob", "Bob is in Marketing")

    # 3. join-1.3: LEFT OUTER JOIN (includes unmatched rows with NULLs)
    cur.execute("SELECT u.name, d.dept_name FROM users AS u LEFT JOIN depts AS d ON u.dept_id = d.id ORDER BY u.id")
    rows = cur.fetchall()
    h.assert_equal_int("join-1.3a", len(rows), 4, "LEFT JOIN returned all 4 users")
    h.assert_equal("join-1.3b", rows[3].get_string(0), "David", "Fourth row is David")
    h.assert_true("join-1.3c", rows[3].is_null(1), "David dept_name is NULL")

    # 4. join-1.4: CROSS JOIN (Cartesian product)
    cur.execute("CREATE TABLE colors(name TEXT)")
    cur.execute("CREATE TABLE sizes(size TEXT)")
    cur.execute("INSERT INTO colors VALUES('Red')")
    cur.execute("INSERT INTO colors VALUES('Blue')")
    cur.execute("INSERT INTO sizes VALUES('S')")
    cur.execute("INSERT INTO sizes VALUES('M')")
    cur.execute("INSERT INTO sizes VALUES('L')")

    cur.execute("SELECT colors.name, sizes.size FROM colors CROSS JOIN sizes")
    rows = cur.fetchall()
    h.assert_equal_int("join-1.4", len(rows), 6, "CROSS JOIN 2 colors * 3 sizes = 6 rows")

    # 5. join-1.5: 3-Table Multi-JOIN
    cur.execute("CREATE TABLE projects(id INT, user_id INT, title TEXT)")
    cur.execute("INSERT INTO projects VALUES(101, 1, 'Compiler')")
    cur.execute("INSERT INTO projects VALUES(102, 1, 'Optimizer')")
    cur.execute("INSERT INTO projects VALUES(103, 2, 'AdCampaign')")

    cur.execute(
        "SELECT u.name, d.dept_name, p.title "
        + "FROM users AS u "
        + "JOIN depts AS d ON u.dept_id = d.id "
        + "JOIN projects AS p ON u.id = p.user_id "
        + "ORDER BY p.id"
    )
    rows = cur.fetchall()
    h.assert_equal_int("join-1.5a", len(rows), 3, "3-table JOIN returned 3 rows")
    h.assert_equal("join-1.5b", rows[0].get_string(2), "Compiler", "First project is Compiler")
    h.assert_equal("join-1.5c", rows[0].get_string(0), "Alice", "Project owner is Alice")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 11 - Multi-Table JOINs")
    run_join_tests(h)
    h.summary()
