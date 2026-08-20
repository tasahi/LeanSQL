from tests.harness import TestHarness
from src.connection import connect


def run_alter_view_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 15: ALTER TABLE & Views (alter.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE employees(id INT, name TEXT)")
    cur.execute("INSERT INTO employees VALUES(1, 'Alice')")
    cur.execute("INSERT INTO employees VALUES(2, 'Bob')")

    # 1. alter-1.1: ALTER TABLE RENAME TO
    cur.execute("ALTER TABLE employees RENAME TO staff")
    cur.execute("SELECT id, name FROM staff ORDER BY id")
    var rows = cur.fetchall()
    h.assert_equal_int("alter-1.1a", Int64(len(rows)), 2, "staff has 2 rows after rename")
    h.assert_equal("alter-1.1b", rows[0].get_string(1), "Alice", "First staff is Alice")
    h.assert_equal("alter-1.1c", rows[1].get_string(1), "Bob", "Second staff is Bob")

    # 2. alter-1.2: ALTER TABLE ADD COLUMN
    cur.execute("ALTER TABLE staff ADD COLUMN role TEXT DEFAULT 'Engineer'")
    cur.execute("SELECT id, name, role FROM staff WHERE id = 1")
    var r1 = cur.fetchone()
    h.assert_true("alter-1.2a", r1.__bool__(), "Row 1 returned with added column")
    h.assert_equal("alter-1.2b", r1.value().get_string(2), "Engineer", "Default role is Engineer")

    # 3. alter-1.3: Insert with new column and ALTER TABLE RENAME COLUMN
    cur.execute("INSERT INTO staff VALUES(3, 'Charlie', 'Manager')")
    cur.execute("ALTER TABLE staff RENAME COLUMN role TO title")
    cur.execute("SELECT title FROM staff WHERE name = 'Charlie'")
    var r3 = cur.fetchone()
    h.assert_true("alter-1.3a", r3.__bool__(), "Row Charlie returned")
    h.assert_equal("alter-1.3b", r3.value().get_string(0), "Manager", "Renamed column title is Manager")

    # 4. alter-1.4: CREATE VIEW & Query View
    cur.execute("CREATE VIEW v_staff AS SELECT id, name FROM staff")
    cur.execute("SELECT type, name FROM sqlite_master WHERE type = 'view'")
    var v_row = cur.fetchone()
    h.assert_true("alter-1.4a", v_row.__bool__(), "View listed in sqlite_master")
    h.assert_equal("alter-1.4b", v_row.value().get_string(1), "v_staff", "View name is v_staff")

    # 5. alter-1.5: DROP VIEW
    cur.execute("DROP VIEW v_staff")
    cur.execute("SELECT type, name FROM sqlite_master WHERE type = 'view'")
    var v_none = cur.fetchone()
    h.assert_true("alter-1.5", not v_none.__bool__(), "View removed after DROP VIEW")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 15 - ALTER TABLE & Views")
    run_alter_view_tests(h)
    h.summary()
