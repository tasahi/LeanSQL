"""Comprehensive Verification of the SQLean Python Drop-in Driver (sqlean_driver.py).
Tests DB-API 2.0 interface compatibility over compiled native sqlean.so.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import sqlean_driver as sqlean


class TestSQLeanPythonDriver(unittest.TestCase):
    def setUp(self):
        self.db_path = "test_driver_suite.db"
        if os.path.exists(self.db_path):
            os.remove(self.db_path)
        self.con = sqlean.connect(self.db_path)
        self.cur = self.con.cursor()

    def tearDown(self):
        self.cur.close()
        self.con.close()
        if os.path.exists(self.db_path):
            os.remove(self.db_path)

    def test_version_info(self):
        ver = sqlean.sqlite_version()
        self.assertIn("SQLean", ver)

    def test_create_and_insert(self):
        self.cur.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, salary REAL)")
        self.cur.execute("INSERT INTO users VALUES (1, 'Alice', 75000.0)")
        self.cur.execute("INSERT INTO users VALUES (2, 'Bob', 62000.0)")
        self.cur.execute("INSERT INTO users VALUES (3, 'Charlie', 89000.0)")

        self.cur.execute("SELECT COUNT(*) FROM users")
        row = self.cur.fetchone()
        self.assertEqual(row[0], 3)

    def test_select_fetchall(self):
        self.cur.execute("CREATE TABLE items (id INT, label TEXT)")
        self.cur.execute("INSERT INTO items VALUES (10, 'Alpha')")
        self.cur.execute("INSERT INTO items VALUES (20, 'Beta')")

        self.cur.execute("SELECT id, label FROM items ORDER BY id")
        rows = self.cur.fetchall()
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], (10, 'Alpha'))
        self.assertEqual(rows[1], (20, 'Beta'))

    def test_parameterized_query(self):
        self.cur.execute("CREATE TABLE products (id INT, price REAL)")
        self.cur.execute("INSERT INTO products VALUES (1, 99.9)")
        self.cur.execute("INSERT INTO products VALUES (2, 149.5)")

        self.cur.execute("SELECT id, price FROM products WHERE price > ?", (100.0,))
        rows = self.cur.fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][0], 2)

    def test_aggregates_and_joins(self):
        self.cur.execute("CREATE TABLE depts (id INT, name TEXT)")
        self.cur.execute("CREATE TABLE emps (id INT, name TEXT, dept_id INT, salary REAL)")

        self.cur.execute("INSERT INTO depts VALUES (1, 'Engineering')")
        self.cur.execute("INSERT INTO depts VALUES (2, 'Design')")

        self.cur.execute("INSERT INTO emps VALUES (1, 'Alice', 1, 100000.0)")
        self.cur.execute("INSERT INTO emps VALUES (2, 'Bob', 1, 90000.0)")
        self.cur.execute("INSERT INTO emps VALUES (3, 'Carol', 2, 85000.0)")

        self.cur.execute("""
            SELECT d.name, COUNT(e.id), AVG(e.salary)
            FROM depts d
            JOIN emps e ON d.id = e.dept_id
            GROUP BY d.name
            ORDER BY d.name
        """)
        rows = self.cur.fetchall()
        self.assertEqual(len(rows), 2)
        # Design
        self.assertEqual(rows[0][0], 'Design')
        self.assertEqual(rows[0][1], 1)
        self.assertEqual(rows[0][2], 85000.0)
        # Engineering
        self.assertEqual(rows[1][0], 'Engineering')
        self.assertEqual(rows[1][1], 2)
        self.assertEqual(rows[1][2], 95000.0)


if __name__ == "__main__":
    print("=======================================================")
    print("=== Suite 21: Python DB-API Driver Verification     ===")
    print("=======================================================")
    unittest.main()
