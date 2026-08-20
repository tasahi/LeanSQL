from tests.harness import TestHarness
from src.connection import connect


def run_triggers_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 18: Database Triggers (trigger1.test)     ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE accounts (id INT, holder TEXT, balance REAL)")
    cur.execute("CREATE TABLE audit_log (id INT, msg TEXT, amount REAL)")

    # 1. CREATE TRIGGER AFTER INSERT
    cur.execute("CREATE TRIGGER trg_insert AFTER INSERT ON accounts FOR EACH ROW BEGIN INSERT INTO audit_log VALUES (NEW.id, 'Account opened', NEW.balance); END;")

    # Verify trigger listed in sqlite_master
    cur.execute("SELECT name, tbl_name FROM sqlite_master WHERE type = 'trigger'")
    var t_rows = cur.fetchall()
    h.assert_equal_int("trg-1.1a", Int64(len(t_rows)), 1, "Trigger listed in sqlite_master")
    h.assert_equal("trg-1.1b", t_rows[0].get_string(0), "trg_insert", "Trigger name matches")
    h.assert_equal("trg-1.1c", t_rows[0].get_string(1), "accounts", "Trigger table matches")

    # Insert into accounts and verify trigger fired
    cur.execute("INSERT INTO accounts VALUES (101, 'Alice', 1500.0)")
    cur.execute("SELECT id, msg, amount FROM audit_log WHERE id = 101")
    var a_rows = cur.fetchall()
    h.assert_equal_int("trg-1.2a", Int64(len(a_rows)), 1, "Audit log row created by AFTER INSERT trigger")
    h.assert_equal("trg-1.2b", a_rows[0].get_string(1), "Account opened", "Audit message matches")
    h.assert_equal_float("trg-1.2c", a_rows[0].get_float(2), 1500.0, 0.0001, "Audit amount matches Alice balance")

    # 2. CREATE TRIGGER AFTER UPDATE
    cur.execute("CREATE TRIGGER trg_update AFTER UPDATE ON accounts FOR EACH ROW BEGIN INSERT INTO audit_log VALUES (999, 'Account balance updated', 0.0); END;")
    cur.execute("UPDATE accounts SET balance = 2000.0 WHERE id = 101")
    cur.execute("SELECT msg FROM audit_log WHERE id = 999")
    var u_rows = cur.fetchall()
    h.assert_equal_int("trg-1.3a", Int64(len(u_rows)), 1, "Audit log row created by AFTER UPDATE trigger")
    h.assert_equal("trg-1.3b", u_rows[0].get_string(0), "Account balance updated", "Update audit message matches")

    # 3. CREATE TRIGGER AFTER DELETE
    cur.execute("CREATE TRIGGER trg_delete AFTER DELETE ON accounts FOR EACH ROW BEGIN INSERT INTO audit_log VALUES (888, 'Account closed', 0.0); END;")
    cur.execute("DELETE FROM accounts WHERE id = 101")
    cur.execute("SELECT msg FROM audit_log WHERE id = 888")
    var d_rows = cur.fetchall()
    h.assert_equal_int("trg-1.4a", Int64(len(d_rows)), 1, "Audit log row created by AFTER DELETE trigger")
    h.assert_equal("trg-1.4b", d_rows[0].get_string(0), "Account closed", "Delete audit message matches")

    # 4. DROP TRIGGER
    cur.execute("DROP TRIGGER trg_insert")
    cur.execute("SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = 'trg_insert'")
    var no_trg = cur.fetchall()
    h.assert_equal_int("trg-1.5", Int64(len(no_trg)), 0, "Trigger removed from catalog after DROP TRIGGER")


def main() raises:
    var h = TestHarness("Suite 18: Database Triggers")
    run_triggers_tests(h)
    h.summary()
