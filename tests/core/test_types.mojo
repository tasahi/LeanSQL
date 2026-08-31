from src import connect, Value


def test_sqlite_types() raises:
    print("=== Testing SQLite Types in Mojo ===")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE test_types (id INTEGER, i_val INTEGER, f_val REAL, t_val TEXT, n_val TEXT)")
    
    var params = List[Value]()
    params.append(Value.of_int(1))
    params.append(Value.of_int(9223372036854775807)) # max int64
    params.append(Value.of_float(3.141592653589793))
    params.append(Value.of_text("🔥 Mojo + SQLite 🔥"))
    params.append(Value.of_null())

    cur.execute_params("INSERT INTO test_types VALUES (?, ?, ?, ?, ?)", params)
    
    cur.execute("SELECT id, i_val, f_val, t_val, n_val FROM test_types WHERE id = 1")
    var row_opt = cur.fetchone()
    if not row_opt:
        raise Error("Expected row from test_types")
    
    var r = row_opt.value()
    print("Int64 max:", r.get_int(1))
    if r.get_int(1) != 9223372036854775807:
        raise Error("Int64 mismatch")

    print("Float val:", r.get_float(2))
    if r.get_float(2) < 3.14159:
        raise Error("Float mismatch")

    print("Unicode text:", r.get_string(3))
    if r.get_string(3) != "🔥 Mojo + SQLite 🔥":
        raise Error("Text mismatch")

    print("Is null:", r.is_null(4))
    if not r.is_null(4):
        raise Error("Expected column 4 to be null")

    cur.close()
    con.close()
    print("SQLite Types test passed successfully!")


def main() raises:
    test_sqlite_types()
