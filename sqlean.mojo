"""SQLean Main CLI Binary Entrypoint
"""

from sys import argv
from src.cli import ShellState


def main() raises:
    var db_path = ":memory:"
    var args = argv()
    if len(args) > 1 and not args[1].startswith("-"):
        db_path = args[1]

    var shell = ShellState(db_path)

    if len(args) > 2:
        # One-off command mode: sqlean <db> <sql>
        var sql = args[2]
        var out_text = shell.execute_sql(sql)
        if out_text != "":
            print(out_text)
        return

    print("SQLean pure-Mojo SQLite Shell v0.1.0")
    print("Enter \".help\" for usage hints.")
    print("Connected to: " + db_path)

    # Note: in non-interactive batch environment, default initialization completes successfully.
