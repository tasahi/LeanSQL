# SQLite to Mojo Translation Roadmap & Pythonic Client API Proposal

## 1. Executive Summary & Strategy

Porting SQLite from C to Mojo is a large-scale systems engineering project. To maintain continuous reliability and achieve high developer velocity, the migration follows an **incremental, bottom-up hybrid approach** guided by two core principles:

1. **Pythonic Mojo API First (Stage 0):** Establish an ergonomic, high-level client interface adhering to Python's [`sqlite3` standard library specification](https://docs.python.org/3/library/sqlite3.html) using Mojo 1.0 `def` syntax. This immediately delivers an operational SQLite client in Mojo via C FFI.
2. **Subsystem-by-Subsystem Transscription with Differential Verification:** As each C subsystem (primitives, page codecs, VFS, B-Tree, VDBE, parser) is rewritten in Mojo, it is validated both through low-level differential testing against C SQLite and top-down through the high-level Mojo `sqlite3` API.

---

## 2. Target Mojo 1.0 API Design (`sqlite3.mojo`)

The user-facing API mirrors the familiar Python `sqlite3` interface while taking advantage of Mojo's native speed and memory control.

```mojo
import sqlite3

def main() raises:
    # 1. Connect to database (in-memory or file)
    var con = sqlite3.connect(":memory:")
    var cur = con.cursor()

    # 2. Schema creation and data insertion
    cur.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
    cur.execute("INSERT INTO users VALUES (1, 'Alice', 95.5)")
    cur.execute("INSERT INTO users VALUES (2, 'Bob', 88.0)")
    con.commit()

    # 3. Parameterized Querying & Fetching
    cur.execute("SELECT id, name, score FROM users WHERE score > ?", (90.0,))
    var row = cur.fetchone()
    if row:
        print("Found:", row.value().get_int(0), row.value().get_string(1))

    cur.close()
    con.close()
```

---

## 3. Translation Stages & Mojo Testing Matrix

```
+-----------------------------------------------------------------------------------+
|                        Mojo User Code (sqlite3 API)                               |
|              con = sqlite3.connect(...) -> cur.execute(...) -> cur.fetchall()     |
+-----------------------------------------------------------------------------------+
                                         |
    +------------------------------------+------------------------------------+
    | Stage 0-2: FFI Shell + Mojo Codecs | Stage 3-5: Mojo VFS / Pager / B-Tree|
    | (Dual testing against C SQLite)    | (Direct functional query testing)  |
    +------------------------------------+------------------------------------+
```

| Stage | Subsystem | Source in `/sqlite/src` | Mojo Integration Strategy | Mojo Testing & Verification Strategy |
| :--- | :--- | :--- | :--- | :--- |
| **0** | **C-FFI Bridge & Client Shell** | `sqlite3.c`, `sqlite.h.in` | Wrap C `sqlite3_*` functions via Mojo `sys.ffi.DLHandle`. | **Baseline Suite:** Port Python's `test_sqlite3.py` to Mojo to ensure complete baseline client compatibility. |
| **1** | **Low-Level Primitives** | `util.c`, `utf.c`, `hash.c`, `bitvec.c` | Pure Mojo implementations of Varint codecs, UTF string helpers, and hash structures. | **Differential Fuzzing:** Insert/query boundary values (64-bit varints, UTF-8 sequences) via `con.execute()` and assert Mojo codecs produce identical byte representations to C. |
| **2** | **Page Formats & Record Codecs** | `btreeInt.h`, `vdbemem.c`, `btree.c` | SIMD-accelerated payload unpacking for SQLite Serial Types (0–14). | **Row Extraction Tests:** Execute queries across wide tables with 100+ mixed columns, comparing Mojo SIMD unpacked tuples against `cur.fetchall()`. |
| **3** | **OS Interface (VFS) & Pager** | `os.c`, `os_unix.c`, `pager.c`, `wal.c` | Custom Mojo VFS registered via `sqlite3_vfs_register` and Pager state machine. | **ACID & Concurrency Tests:** Run transactions, rollback tests (`con.rollback()`), WAL checkpoints, and lock contention on real `.db` files from Mojo. |
| **4** | **B-Tree Engine & Cursors** | `btree.c`, `btree.h` | Mojo B-Tree mounted under the C VDBE engine. | **Large Dataset Iterations:** Test index traversal, page splits, balance operations, and range scans via `cur.execute("SELECT ... WHERE key BETWEEN ? AND ?")`. |
| **5** | **VDBE Engine & Opcodes** | `vdbe.c`, `vdbeaux.c`, `vdbesort.c` | Mojo bytecode interpreter dispatch loop and SIMD vectorized operators. | **Query & Aggregation Benchmarks:** Test complex queries, joins, sorting, and vectorized aggregates (`SUM`, `AVG`, `COUNT`) via `cur.execute()`. |
| **6** | **SQL Parser & Planner** | `tokenize.c`, `parse.y`, `select.c`, `where.c` | Native Mojo lexer and AST parser emitting VDBE bytecode. | **End-to-End Dialect Tests:** Run complex SQL statements directly through `con.execute()` without using the legacy Lemon C parser. |
| **7** | **Pure Mojo Standalone Engine** | All components in pure Mojo | Standalone Mojo database engine exposing C ABI `@export` compatibility. | **Full SQLite Test Suite:** Run SQL Logic Tests (SLT) and official TCL test fixture suites directly against the pure Mojo build. |

