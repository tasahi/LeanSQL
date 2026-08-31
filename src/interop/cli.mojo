"""LeanSQL Interactive Command-Line Interface (CLI Shell)
Pure Mojo implementation of the SQLite CLI shell and REPL.
"""

from src.engine.connection import connect, Connection, Cursor
from src.engine.row import Row, Value
from src.vfs.vfs_os import VFS


comptime MODE_LIST = 0
comptime MODE_COLUMN = 1
comptime MODE_CSV = 2
comptime MODE_LINE = 3


struct ShellState:
    var con: Connection
    var mode: Int
    var show_headers: Bool
    var show_timer: Bool
    var separator: String
    var null_value: String
    var should_exit: Bool

    def __init__(out self, db_path: String = ":memory:") raises:
        self.con = connect(db_path)
        self.mode = MODE_LIST
        self.show_headers = False
        self.show_timer = False
        self.separator = "|"
        self.null_value = ""
        self.should_exit = False

    def handle_dot_command(mut self, cmd_line: String) raises -> String:
        """Processes a dot command (e.g. .tables, .schema, .mode, .help)."""
        var line = String(cmd_line.strip())
        if line == ".quit" or line == ".exit":
            self.should_exit = True
            return "Exiting."

        if line == ".help":
            var help_text = String()
            help_text += ".dump ?TABLE? ...      Render database content as SQL\n"
            help_text += ".headers on|off         Turn display of headers on or off\n"
            help_text += ".help                   Show this message\n"
            help_text += ".mode MODE              Set output mode (list, column, csv, line)\n"
            help_text += ".nullvalue STRING       Use STRING in place of NULL values\n"
            help_text += ".quit / .exit           Exit this program\n"
            help_text += ".read FILENAME          Execute SQL in FILENAME\n"
            help_text += ".schema ?PATTERN?       Show the CREATE statements matching PATTERN\n"
            help_text += ".separator STRING       Change separator used by output mode and .import\n"
            help_text += ".tables ?PATTERN?       List names of tables matching PATTERN\n"
            help_text += ".timer on|off           Turn SQL timer on or off\n"
            return help_text

        if line.startswith(".mode"):
            var parts = line.split()
            if len(parts) >= 2:
                var m = parts[1].lower()
                if m == "list":
                    self.mode = MODE_LIST
                elif m == "column":
                    self.mode = MODE_COLUMN
                elif m == "csv":
                    self.mode = MODE_CSV
                elif m == "line":
                    self.mode = MODE_LINE
            return ""

        if line.startswith(".headers"):
            var parts = line.split()
            if len(parts) >= 2:
                var h = parts[1].lower()
                self.show_headers = (h == "on" or h == "yes" or h == "1")
            return ""

        if line.startswith(".timer"):
            var parts = line.split()
            if len(parts) >= 2:
                var t = parts[1].lower()
                self.show_timer = (t == "on" or t == "yes" or t == "1")
            return ""

        if line.startswith(".separator"):
            var parts = line.split()
            if len(parts) >= 2:
                self.separator = String(parts[1])
            return ""

        if line.startswith(".nullvalue"):
            var parts = line.split()
            if len(parts) >= 2:
                self.null_value = String(parts[1])
            return ""

        if line.startswith(".tables"):
            var cur = self.con.cursor()
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            var rows = cur.fetchall()
            var out_str = String()
            for i in range(len(rows)):
                if i > 0:
                    out_str += "  "
                out_str += rows[i].get_string(0)
            return out_str

        if line.startswith(".schema"):
            var parts = line.split()
            var sql = "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL"
            if len(parts) >= 2:
                sql += " AND name = '" + String(parts[1]) + "'"
            sql += " ORDER BY type, name"
            var cur = self.con.cursor()
            cur.execute(sql)
            var rows = cur.fetchall()
            var out_str = String()
            for i in range(len(rows)):
                if i > 0:
                    out_str += "\n"
                out_str += rows[i].get_string(0) + ";"
            return out_str

        if line.startswith(".dump"):
            var cur = self.con.cursor()
            var dump_str = String()
            dump_str += "PRAGMA foreign_keys=OFF;\nBEGIN TRANSACTION;\n"
            cur.execute("SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name")
            var tbl_rows = cur.fetchall()
            for t_i in range(len(tbl_rows)):
                var tbl_name = tbl_rows[t_i].get_string(0)
                var tbl_sql = tbl_rows[t_i].get_string(1)
                dump_str += tbl_sql + ";\n"

                var d_cur = self.con.cursor()
                d_cur.execute("SELECT * FROM " + tbl_name)
                var data_rows = d_cur.fetchall()
                for r_i in range(len(data_rows)):
                    var r = data_rows[r_i]
                    dump_str += "INSERT INTO " + tbl_name + " VALUES("
                    for c_i in range(len(r.values)):
                        if c_i > 0:
                            dump_str += ","
                        var v = r.values[c_i]
                        if v.is_null():
                            dump_str += "NULL"
                        elif v.type_tag == 3: # TEXT
                            dump_str += "'" + v.text_val + "'"
                        else:
                            dump_str += v.to_string()
                    dump_str += ");\n"
            dump_str += "COMMIT;\n"
            return dump_str

        if line.startswith(".read"):
            var parts = line.split()
            if len(parts) >= 2:
                var file_path = String(parts[1])
                var vfs = VFS()
                if not vfs.file_exists(file_path):
                    return "Error: cannot open " + file_path
                var f = vfs.open_disk(file_path, read_only=True, create=False)
                var sz = f.file_size()
                var buf = List[UInt8]()
                for _ in range(Int(sz)):
                    buf.append(0)
                _ = f.read(0, Int(sz), buf.unsafe_ptr())
                f.close()

                var script_str = String()
                for i in range(len(buf)):
                    script_str += chr(Int(buf[i]))

                # Execute statement by statement
                var stmts = script_str.split(";")
                for s_i in range(len(stmts)):
                    var stmt_text = String(stmts[s_i].strip())
                    if stmt_text != "":
                        _ = self.execute_sql(stmt_text)
                return "Executed script " + file_path
            return "Error: missing filename for .read"

        return "Error: unknown command: " + line

    def execute_sql(mut self, sql: String) raises -> String:
        """Executes an SQL statement and formats output according to current shell mode."""
        var cur = self.con.cursor()
        cur.execute(sql)
        var rows = cur.fetchall()

        if len(rows) == 0:
            return ""

        var out_res = String()

        # 1. MODE_LIST
        if self.mode == MODE_LIST:
            if self.show_headers and len(rows) > 0:
                for c in range(len(rows[0].col_names)):
                    if c > 0:
                        out_res += self.separator
                    out_res += rows[0].col_names[c]
                out_res += "\n"

            for r in range(len(rows)):
                for c in range(len(rows[r].values)):
                    if c > 0:
                        out_res += self.separator
                    var v = rows[r].values[c]
                    out_res += self.null_value if v.is_null() else v.to_string()
                out_res += "\n"

        # 2. MODE_CSV
        elif self.mode == MODE_CSV:
            if self.show_headers and len(rows) > 0:
                for c in range(len(rows[0].col_names)):
                    if c > 0:
                        out_res += ","
                    out_res += rows[0].col_names[c]
                out_res += "\n"

            for r in range(len(rows)):
                for c in range(len(rows[r].values)):
                    if c > 0:
                        out_res += ","
                    var v = rows[r].values[c]
                    if v.is_null():
                        out_res += self.null_value
                    elif v.type_tag == 3: # TEXT
                        out_res += '"' + v.text_val + '"'
                    else:
                        out_res += v.to_string()
                out_res += "\n"

        # 3. MODE_LINE
        elif self.mode == MODE_LINE:
            for r in range(len(rows)):
                for c in range(len(rows[r].values)):
                    var col = rows[r].col_names[c] if c < len(rows[r].col_names) else "col"
                    var v = rows[r].values[c]
                    var val_s = self.null_value if v.is_null() else v.to_string()
                    out_res += col + " = " + val_s + "\n"
                if r + 1 < len(rows):
                    out_res += "\n"

        # 4. MODE_COLUMN
        elif self.mode == MODE_COLUMN:
            var num_cols = len(rows[0].values)
            var col_widths = List[Int]()
            for c in range(num_cols):
                var max_w = rows[0].col_names[c].byte_length() if (self.show_headers and c < len(rows[0].col_names)) else 0
                for r in range(len(rows)):
                    var val_len = self.null_value.byte_length() if rows[r].values[c].is_null() else rows[r].values[c].to_string().byte_length()
                    if val_len > max_w:
                        max_w = val_len
                col_widths.append(max_w)

            if self.show_headers:
                for c in range(num_cols):
                    var cname = rows[0].col_names[c] if c < len(rows[0].col_names) else ""
                    out_res += cname
                    for _ in range(col_widths[c] - cname.byte_length() + 2):
                        out_res += " "
                out_res += "\n"
                for c in range(num_cols):
                    for _ in range(col_widths[c]):
                        out_res += "-"
                    out_res += "  "
                out_res += "\n"

            for r in range(len(rows)):
                for c in range(num_cols):
                    var v = rows[r].values[c]
                    var s = self.null_value if v.is_null() else v.to_string()
                    out_res += s
                    if c + 1 < num_cols:
                        for _ in range(col_widths[c] - s.byte_length() + 2):
                            out_res += " "
                out_res += "\n"

        return String(out_res.strip())
