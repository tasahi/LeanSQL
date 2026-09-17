"""LeanSQL Complete C-ABI Interface & Diagnostics Contexts.
Corresponds to SQLite3 C ABI data structures and entrypoints.
"""

from std.ffi import c_char, c_int, c_double
from std.memory import Pointer
from src.core.types import *
from src.engine.connection import connect, Connection, Cursor
from src.engine.row import Row, Value
from src.engine.vtab import VirtualTableModule


comptime VERSION_CSTR = "3.45.0 (LeanSQL Pure-Mojo Engine)"
comptime SOURCEID_CSTR = "2026-08-20 pure-mojo-leansql"


struct CStatementContext(Copyable, Movable):
    var sql: String
    var rows: List[Row]
    var col_names: List[String]
    var cur_row_idx: Int
    var is_done: Bool
    var last_err: String

    def __init__(out self, sql: String):
        self.sql = sql
        self.rows = List[Row]()
        self.col_names = List[String]()
        self.cur_row_idx = -1
        self.is_done = False
        self.last_err = ""

    def __moveinit__(out self, mut existing: Self):
        self.sql = existing.sql^
        self.rows = existing.rows^
        self.col_names = existing.col_names^
        self.cur_row_idx = existing.cur_row_idx
        self.is_done = existing.is_done
        self.last_err = existing.last_err^

    def __copyinit__(out self, existing: Self):
        self.sql = existing.sql
        self.rows = existing.rows.copy()
        self.col_names = existing.col_names.copy()
        self.cur_row_idx = existing.cur_row_idx
        self.is_done = existing.is_done
        self.last_err = existing.last_err

    def step(mut self) -> Int:
        if self.is_done:
            return SQLITE_DONE
        self.cur_row_idx += 1
        if self.cur_row_idx < len(self.rows):
            return SQLITE_ROW
        else:
            self.is_done = True
            return SQLITE_DONE

    def reset(mut self):
        self.cur_row_idx = -1
        self.is_done = False

    def column_count(self) -> Int:
        if self.cur_row_idx >= 0 and self.cur_row_idx < len(self.rows):
            return len(self.rows[self.cur_row_idx].values)
        return len(self.col_names)

    def column_type(self, col: Int) -> Int:
        if self.cur_row_idx < 0 or self.cur_row_idx >= len(self.rows):
            return SQLITE_NULL
        if col < 0 or col >= len(self.rows[self.cur_row_idx].values):
            return SQLITE_NULL
        return self.rows[self.cur_row_idx].values[col].type_tag

    def column_int64(self, col: Int) -> Int64:
        if self.cur_row_idx < 0 or self.cur_row_idx >= len(self.rows):
            return 0
        if col < 0 or col >= len(self.rows[self.cur_row_idx].values):
            return 0
        return self.rows[self.cur_row_idx].values[col].to_int()

    def column_double(self, col: Int) -> Float64:
        if self.cur_row_idx < 0 or self.cur_row_idx >= len(self.rows):
            return 0.0
        if col < 0 or col >= len(self.rows[self.cur_row_idx].values):
            return 0.0
        return self.rows[self.cur_row_idx].values[col].to_float()

    def column_text(self, col: Int) -> String:
        if self.cur_row_idx < 0 or self.cur_row_idx >= len(self.rows):
            return ""
        if col < 0 or col >= len(self.rows[self.cur_row_idx].values):
            return ""
        return self.rows[self.cur_row_idx].values[col].to_string()


struct CDatabaseContext(Copyable, Movable):
    var con: Connection
    var last_err: String
    var err_code: Int

    def __init__(out self, db_path: String) raises:
        self.con = connect(db_path)
        self.last_err = "not an error"
        self.err_code = SQLITE_OK

    def __moveinit__(out self, mut existing: Self):
        self.con = existing.con^
        self.last_err = existing.last_err^
        self.err_code = existing.err_code

    def __copyinit__(out self, existing: Self):
        self.con = existing.con.copy()
        self.last_err = existing.last_err
        self.err_code = existing.err_code

    def prepare(mut self, sql: String) raises -> CStatementContext:
        var stmt = CStatementContext(sql)
        var cur = self.con.cursor()
        cur.execute(sql)
        stmt.rows = cur.fetchall()
        if len(stmt.rows) > 0:
            for c in range(len(stmt.rows[0].col_names)):
                stmt.col_names.append(stmt.rows[0].col_names[c])
        return stmt^

    def changes(self) -> Int:
        return self.con.changes()

    def total_changes(self) -> Int:
        return self.con.total_changes()

    def last_insert_rowid(self) -> Int64:
        return self.con.last_insert_rowid()

    def load_extension(mut self, path: String, entrypoint: String = "sqlite3_extension_init") -> Int:
        try:
            self.con.load_extension(path, entrypoint)
            self.err_code = SQLITE_OK
            self.last_err = "not an error"
            return SQLITE_OK
        except e:
            self.err_code = SQLITE_ERROR
            self.last_err = String(e)
            return SQLITE_ERROR

    def register_function(mut self, name: String, f: def(List[Value]) thin -> Value) -> Int:
        self.con.register_function(name, f)
        self.err_code = SQLITE_OK
        return SQLITE_OK

    def register_vtab_module(mut self, name: String, mod: VirtualTableModule) -> Int:
        self.con.register_module(name, mod)
        self.err_code = SQLITE_OK
        return SQLITE_OK


def sqlite3_libversion() -> String:
    return VERSION_CSTR


def sqlite3_sourceid() -> String:
    return SOURCEID_CSTR


def sqlite3_libversion_number() -> Int:
    return 3045000
