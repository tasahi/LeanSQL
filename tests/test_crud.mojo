from src import connect, Value


def test_crud_operations() raises:
    print("=== Testing CRUD Operations ===")
    var con = connect(":memory:")
    var cur = con.cursor()

    # 1. CREATE TABLE
    cur.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
    print("CREATE TABLE passed")

    # 2. INSERT data
    cur.execute("INSERT INTO users VALUES (1, 'Alice', 95.5)")
    cur.execute("INSERT INTO users VALUES (2, 'Bob', 88.0)")
    cur.execute("INSERT INTO users VALUES (3, 'Charlie', 72.3)")
    print("INSERT passed (changes:", con.total_changes(), ")")

    # 3. SELECT & fetchall
    cur.execute("SELECT id, name, score FROM users ORDER BY score DESC")
    var rows = cur.fetchall()
    print("Fetched", len(rows), "rows:")
    for i in range(len(rows)):
        var r = rows[i]
        print("  User:", r.get_int(0), "| Name:", r.get_string(1), "| Score:", r.get_float(2))

    if len(rows) != 3:
        raise Error("Expected 3 rows, got " + String(len(rows)))
    if rows[0].get_string(1) != "Alice":
        raise Error("Expected top scorer to be Alice")

    # 4. Parameterized Query
    var params = List[Value]()
    params.append(Value.of_float(80.0))
    cur.execute_params("SELECT id, name, score FROM users WHERE score > ? ORDER BY id", params)
    var high_scorers = cur.fetchall()
    print("High scorers count (> 80.0):", len(high_scorers))
    if len(high_scorers) != 2:
        raise Error("Expected 2 high scorers, got " + String(len(high_scorers)))

    # 5. UPDATE
    cur.execute("UPDATE users SET score = 99.9 WHERE id = 1")
    cur.execute("SELECT score FROM users WHERE id = 1")
    var updated_row = cur.fetchone()
    if not updated_row:
        raise Error("Expected row after update")
    print("Updated score:", updated_row.value().get_float(0))
    if updated_row.value().get_float(0) != 99.9:
        raise Error("Score was not updated correctly")

    # 6. DELETE
    cur.execute("DELETE FROM users WHERE id = 3")
    cur.execute("SELECT COUNT(*) FROM users")
    var count_row = cur.fetchone()
    if not count_row:
        raise Error("Expected count row")
    print("Final count:", count_row.value().get_int(0))
    if count_row.value().get_int(0) != 2:
        raise Error("Expected 2 users remaining")

    cur.close()
    con.close()
    print("CRUD operations test passed successfully!")


def main() raises:
    test_crud_operations()
