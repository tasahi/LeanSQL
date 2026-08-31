"""LeanSQL Python Driver — Drop-in replacement for standard library `sqlite3`.
Backed by the 100% pure-Mojo database engine compiled into `leansql.so`.
"""

import ctypes
import os
from typing import Any, List, Optional, Tuple, Union


# Find and load the native shared library
_LIB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "leansql.so")
if not os.path.exists(_LIB_PATH):
    # Try current working directory
    _LIB_PATH = os.path.abspath("leansql.so")

try:
    _lib = ctypes.CDLL(_LIB_PATH)
except Exception as e:
    _lib = None


# Types
SQLITE_OK = 0
SQLITE_ROW = 100
SQLITE_DONE = 101

SQLITE_INTEGER = 1
SQLITE_FLOAT = 2
SQLITE_TEXT = 3
SQLITE_BLOB = 4
SQLITE_NULL = 5


class Error(Exception):
    """Base exception for LeanSQL errors."""
    pass


class OperationalError(Error):
    pass


class IntegrityError(Error):
    pass


if _lib is not None:
    # Setup C function prototypes
    _lib.sqlite3_libversion.restype = ctypes.c_char_p
    _lib.sqlite3_sourceid.restype = ctypes.c_char_p
    _lib.sqlite3_libversion_number.restype = ctypes.c_int

    _lib.sqlite3_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    _lib.sqlite3_open.restype = ctypes.c_int

    _lib.sqlite3_close.argtypes = [ctypes.c_void_p]
    _lib.sqlite3_close.restype = ctypes.c_int

    _lib.sqlite3_prepare_v2.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_void_p),
        ctypes.POINTER(ctypes.c_char_p),
    ]
    _lib.sqlite3_prepare_v2.restype = ctypes.c_int

    _lib.sqlite3_step.argtypes = [ctypes.c_void_p]
    _lib.sqlite3_step.restype = ctypes.c_int

    _lib.sqlite3_finalize.argtypes = [ctypes.c_void_p]
    _lib.sqlite3_finalize.restype = ctypes.c_int

    _lib.sqlite3_reset.argtypes = [ctypes.c_void_p]
    _lib.sqlite3_reset.restype = ctypes.c_int

    _lib.sqlite3_column_count.argtypes = [ctypes.c_void_p]
    _lib.sqlite3_column_count.restype = ctypes.c_int

    _lib.sqlite3_column_type.argtypes = [ctypes.c_void_p, ctypes.c_int]
    _lib.sqlite3_column_type.restype = ctypes.c_int

    _lib.sqlite3_column_name.argtypes = [ctypes.c_void_p, ctypes.c_int]
    _lib.sqlite3_column_name.restype = ctypes.c_char_p

    _lib.sqlite3_column_int64.argtypes = [ctypes.c_void_p, ctypes.c_int]
    _lib.sqlite3_column_int64.restype = ctypes.c_int64

    _lib.sqlite3_column_double.argtypes = [ctypes.c_void_p, ctypes.c_int]
    _lib.sqlite3_column_double.restype = ctypes.c_double

    _lib.sqlite3_column_text.argtypes = [ctypes.c_void_p, ctypes.c_int]
    _lib.sqlite3_column_text.restype = ctypes.c_char_p

    _lib.sqlite3_errmsg.argtypes = [ctypes.c_void_p]
    _lib.sqlite3_errmsg.restype = ctypes.c_char_p

    _lib.sqlite3_changes.argtypes = [ctypes.c_void_p]
    _lib.sqlite3_changes.restype = ctypes.c_int

    _lib.sqlite3_total_changes.argtypes = [ctypes.c_void_p]
    _lib.sqlite3_total_changes.restype = ctypes.c_int

    _lib.sqlite3_last_insert_rowid.argtypes = [ctypes.c_void_p]
    _lib.sqlite3_last_insert_rowid.restype = ctypes.c_int64


def sqlite_version() -> str:
    """Returns the LeanSQL SQLite library version."""
    if _lib:
        return _lib.sqlite3_libversion().decode("utf-8")
    return "3.45.0"


