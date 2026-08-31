from src import connect


def test_transactions() raises:
    print("=== Testing Transactions & Rollback ===")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE accounts (id INTEGER PRIMARY KEY, balance REAL)")
    cur.execute("INSERT INTO accounts VALUES (1, 1000.0)")
    con.commit()

    # Test Rollback
    cur.execute("BEGIN TRANSACTION")
    cur.execute("UPDATE accounts SET balance = 500.0 WHERE id = 1")
    cur.execute("SELECT balance FROM accounts WHERE id = 1")
    var row_in_tx = cur.fetchone()
    print("Balance inside transaction before rollback:", row_in_tx.value().get_float(0))
    con.rollback()

    cur.execute("SELECT balance FROM accounts WHERE id = 1")
    var row_after_rollback = cur.fetchone()
    print("Balance after rollback:", row_after_rollback.value().get_float(0))
    if row_after_rollback.value().get_float(0) != 1000.0:
        raise Error("Rollback failed to restore balance!")

    # Test Commit
    cur.execute("BEGIN TRANSACTION")
    cur.execute("UPDATE accounts SET balance = 1500.0 WHERE id = 1")
    con.commit()

    cur.execute("SELECT balance FROM accounts WHERE id = 1")
    var row_after_commit = cur.fetchone()
    print("Balance after commit:", row_after_commit.value().get_float(0))
    if row_after_commit.value().get_float(0) != 1500.0:
        raise Error("Commit failed to save balance!")

    cur.close()
    con.close()
    print("Transaction tests passed successfully!")

def main() raises:
    test_transactions()
