from src.core.hash import str_hash


def test_string_hashing() raises:
    print("=== Testing SQLite Multiplicative String Hash ===")
    
    # 1. Identifiers
    var h1 = str_hash("table")
    var h2 = str_hash("TABLE")
    var h3 = str_hash("Table")
    print("  'table':", h1, "| 'TABLE':", h2, "| 'Table':", h3)
    if h1 != h2 or h2 != h3:
        raise Error("Case-folding hash failed for table/TABLE/Table")

    var h_user = str_hash("users")
    var h_post = str_hash("posts")
    print("  'users':", h_user, "| 'posts':", h_post)
    if h_user == h_post:
        raise Error("Distinct identifiers produced colliding hash unexpectedly")

    print("String hash test passed!")


def main() raises:
    test_string_hashing()
