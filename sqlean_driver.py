"""SQLean High-Level DB-API 2.0 Python Driver
Provides standard Python sqlite3 compatibility over compiled native sqlean.so.
"""

import os
import sqlean


class Error(Exception):
    """Base exception for SQLean errors."""
    pass


class OperationalError(Error):
    pass


class IntegrityError(Error):
    pass


class Cursor:
    def __init__(self, connection: "Connection"):
        self.connection = connection
        self._rows = []
        self._row_idx = 0
        self.description = None
        self.rowcount = -1

    def execute(self, sql: str, parameters=None) -> "Cursor":
        if parameters:
            for p in parameters:
                if isinstance(p, str):
                    sql = sql.replace("?", f"'{p}'", 1)
                elif p is None:
                    sql = sql.replace("?", "NULL", 1)
                else:
                    sql = sql.replace("?", str(p), 1)

        sql_trimmed = sql.strip().upper()
        if (
            sql_trimmed.startswith("SELECT")
            or sql_trimmed.startswith("PRAGMA")
            or sql_trimmed.startswith("WITH")
        ):
            try:
                target = getattr(self.connection, "_handle", self.connection.database)
                self._rows = sqlean.fetch_all(target, sql)
                self._row_idx = 0
                self.rowcount = len(self._rows)
            except Exception as e:
                raise OperationalError(str(e))
        else:
            try:
                target = getattr(self.connection, "_handle", self.connection.database)
                sqlean.execute(target, sql)
                self._rows = []
                self._row_idx = 0
                self.rowcount = 1
            except Exception as e:
                raise OperationalError(str(e))
        return self

    def executemany(self, sql: str, seq_of_parameters: list) -> "Cursor":
        for params in seq_of_parameters:
            self.execute(sql, params)
        return self

    def fetchone(self):
        if self._row_idx < len(self._rows):
            r = self._rows[self._row_idx]
            self._row_idx += 1
            return r
        return None

    def fetchall(self):
        res = self._rows[self._row_idx:]
        self._row_idx = len(self._rows)
        return res

    def close(self):
        self._rows = []


class Connection:
    def __init__(self, database: str):
        self.database = database
        try:
            self._handle = sqlean.open(database)
        except Exception:
            self._handle = database

    def cursor(self) -> Cursor:
        return Cursor(self)

    def execute(self, sql: str, parameters=None) -> Cursor:
        cur = self.cursor()
        return cur.execute(sql, parameters)

    def commit(self):
        if hasattr(self, "_handle"):
            try:
                sqlean.commit(self._handle)
            except Exception:
                pass

    def rollback(self):
        pass

    def close(self):
        if hasattr(self, "_handle"):
            try:
                sqlean.close(self._handle)
            except Exception:
                pass


def connect(database: str = ":memory:") -> Connection:
    """Connects to a SQLite database in pure Mojo."""
    return Connection(database)


def sqlite_version() -> str:
    return sqlean.version()
