from tests.harness import TestHarness
from src.connection import connect


def run_trans_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 7: Transactions & Isolation (trans.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE t7(id INT PRIMARY KEY, balance REAL)")
    cur.execute("INSERT INTO t7 VALUES(1, 1000.0)")

    # 1. trans-1.1: Autocommit default state
    h.assert_true("trans-1.1", con.autocommit(), "Autocommit is initially TRUE (1)")

    # 2. trans-1.2: Explicit BEGIN turns off autocommit
    cur.execute("BEGIN TRANSACTION")
    h.assert_true("trans-1.2", not con.autocommit(), "Autocommit is FALSE inside BEGIN")

    # 3. trans-1.3: COMMIT transaction commits changes and restores autocommit
    cur.execute("UPDATE t7 SET balance = 1500.0 WHERE id = 1")
    con.commit()
    h.assert_true("trans-1.3a", con.autocommit(), "Autocommit is restored after COMMIT")
    cur.execute("SELECT balance FROM t7 WHERE id = 1")
    var r = cur.fetchone()
    h.assert_equal_float("trans-1.3b", r.value().get_float(0), 1500.0, 0.001, "Committed balance is 1500.0")

    # 4. trans-1.4: ROLLBACK transaction discards changes
    cur.execute("BEGIN")
    cur.execute("UPDATE t7 SET balance = 0.0 WHERE id = 1")
    con.rollback()
    h.assert_true("trans-1.4a", con.autocommit(), "Autocommit is restored after ROLLBACK")
    cur.execute("SELECT balance FROM t7 WHERE id = 1")
    r = cur.fetchone()
    h.assert_equal_float("trans-1.4b", r.value().get_float(0), 1500.0, 0.001, "Rollback preserved 1500.0")

    # 5. trans-1.5: ROLLBACK on INSERT discards newly created row
    cur.execute("BEGIN")
    cur.execute("INSERT INTO t7 VALUES(2, 500.0)")
    con.rollback()
    cur.execute("SELECT COUNT(*) FROM t7 WHERE id = 2")
    r = cur.fetchone()
    h.assert_equal_int("trans-1.5", r.value().get_int(0), 0, "Inserted row rolled back")

    # 6. trans-1.6: ROLLBACK on DELETE restores deleted row
    cur.execute("BEGIN")
    cur.execute("DELETE FROM t7 WHERE id = 1")
    con.rollback()
    cur.execute("SELECT COUNT(*) FROM t7 WHERE id = 1")
    r = cur.fetchone()
    h.assert_equal_int("trans-1.6", r.value().get_int(0), 1, "Deleted row restored on rollback")

    # 7. trans-1.7: Multi-statement transaction atomicity
    cur.execute("BEGIN")
    cur.execute("INSERT INTO t7 VALUES(2, 200.0)")
    cur.execute("INSERT INTO t7 VALUES(3, 300.0)")
    cur.execute("UPDATE t7 SET balance = 2000.0 WHERE id = 1")
    con.commit()
    cur.execute("SELECT COUNT(*), SUM(balance) FROM t7")
    r = cur.fetchone()
    h.assert_equal_int("trans-1.7a", r.value().get_int(0), 3, "3 rows present after atomic commit")
    h.assert_equal_float("trans-1.7b", r.value().get_float(1), 2500.0, 0.01, "Total balance is 2500.0")

    # 8. trans-1.8: SAVEPOINT creation and RELEASE
    cur.execute("SAVEPOINT sp1")
    cur.execute("UPDATE t7 SET balance = 9999.0 WHERE id = 1")
    cur.execute("RELEASE SAVEPOINT sp1")
    cur.execute("SELECT balance FROM t7 WHERE id = 1")
    r = cur.fetchone()
    h.assert_equal_float("trans-1.8", r.value().get_float(0), 9999.0, 0.01, "Savepoint released and committed")

    # 9. trans-1.9: ROLLBACK TO SAVEPOINT
    cur.execute("SAVEPOINT sp2")
    cur.execute("UPDATE t7 SET balance = 1.0 WHERE id = 1")
    cur.execute("ROLLBACK TO SAVEPOINT sp2")
    cur.execute("SELECT balance FROM t7 WHERE id = 1")
    r = cur.fetchone()
    h.assert_equal_float("trans-1.9", r.value().get_float(0), 9999.0, 0.01, "Rollback to savepoint restored balance")

    # 10. trans-1.10: Clean final state verification
    cur.execute("SELECT COUNT(*) FROM t7")
    r = cur.fetchone()
    h.assert_equal_int("trans-1.10", r.value().get_int(0), 3, "Final row count verified")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 07 - Transactions & Isolation")
    run_trans_tests(h)
    h.summary()
