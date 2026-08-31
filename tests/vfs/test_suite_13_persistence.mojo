from tests.harness import TestHarness
from src.engine.connection import connect
from src.vfs.vfs_os import VFS


def run_persistence_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 13: File-Backed Persistence (persist.test) ===")
    print("=======================================================")
    var vfs = VFS()
    var db_file = "leansql_test_disk.db"

    # Clean up before testing
    if vfs.file_exists(db_file):
        try:
            vfs.delete_file(db_file)
        except:
            pass

    # 1. persist-1.1: Create table and insert in session 1
    var con1 = connect(db_file)
    var cur1 = con1.cursor()
    cur1.execute("CREATE TABLE products(id INT, title TEXT, price REAL)")
    cur1.execute("INSERT INTO products VALUES(1, 'Laptop', 1200.0)")
    cur1.execute("INSERT INTO products VALUES(2, 'Mouse', 25.5)")
    cur1.execute("INSERT INTO products VALUES(3, 'Keyboard', 75.0)")
    con1.commit()
    con1.close()

    h.assert_true("persist-1.1", vfs.file_exists(db_file), "Database file created on disk")

    # 2. persist-1.2: Reopen file in session 2 and verify data survived
    var con2 = connect(db_file)
    var cur2 = con2.cursor()
    cur2.execute("SELECT id, title, price FROM products ORDER BY id")
    var rows = cur2.fetchall()
    h.assert_equal_int("persist-1.2a", len(rows), 3, "All 3 rows loaded from disk file")
    h.assert_equal("persist-1.2b", rows[0].get_string(1), "Laptop", "First row is Laptop")
    h.assert_equal("persist-1.2c", rows[2].get_string(1), "Keyboard", "Third row is Keyboard")

    # 3. persist-1.3: Update and insert in session 2, commit, close, and verify in session 3
    cur2.execute("INSERT INTO products VALUES(4, 'Monitor', 300.0)")
    cur2.execute("UPDATE products SET price = 1100.0 WHERE id = 1")
    con2.commit()
    con2.close()

    var con3 = connect(db_file)
    var cur3 = con3.cursor()
    cur3.execute("SELECT COUNT(*) FROM products")
    var cnt_row = cur3.fetchone()
    h.assert_true("persist-1.3a", cnt_row.__bool__(), "Count row returned")
    h.assert_equal_int("persist-1.3b", cnt_row.value().get_int(0), 4, "Total count is now 4")

    cur3.execute("SELECT price FROM products WHERE id = 1")
    var p_row = cur3.fetchone()
    h.assert_true("persist-1.3c", p_row.__bool__(), "Updated price row found")
    h.assert_equal("persist-1.3d", p_row.value().get_string(0), "1100.0", "Price updated to 1100.0")

    cur3.close()
    con3.close()

    # Clean up file after tests
    if vfs.file_exists(db_file):
        try:
            vfs.delete_file(db_file)
        except:
            pass


def main() raises:
    var h = TestHarness("Suite 13 - File Persistence")
    run_persistence_tests(h)
    h.summary()
