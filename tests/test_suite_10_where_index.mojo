from tests.harness import TestHarness
from src.connection import connect


def run_where_index_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 10: WHERE Clauses & Indexes (where.test, index.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE t10(id INT, email TEXT, age INT, city TEXT)")
    cur.execute("INSERT INTO t10 VALUES(1, 'alice@example.com', 25, 'London')")
    cur.execute("INSERT INTO t10 VALUES(2, 'bob@example.com', 30, 'Paris')")
    cur.execute("INSERT INTO t10 VALUES(3, 'charlie@example.com', 35, 'London')")
    cur.execute("INSERT INTO t10 VALUES(4, 'david@example.com', 40, 'Tokyo')")
    cur.execute("INSERT INTO t10 VALUES(5, 'eve@example.com', 22, 'New York')")

    # 1. where-1.1: Multi-predicate AND filter
    cur.execute("SELECT id FROM t10 WHERE city = 'London' AND age > 30")
    var r = cur.fetchone()
    h.assert_true("where-1.1a", r.__bool__(), "Row found")
    h.assert_equal_int("where-1.1b", r.value().get_int(0), 3, "charlie (id=3) matches London AND age > 30")

    # 2. where-1.2: Multi-predicate OR filter
    cur.execute("SELECT COUNT(*) FROM t10 WHERE city = 'Paris' OR city = 'Tokyo'")
    r = cur.fetchone()
    h.assert_equal_int("where-1.2", r.value().get_int(0), 2, "2 rows match Paris OR Tokyo")

    # 3. where-1.3: Parenthesized compound logic (A AND (B OR C))
    cur.execute("SELECT id FROM t10 WHERE age >= 30 AND (city = 'Paris' OR city = 'London')")
    var rows = cur.fetchall()
    h.assert_equal_int("where-1.3", len(rows), 2, "Bob (id=2) and Charlie (id=3) match")

    # 4. where-1.4: IN clause with string literals
    cur.execute("SELECT COUNT(*) FROM t10 WHERE city IN ('London', 'Tokyo')")
    r = cur.fetchone()
    h.assert_equal_int("where-1.4", r.value().get_int(0), 3, "3 rows in London or Tokyo")

    # 5. where-1.5: NOT IN clause
    cur.execute("SELECT COUNT(*) FROM t10 WHERE city NOT IN ('London', 'Tokyo')")
    r = cur.fetchone()
    h.assert_equal_int("where-1.5", r.value().get_int(0), 2, "2 rows not in London or Tokyo")

    # 6. index-1.1: CREATE INDEX statement
    cur.execute("CREATE INDEX idx_t10_email ON t10(email)")
    cur.execute("SELECT email FROM t10 WHERE email = 'alice@example.com'")
    r = cur.fetchone()
    h.assert_equal("index-1.1", r.value().get_string(0), "alice@example.com", "Index lookup matches")

    # 7. index-1.2: CREATE UNIQUE INDEX
    cur.execute("CREATE TABLE t10_uniq(code TEXT UNIQUE, name TEXT)")
    cur.execute("INSERT INTO t10_uniq VALUES('US', 'United States')")
    cur.execute("INSERT INTO t10_uniq VALUES('GB', 'United Kingdom')")
    cur.execute("SELECT COUNT(*) FROM t10_uniq")
    r = cur.fetchone()
    h.assert_equal_int("index-1.2", r.value().get_int(0), 2, "Unique table holds 2 items")

    # 8. index-1.3: Composite Index (multi-column)
    cur.execute("CREATE INDEX idx_t10_city_age ON t10(city, age)")
    cur.execute("SELECT id FROM t10 WHERE city = 'London' AND age = 25")
    r = cur.fetchone()
    h.assert_equal_int("index-1.3", r.value().get_int(0), 1, "Composite index query returns id=1")

    # 9. index-1.4: DROP INDEX
    cur.execute("DROP INDEX idx_t10_email")
    cur.execute("SELECT email FROM t10 WHERE email = 'bob@example.com'")
    r = cur.fetchone()
    h.assert_equal("index-1.4", r.value().get_string(0), "bob@example.com", "Query succeeds after dropping index")

    # 10. index-1.5: Subquery in WHERE clause (scalar subquery)
    cur.execute("SELECT id FROM t10 WHERE age = (SELECT MAX(age) FROM t10)")
    r = cur.fetchone()
    h.assert_equal_int("index-1.5", r.value().get_int(0), 4, "Subquery found max age id=4 (David, 40)")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 10 - WHERE Clauses & Indexes")
    run_where_index_tests(h)
    h.summary()