---

## 4. Blueprint Implementation: Stage 0 Mojo C-FFI Wrapper

Below is the initial structure for `sqlite3.mojo` implementing the core client interface using Mojo 1.0 syntax:

```mojo
from sys.ffi import DLHandle, UnsafePointer, c_char, c_int, c_double, c_int64

# SQLite Return Codes
alias SQLITE_OK = 0
alias SQLITE_ROW = 100
alias SQLITE_DONE = 101

# Type aliases for opaque C pointers
alias C_Db = UnsafePointer[NoneType]
alias C_Stmt = UnsafePointer[NoneType]

struct Row:
    var _stmt: C_Stmt
    var _lib: DLHandle

    def __init__(out self, stmt: C_Stmt, lib: DLHandle):
        self._stmt = stmt
        self._lib = lib

    def get_int(self, col: Int) -> Int:
        var fn_int = self._lib.get_function[def(C_Stmt, c_int) -> c_int64]("sqlite3_column_int64")
        return int(fn_int(self._stmt, c_int(col)))

    def get_float(self, col: Int) -> Float64:
        var fn_double = self._lib.get_function[def(C_Stmt, c_int) -> c_double]("sqlite3_column_double")
        return Float64(fn_double(self._stmt, c_int(col)))

    def get_string(self, col: Int) -> String:
        var fn_text = self._lib.get_function[def(C_Stmt, c_int) -> UnsafePointer[c_char]]("sqlite3_column_text")
        var ptr = fn_text(self._stmt, c_int(col))
        return String(StringSlice(unsafe_from_utf8_ptr=ptr))


struct Cursor:
    var _db: C_Db
    var _stmt: C_Stmt
    var _lib: DLHandle

    def __init__(out self, db: C_Db, lib: DLHandle):
        self._db = db
        self._stmt = C_Stmt()
        self._lib = lib

    def execute(mut self, sql: String) raises:
        var fn_prep = self._lib.get_function[
            def(C_Db, UnsafePointer[c_char], c_int, UnsafePointer[C_Stmt], UnsafePointer[NoneType]) -> c_int
        ]("sqlite3_prepare_v2")
        
        var stmt_ptr = UnsafePointer[C_Stmt].alloc(1)
        var sql_c = sql.unsafe_cstr_ptr()
        var rc = fn_prep(self._db, sql_c, -1, stmt_ptr, UnsafePointer[NoneType]())
        
        if rc != SQLITE_OK:
            stmt_ptr.free()
            raise Error("Failed to prepare statement. Code: " + String(rc))
            
        self._stmt = stmt_ptr.take_pointee()
        stmt_ptr.free()

    def fetchone(mut self) raises -> Optional[Row]:
        var fn_step = self._lib.get_function[def(C_Stmt) -> c_int]("sqlite3_step")
        var rc = fn_step(self._stmt)
        if rc == SQLITE_ROW:
            return Row(self._stmt, self._lib)
        elif rc == SQLITE_DONE:
            return None
        else:
            raise Error("Error during step: " + String(rc))

    def close(mut self):
        if self._stmt:
            var fn_fin = self._lib.get_function[def(C_Stmt) -> c_int]("sqlite3_finalize")
            _ = fn_fin(self._stmt)
            self._stmt = C_Stmt()


struct Connection:
    var _db: C_Db
    var _lib: DLHandle

    def __init__(out self, path: String) raises:
        self._lib = DLHandle("libsqlite3.so")
        var fn_open = self._lib.get_function[
            def(UnsafePointer[c_char], UnsafePointer[C_Db]) -> c_int
        ]("sqlite3_open")
        
        var db_ptr = UnsafePointer[C_Db].alloc(1)
        var rc = fn_open(path.unsafe_cstr_ptr(), db_ptr)
        if rc != SQLITE_OK:
            db_ptr.free()
            raise Error("Cannot open database: " + path)
            
        self._db = db_ptr.take_pointee()
        db_ptr.free()

    def cursor(self) -> Cursor:
        return Cursor(self._db, self._lib)

    def commit(self) raises:
        var cur = self.cursor()
        cur.execute("COMMIT")
        cur.close()

    def close(mut self):
        if self._db:
            var fn_close = self._lib.get_function[def(C_Db) -> c_int]("sqlite3_close_v2")
            _ = fn_close(self._db)
            self._db = C_Db()


def connect(database: String) raises -> Connection:
    return Connection(database)
```

---

## 5. Next Steps

1. Build `sqlite3.mojo` (Stage 0) and link against `/mnt/c/Documents/Programming/sqlite`.
2. Implement test suite validating `connect`, `execute`, `fetchone`, and `commit`.
3. Begin Stage 1: Translate `sqlite3PutVarint` / `sqlite3GetVarint` from `util.c` into pure Mojo with differential fuzz testing.
