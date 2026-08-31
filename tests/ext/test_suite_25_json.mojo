from tests.harness import TestHarness
from src.engine.connection import connect


def run_json_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 25: JSON Functions & Path Operators (json) ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    # 1. Direct JSON Scalar Functions
    cur.execute("SELECT json_valid('{\"a\": 1, \"b\": [2, 3]}'), json_valid('invalid json')")
    var r = cur.fetchone()
    h.assert_equal_int("json-1.1a", r.value().get_int(0), 1, "json_valid on valid json returns 1")
    h.assert_equal_int("json-1.1b", r.value().get_int(1), 0, "json_valid on invalid json returns 0")

    # 2. json_extract and json_array_length
    cur.execute("""
        SELECT 
            json_extract('{"name": "Alice", "address": {"city": "New York"}}', '$.address.city'),
            json_array_length('{"tags": ["admin", "dev", "ai"]}', '$.tags'),
            json_type('{"active": true}', '$.active')
    """)
    r = cur.fetchone()
    h.assert_equal("json-1.2a", r.value().get_string(0), "New York", "json_extract returns nested field")
    h.assert_equal_int("json-1.2b", r.value().get_int(1), 3, "json_array_length returns 3")
    h.assert_equal("json-1.2c", r.value().get_string(2), "true", "json_type returns true")

    # 3. Table creation and Arrow operators (-> and ->>)
    cur.execute("CREATE TABLE users (id INTEGER, metadata TEXT)")
    cur.execute("INSERT INTO users VALUES (1, '{\"name\": \"Alice\", \"age\": 30, \"address\": {\"city\": \"New York\", \"zip\": \"10001\"}, \"tags\": [\"admin\", \"dev\"]}')")
    cur.execute("INSERT INTO users VALUES (2, '{\"name\": \"Bob\", \"age\": 25, \"address\": {\"city\": \"San Francisco\", \"zip\": \"94101\"}, \"tags\": [\"user\"]}')")

    # 4. Query using arrow operators and functions
    cur.execute("""
        SELECT 
            id,
            metadata->>'$.name' AS user_name,
            json_extract(metadata, '$.address.city') AS city,
            json_array_length(metadata, '$.tags') AS tag_count
        FROM users
        WHERE metadata->>'$.age' >= 28
    """)
    var rows = cur.fetchall()
    h.assert_equal_int("json-1.3a", len(rows), 1, "Filtered to 1 user with age >= 28")
    h.assert_equal_int("json-1.3b", rows[0].get_int(0), 1, "User ID is 1")
    h.assert_equal("json-1.3c", rows[0].get_string(1), "Alice", "metadata->>'$.name' unquoted is Alice")
    h.assert_equal("json-1.3d", rows[0].get_string(2), "New York", "json_extract city is New York")
    h.assert_equal_int("json-1.3e", rows[0].get_int(3), 2, "tag_count is 2")

    # 5. Test JSON quoted arrow (->)
    cur.execute("SELECT metadata->'$.name' FROM users WHERE id = 1")
    r = cur.fetchone()
    h.assert_equal("json-1.4", r.value().get_string(0), "\"Alice\"", "metadata->'$.name' returns quoted \"Alice\"")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 25 - JSON Functions & Path Operators")
    run_json_tests(h)
    h.summary()
