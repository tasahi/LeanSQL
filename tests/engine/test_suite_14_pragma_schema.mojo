from tests.harness import TestHarness
from src.engine.connection import connect


def run_pragma_schema_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 14: PRAGMA & Schema Introspection (pragma.test) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE items(id INT PRIMARY KEY, name TEXT NOT NULL, price REAL DEFAULT 9.99)")
    cur.execute("CREATE INDEX idx_items_name ON items(name)")

    # 1. pragma-1.1: PRAGMA table_info(items)
    cur.execute("PRAGMA table_info(items)")
    var cols = cur.fetchall()
    h.assert_equal_int("pragma-1.1a", Int64(len(cols)), 3, "table_info returned 3 columns")

    # Column 0: id
    h.assert_equal("pragma-1.1b", cols[0].get_string(1), "id", "Col 0 name is id")
    h.assert_equal("pragma-1.1c", cols[0].get_string(2), "INTEGER", "Col 0 type is INTEGER")
    h.assert_equal_int("pragma-1.1d", cols[0].get_int(5), 1, "Col 0 pk is 1")

    # Column 1: name
    h.assert_equal("pragma-1.1e", cols[1].get_string(1), "name", "Col 1 name is name")
    h.assert_equal("pragma-1.1f", cols[1].get_string(2), "TEXT", "Col 1 type is TEXT")
    h.assert_equal_int("pragma-1.1g", cols[1].get_int(3), 1, "Col 1 notnull is 1")

    # Column 2: price
    h.assert_equal("pragma-1.1h", cols[2].get_string(1), "price", "Col 2 name is price")
    h.assert_equal("pragma-1.1i", cols[2].get_string(2), "REAL", "Col 2 type is REAL")

    # 2. pragma-1.2: PRAGMA index_list(items)
    cur.execute("PRAGMA index_list(items)")
    var idxs = cur.fetchall()
    h.assert_equal_int("pragma-1.2a", Int64(len(idxs)), 1, "index_list returned 1 index")
    h.assert_equal("pragma-1.2b", idxs[0].get_string(1), "idx_items_name", "Index name matches")

    # 3. pragma-1.3: PRAGMA user_version getter & setter
    cur.execute("PRAGMA user_version")
    var uv_row = cur.fetchone()
    h.assert_true("pragma-1.3a", uv_row.__bool__(), "user_version row returned")
    h.assert_equal_int("pragma-1.3b", uv_row.value().get_int(0), 0, "Initial user_version is 0")

    cur.execute("PRAGMA user_version = 42")
    cur.execute("PRAGMA user_version")
    uv_row = cur.fetchone()
    h.assert_true("pragma-1.3c", uv_row.__bool__(), "user_version row returned after update")
    h.assert_equal_int("pragma-1.3d", uv_row.value().get_int(0), 42, "Updated user_version is 42")

    # 4. pragma-1.4: sqlite_master query
    cur.execute("SELECT type, name FROM sqlite_master ORDER BY type, name")
    var master_rows = cur.fetchall()
    h.assert_equal_int("pragma-1.4a", Int64(len(master_rows)), 2, "sqlite_master returned 2 entries (table + index)")
    h.assert_equal("pragma-1.4b", master_rows[0].get_string(0), "index", "First entry is index")
    h.assert_equal("pragma-1.4c", master_rows[0].get_string(1), "idx_items_name", "Index name is idx_items_name")
    h.assert_equal("pragma-1.4d", master_rows[1].get_string(0), "table", "Second entry is table")
    h.assert_equal("pragma-1.4e", master_rows[1].get_string(1), "items", "Table name is items")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 14 - PRAGMA & Schema Introspection")
    run_pragma_schema_tests(h)
    h.summary()
