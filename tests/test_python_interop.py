import os
import sys

def main():
    print("=======================================================")
    print("=== Testing Python Native C-Extension: sqlean.so ===")
    print("=======================================================")

    sys.path.insert(0, os.getcwd())

    try:
        import sqlean
    except ImportError as e:
        print(f"[FAIL] Could not import sqlean: {e}")
        sys.exit(1)

    # 1. Test version()
    ver = sqlean.version()
    print(f"  [PASS] sqlean.version() -> {ver}")
    assert "SQLean" in ver

    # 2. Test execute() and execute_count()
    test_db = "sqlean_py_test.db"
    if os.path.exists(test_db):
        os.remove(test_db)

    sqlean.execute(test_db, "CREATE TABLE users(id INT, name TEXT, score REAL)")
    sqlean.execute(test_db, "INSERT INTO users VALUES(1, 'Alice', 95.5)")
    sqlean.execute(test_db, "INSERT INTO users VALUES(2, 'Bob', 88.0)")
    sqlean.execute(test_db, "INSERT INTO users VALUES(3, 'Charlie', 72.5)")

    cnt = sqlean.execute_count(test_db, "users")
    print(f"  [PASS] sqlean.execute_count() -> {cnt}")
    assert cnt == 3, f"Expected 3, got {cnt}"

    # 3. Test execute_query()
    out = sqlean.execute_query(test_db, "SELECT id, name, score FROM users ORDER BY score DESC")
    print("  [PASS] sqlean.execute_query() ->")
    for line in out.strip().split("\n"):
        print(f"         {line}")

    lines = out.strip().split("\n")
    assert len(lines) == 3
    assert "Alice" in lines[0]

    # Clean up test db
    if os.path.exists(test_db):
        os.remove(test_db)

    print("\n--- Python Native Interoperability Tests: ALL PASSED ---")

if __name__ == "__main__":
    main()
