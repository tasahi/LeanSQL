"""SQLite Error Validation and Exception Helpers."""

from src.core.types import *
from src.interop.c_api import c_sqlite3_errmsg, c_sqlite3_errcode


def check_rc(rc: Int, db: C_Db) raises:
    """Verifies a return code. Raises an Error if rc is not OK, ROW, or DONE."""
    if rc != SQLITE_OK and rc != SQLITE_ROW and rc != SQLITE_DONE:
        var msg = c_sqlite3_errmsg(db)
        raise Error("SQLite error (" + String(rc) + "): " + msg)


def check_rc_stmt(rc: Int, db: C_Db, sql: String) raises:
    """Verifies a statement preparation return code."""
    if rc != SQLITE_OK:
        var msg = c_sqlite3_errmsg(db)
        raise Error("SQLite prepare error for [" + sql + "] (" + String(rc) + "): " + msg)