class Cursor:
    def __init__(self, connection: "Connection"):
        self.connection = connection
        self._stmt = None
        self.description: Optional[List[Tuple[str, Any, Any, Any, Any, Any, Any]]] = None
        self.rowcount: int = -1

    def execute(self, sql: str, parameters: Optional[Union[tuple, list]] = None) -> "Cursor":
        if self._stmt:
            _lib.sqlite3_finalize(self._stmt)
            self._stmt = None

        if parameters:
            # Bind parameters via basic string substitution if provided
            for p in parameters:
                if isinstance(p, str):
                    sql = sql.replace("?", f"'{p}'", 1)
                elif p is None:
                    sql = sql.replace("?", "NULL", 1)
                else:
                    sql = sql.replace("?", str(p), 1)

        stmt_ptr = ctypes.c_void_p()
        tail_ptr = ctypes.c_char_p()
        rc = _lib.sqlite3_prepare_v2(
            self.connection._db,
            sql.encode("utf-8"),
            -1,
            ctypes.byref(stmt_ptr),
            ctypes.byref(tail_ptr),
        )
        if rc != SQLITE_OK:
            err = _lib.sqlite3_errmsg(self.connection._db).decode("utf-8")
            raise OperationalError(f"{err} (SQL: {sql})")

        self._stmt = stmt_ptr
        col_count = _lib.sqlite3_column_count(self._stmt)
        if col_count > 0:
            self.description = []
            for i in range(col_count):
                c_name = _lib.sqlite3_column_name(self._stmt, i)
                name_str = c_name.decode("utf-8") if c_name else f"col_{i}"
                self.description.append((name_str, None, None, None, None, None, None))
        else:
            self.description = None
            # DML statements step immediately
            step_rc = _lib.sqlite3_step(self._stmt)
            self.rowcount = _lib.sqlite3_changes(self.connection._db)

        return self

    def executemany(self, sql: str, seq_of_parameters: list) -> "Cursor":
        for params in seq_of_parameters:
            self.execute(sql, params)
        return self

    def fetchone(self) -> Optional[Tuple]:
        if not self._stmt:
            return None
        rc = _lib.sqlite3_step(self._stmt)
        if rc == SQLITE_ROW:
            col_count = _lib.sqlite3_column_count(self._stmt)
            row = []
            for i in range(col_count):
                t = _lib.sqlite3_column_type(self._stmt, i)
                if t == SQLITE_INTEGER:
                    row.append(_lib.sqlite3_column_int64(self._stmt, i))
                elif t == SQLITE_FLOAT:
                    row.append(_lib.sqlite3_column_double(self._stmt, i))
                elif t == SQLITE_TEXT:
                    txt = _lib.sqlite3_column_text(self._stmt, i)
                    row.append(txt.decode("utf-8") if txt else "")
                elif t == SQLITE_NULL:
                    row.append(None)
                else:
                    row.append(None)
            return tuple(row)
        elif rc == SQLITE_DONE:
            return None
        else:
            err = _lib.sqlite3_errmsg(self.connection._db).decode("utf-8")
            raise OperationalError(err)

    def fetchall(self) -> List[Tuple]:
        rows = []
        while True:
            r = self.fetchone()
            if r is None:
                break
            rows.append(r)
        return rows

    def close(self):
        if self._stmt:
            _lib.sqlite3_finalize(self._stmt)
            self._stmt = None


class Connection:
    def __init__(self, database: str):
        if _lib is None:
            raise OperationalError("Could not load native leansql.so library.")
        self.database = database
        self._db = ctypes.c_void_p()
        rc = _lib.sqlite3_open(database.encode("utf-8"), ctypes.byref(self._db))
        if rc != SQLITE_OK:
            raise OperationalError(f"Cannot open database: {database}")

    def cursor(self) -> Cursor:
        return Cursor(self)

    def execute(self, sql: str, parameters: Optional[Union[tuple, list]] = None) -> Cursor:
        cur = self.cursor()
        return cur.execute(sql, parameters)

    def commit(self):
        self.execute("COMMIT")

    def rollback(self):
        self.execute("ROLLBACK")

    @property
    def total_changes(self) -> int:
        return _lib.sqlite3_total_changes(self._db)

    def close(self):
        if self._db:
            _lib.sqlite3_close(self._db)
            self._db = None


def connect(database: str) -> Connection:
    """Connects to a SQLite database file or :memory: in pure Mojo."""
    return Connection(database)
