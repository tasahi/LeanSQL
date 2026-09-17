---
type: extension
title: "LeanSQL Virtual Table Interface, Dynamic Library Loading, and Function Hooks"
description: "Architecture and reference manual for LeanSQL's Virtual Table mechanism (CREATE VIRTUAL TABLE ... USING), dynamic library loading (dlopen/dlsym), and user-defined scalar function registration in pure Mojo."
tags:
  - mojo
  - sqlite
  - vtable
  - extensions
  - virtual-tables
  - dynamic-linking
  - ffi
  - udfs
version: "1.0"
last_updated: "2026-09-16"
status: active
---

# LeanSQL: Virtual Table Interface & Dynamic Extension System

LeanSQL provides an extensible, SQLite-compatible **Virtual Table Interface**, runtime **Dynamic Library Loader**, and **User-Defined Function (UDF) Registration** mechanism written in 100% pure Mojo.

---

## 1. User-Defined Custom Scalar Functions

Users can register custom Mojo scalar functions dynamically on any active database `Connection`.

### Interface: `register_function`
```mojo
conn.register_function("name", callback_func)
```
- **Function Signature**: `def(List[Value]) thin -> Value` (thin function pointer in Mojo 1.0).
- Functions receive evaluated SQL argument values and return a typed `Value` (`NULL`, `INTEGER`, `FLOAT`, `TEXT`, `BLOB`).

### Example Usage
```mojo
from src.engine.connection import Connection, connect
from src.engine.row import Value

def double_val(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    return Value.of_int(args[0].to_int() * 2)

var conn = Connection(":memory:")
conn.register_function("double_val", double_val)

var cursor = conn.execute("SELECT double_val(21) AS result")
# Output: result = 42
```

Registered functions can be used seamlessly across `SELECT`, `WHERE`, `ORDER BY`, `GROUP BY`, and subqueries.

---

## 2. Dynamic Library Loading & C/C++ Extensions

LeanSQL implements a zero-dependency platform dynamic loader using Mojo's `std.ffi.external_call` (`dlopen`, `dlsym`, `dlclose`, `dlerror`).

### A. Mojo Interface: `DynamicLibrary` & `load_extension`
```mojo
conn.load_extension(path: String, entrypoint: String = "sqlite3_extension_init")
```
- Dynamically loads `.so` / `.dylib` / `.dll` shared libraries at runtime.
- If an `entrypoint` function is supplied, LeanSQL looks up the symbol via `dlsym` and invokes the module initializer.

### B. C-ABI Interface (`include/leansql.h`)
LeanSQL exports the standard SQLite3 extension loading symbols and virtual table module definitions:
```c
int sqlite3_load_extension(sqlite3 *pDb, const char *zFile, const char *zProc, char **pzErrMsg);
int sqlite3_create_function(sqlite3 *pDb, const char *zFunctionName, int nArg, int eTextRep, void *pApp, ...);
int sqlite3_create_module(sqlite3 *pDb, const char *zName, const sqlite3_module *pModule, void *pClientData);
```

### C. Python DB-API Interface (`leansqlean_driver.py`)
```python
import leansqlean_driver as sqlite3

con = sqlite3.connect(":memory:")
con.enable_load_extension(True)
con.load_extension("./my_extension.so")
```

---

## 3. Virtual Table Interface (`CREATE VIRTUAL TABLE`)

LeanSQL supports custom storage engines, specialized indexes (such as external vector search indexes or graph indexes), and in-memory generators via SQLite's `CREATE VIRTUAL TABLE` syntax.

### Syntax
```sql
CREATE VIRTUAL TABLE <table_name> USING <module_name>(<arg1>, <arg2>, ...);
```

### Virtual Table Architecture (`src/engine/vtab.mojo`)

1. **`VirtualTableModule`**: Factory interface responsible for creating or connecting to virtual tables (`create`, `connect`).
2. **`VirtualTable`**: Represents an active virtual table instance.
   - `best_index(constraints: List[IndexConstraint]) -> Int`: Evaluates query constraints to select optimal scan strategies.
   - `open_cursor() -> VirtualTableCursor`: Instantiates a cursor for row iteration.
   - `insert_row(rowid: Int64, values: List[Value])`: Handles `INSERT` statements.
   - `delete_row(rowid: Int64)`: Handles `DELETE` statements.
3. **`VirtualTableCursor`**:
   - `filter(idx_num: Int, constraints: List[Value])`: Positions cursor based on `best_index` plan.
   - `next()`: Advances cursor to the next row.
   - `eof() -> Bool`: Checks whether cursor reached end-of-scan.
   - `column_value(col_idx: Int) -> Value`: Reads the column value at the current row.
   - `rowid() -> Int64`: Returns unique row identifier.

---

## 4. Implementing and Using a Virtual Table Module

Below is a complete example of creating, registering, and querying an in-memory virtual table module using standard Mojo 1.0 syntax:

```mojo
from src.core.types import *
from src.engine.connection import Connection, connect
from src.engine.row import Value, Row
from src.engine.vtab import VirtualTableModule

var conn = connect(":memory:")

# 1. Register a Virtual Table Module
var vmod = VirtualTableModule("temp_series")
conn.register_module("temp_series", vmod)

# 2. Create Virtual Table via standard SQL DDL
_ = conn.execute("CREATE VIRTUAL TABLE series_data USING temp_series(id INT, label TEXT, score REAL)")

# 3. Insert rows into the virtual table
_ = conn.execute("INSERT INTO series_data VALUES (101, 'alpha', 88.5)")
_ = conn.execute("INSERT INTO series_data VALUES (102, 'beta', 92.0)")
_ = conn.execute("INSERT INTO series_data VALUES (103, 'gamma', 75.2)")

# 4. Query the virtual table with SQL filtering, projection, and ordering
var cur = conn.execute("SELECT label, score FROM series_data WHERE score >= 80.0 ORDER BY score DESC")
var rows = cur.fetchall()

for i in range(len(rows)):
    var r = rows[i]
    print(r.get_string(0), r.get_float(1))

# Output:
# beta 92.0
# alpha 88.5
```


