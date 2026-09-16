---
type: integration-guide
title: "Native Python C-Extension Module Export (leansql.so)"
description: "Implementation and build instructions for exporting LeanSQL as a native C-extension shared library using Mojo's PythonModuleBuilder and PyInit entrypoints."
tags:
  - mojo
  - python
  - c-extension
  - interop
  - leansql
  - shared-lib
version: "1.0"
last_updated: "2026-09-16"
status: active
---

# Native Python C-Extension Module Export (`leansql.so`)

LeanSQL can be built directly into a standard Python native C-extension shared library (`leansql.so`) using Mojo's `PythonModuleBuilder` and exported `PyInit_leansql` ABI entrypoint.

---

## 1. Mojo Export Source ([`src/interop/py_export.mojo`](../src/interop/py_export.mojo))

```mojo
from std.python import PythonObject
from std.python.bindings import PythonModuleBuilder
from src.engine.connection import connect
from src.engine.row import Value, Row


def leansql_version() raises -> PythonObject:
    """ Returns the version of LeanSQL."""
    return PythonObject("LeanSQL 0.1.0 (Mojo + SQLite Engine)")


def leansql_count(path_obj: PythonObject, table_obj: PythonObject) raises -> PythonObject:
    """ Executes SELECT COUNT(*) from the given table and returns integer count."""
    var db_path = String(path_obj)
    var table_name = String(table_obj)
    var query = "SELECT COUNT(*) FROM " + table_name

    var con = connect(db_path)
    var cur = con.cursor()
    cur.execute(query)

    var row = cur.fetchone()
    var count: Int = 0
    if row:
        count = Int(row.value().get_int(0))

    con.close()
    return PythonObject(count)


def leansql_query(path_obj: PythonObject, sql_obj: PythonObject) raises -> PythonObject:
    """ Connects to SQLite database at `path_obj`, executes `sql_obj`, and returns formatted lines."""
    var path_str = String(path_obj)
    var sql_str = String(sql_obj)

    var con = connect(path_str)
    var cur = con.cursor()
    cur.execute(sql_str)

    var rows = cur.fetchall()
    var output_str = String()

    for r_idx in range(len(rows)):
        var row = rows[r_idx]
        var line = String()
        var num_cols = len(row)

        for c_idx in range(num_cols):
            if c_idx > 0:
                line += ","
            if row.is_null(c_idx):
                line += "NULL"
            else:
                line += row.get_string(c_idx)

        output_str += line + "\n"

    con.close()
    return PythonObject(output_str)


@export
def PyInit_leansql() abi("C") -> PythonObject:
    """ Initializes the native Python C-extension module 'leansql'."""
    try:
        var mb = PythonModuleBuilder("leansql")
        mb.def_function[leansql_version]("version", "Returns LeanSQL version string")
        mb.def_function[leansql_count]("execute_count", "Returns integer row count for a table")
        mb.def_function[leansql_query]("execute_query", "Executes SQL query and returns formatted rows as string")
        return mb.finalize()
    except:
        return PythonObject()
```

---

## 2. Compilation into `.so`

To compile the shared object library:

```bash
source /home/tasahi/miniconda/bin/activate moj
mojo build --emit shared-lib -I . -Xlinker -L/home/tasahi/miniconda/envs/moj/lib -Xlinker -lsqlite3 src/interop/py_export.mojo -o leansql.so
```

---

## 3. Direct Python Usage Example

You can import and use `leansql` directly in any Python 3 script or REPL:

```python
import leansql

# 1. Check version
print(leansql.version())
# Output: LeanSQL 0.1.0 (Mojo + SQLite Engine)

# 2. Execute COUNT query directly from Python
count = leansql.execute_count("./data/example.db", "rag_chunks")
print(f"Total chunks: {count}")
# Output: Total chunks: 1638

# 3. Execute arbitrary SQL query returning formatted data
result = leansql.execute_query("./data/example.db", "SELECT id, title FROM navigation_items LIMIT 3")
print(result)
```
