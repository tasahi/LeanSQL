import os
import sys

def main():
    print("=======================================================")
    print("=== Testing Python Native C-Extension: leansql.so ===")
    print("=======================================================")

    sys.path.insert(0, os.getcwd())

    try:
        import leansql
    except ImportError as e:
        print(f"[FAIL] Could not import leansql: {e}")
        sys.exit(1)

    # 1. Test version()
    ver = leansql.version()
    print(f"  [PASS] leansql.version() -> {ver}")
    assert "LeanSQL" in ver

    # 2. Test execute() and execute_count()
    test_db = "leansql_py_test.db"
    if os.path.exists(test_db):
        os.remove(test_db)

    leansql.execute(test_db, "CREATE TABLE users(id INT, name TEXT, score REAL)")
    leansql.execute(test_db, "INSERT INTO users VALUES(1, 'Alice', 95.5)")
    leansql.execute(test_db, "INSERT INTO users VALUES(2, 'Bob', 88.0)")
    leansql.execute(test_db, "INSERT INTO users VALUES(3, 'Charlie', 72.5)")

    cnt = leansql.execute_count(test_db, "users")
    print(f"  [PASS] leansql.execute_count() -> {cnt}")
    assert cnt == 3, f"Expected 3, got {cnt}"

    # 3. Test execute_query()
    out = leansql.execute_query(test_db, "SELECT id, name, score FROM users ORDER BY score DESC")
    print("  [PASS] leansql.execute_query() ->")
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
