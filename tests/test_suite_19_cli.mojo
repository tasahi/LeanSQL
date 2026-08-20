from tests.harness import TestHarness
from src.cli import ShellState, MODE_LIST, MODE_COLUMN, MODE_CSV, MODE_LINE


def run_cli_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 19: Interactive CLI Shell & Dot Commands  ===")
    print("=======================================================")
    var shell = ShellState(":memory:")

    # 1. Setup sample tables and data
    _ = shell.execute_sql("CREATE TABLE users (id INT, name TEXT, role TEXT)")
    _ = shell.execute_sql("INSERT INTO users VALUES (1, 'Alice', 'Admin')")
    _ = shell.execute_sql("INSERT INTO users VALUES (2, 'Bob', 'Engineer')")

    # 2. .tables
    var tbls = shell.handle_dot_command(".tables")
    h.assert_equal("cli-1.1", tbls, "users", ".tables lists table 'users'")

    # 3. .schema
    var schema = shell.handle_dot_command(".schema")
    h.assert_true("cli-1.2", "CREATE TABLE users" in schema, ".schema contains CREATE TABLE statement")

    # 4. Output Mode: MODE_LIST with pipe separator
    _ = shell.handle_dot_command(".mode list")
    _ = shell.handle_dot_command(".separator |")
    var list_out = shell.execute_sql("SELECT * FROM users ORDER BY id")
    h.assert_true("cli-1.3a", "1|Alice|Admin" in list_out, "List mode formats Alice with pipe")
    h.assert_true("cli-1.3b", "2|Bob|Engineer" in list_out, "List mode formats Bob with pipe")

    # 5. Output Mode: MODE_CSV
    _ = shell.handle_dot_command(".mode csv")
    var csv_out = shell.execute_sql("SELECT * FROM users ORDER BY id")
    h.assert_true("cli-1.4", '1,"Alice","Admin"' in csv_out, "CSV mode formats rows with quotes and commas")

    # 6. Output Mode: MODE_LINE
    _ = shell.handle_dot_command(".mode line")
    var line_out = shell.execute_sql("SELECT name, role FROM users WHERE id = 1")
    h.assert_true("cli-1.5a", "name = Alice" in line_out, "Line mode formats name = Alice")
    h.assert_true("cli-1.5b", "role = Admin" in line_out, "Line mode formats role = Admin")

    # 7. .dump database
    var dump_out = shell.handle_dot_command(".dump")
    h.assert_true("cli-1.6a", "BEGIN TRANSACTION;" in dump_out, "Dump starts with transaction")
    h.assert_true("cli-1.6b", "INSERT INTO users VALUES(1,'Alice','Admin');" in dump_out, "Dump generates insert for Alice")
    h.assert_true("cli-1.6c", "COMMIT;" in dump_out, "Dump ends with commit")

    # 8. .help & .quit
    var help_out = shell.handle_dot_command(".help")
    h.assert_true("cli-1.7", ".tables" in help_out, ".help displays command catalogue")

    _ = shell.handle_dot_command(".quit")
    h.assert_true("cli-1.8", shell.should_exit, ".quit sets should_exit flag to True")


def main() raises:
    var h = TestHarness("Suite 19: CLI Shell")
    run_cli_tests(h)
    h.summary()
