from src import connect


def test_memory_connection() raises:
    print("=== Testing in-memory connection ===")
    var con = connect(":memory:")
    var cur = con.cursor()
    cur.execute("SELECT 'Connection OK'")
    var row = cur.fetchone()
    if not row:
        raise Error("Expected row from in-memory test")
    print("Result:", row.value().get_string(0))
    cur.close()
    con.close()
    print("In-memory test passed!")


def main() raises:
    test_memory_connection()
