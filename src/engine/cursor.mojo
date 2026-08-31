""" SQLite Cursor for Pure Mojo Engine.

Implements query result iteration and cursor navigation matching Python DB-API 2.0 / sqlite3.
"""

from src.core.types import *
from src.engine.row import Value, Row


struct Cursor(ImplicitlyCopyable, Copyable, Movable):
    """ Manages iteration over SQL query results in pure Mojo."""
    var _rows: List[Row]
    var _idx: Int
    var _col_names: List[String]
    var rowcount: Int
    var lastrowid: Int64

    def __init__(out self, rows: List[Row], col_names: List[String], rowcount: Int = -1, lastrowid: Int64 = 0):
        self._rows = rows.copy()
        self._idx = 0
        self._col_names = col_names.copy()
        self.rowcount = rowcount
        self.lastrowid = lastrowid

    def __init__(out self, *, copy: Self):
        self._rows = copy._rows.copy()
        self._idx = copy._idx
        self._col_names = copy._col_names.copy()
        self.rowcount = copy.rowcount
        self.lastrowid = copy.lastrowid

    def __init__(out self, *, deinit move: Self):
        self._rows = move._rows^
        self._idx = move._idx
        self._col_names = move._col_names^
        self.rowcount = move.rowcount
        self.lastrowid = move.lastrowid

    def fetchone(mut self) -> Optional[Row]:
        """ Fetches the next row in the result set, or None if exhausted."""
        if self._idx >= 0 and self._idx < len(self._rows):
            var row = self._rows[self._idx].copy()
            self._idx += 1
            return Optional(row^)
        return None

    def fetchall(mut self) -> List[Row]:
        """ Fetches all remaining rows in the result set."""
        var res = List[Row]()
        while self._idx < len(self._rows):
            res.append(self._rows[self._idx].copy())
            self._idx += 1
        return res^

    def column_names(self) -> List[String]:
        """ Returns the projected column names of the query."""
        return self._col_names.copy()

    def close(mut self):
        """ Releases cursor buffered rows."""
        self._rows = List[Row]()
        self._idx = 0
