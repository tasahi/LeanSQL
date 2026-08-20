# Stage 10 Walkthrough: PRAGMA Engine, Schema Evolution DDL (`ALTER TABLE`), Views, and Native Python C-Extension Export (`sqlean.so`)

## Overview

Stage 10 introduces advanced schema management, schema evolution capabilities, runtime database introspection via `PRAGMA` and `sqlite_master`, and direct native Python C-extension export via Mojo's `PythonModuleBuilder`.

SQLean remains **100% pure Mojo** with zero external C dependencies, yet can now be imported directly into standard Python 3 applications via `import sqlean`.

---

## Key Features Implemented

### 1. PRAGMA & Schema Introspection Engine
- **`PRAGMA table_info(<table_name>)`**:
  Returns metadata rows with columns:
  - `cid`: Column ID (0-indexed integer)
  - `name`: Column name (string)
  - `type`: Data type affinity (`INTEGER`, `REAL`, `TEXT`, `BLOB`)
  - `notnull`: Boolean flag (1 if `NOT NULL` constraint is active, else 0)
  - `dfl_value`: Default value specified during table creation
  - `pk`: Boolean flag (1 if Primary Key, else 0)
- **`PRAGMA index_list(<table_name>)`**:
  Returns all indexes associated with the specified table (`seq`, `name`, `unique`, `origin`, `partial`).
- **`PRAGMA user_version` & `PRAGMA user_version = <val>`**:
  Provides user-defined version tracking for database migrations.
- **`sqlite_master` / `sqlite_schema` Virtual Catalog Table**:
  Enables SQL queries over schema metadata (`SELECT type, name, tbl_name, rootpage, sql FROM sqlite_master`), supporting filtering (`WHERE type = 'view'`) and multi-column ordering (`ORDER BY type, name`).

### 2. Schema Evolution DDL (`ALTER TABLE`) & Views (`CREATE VIEW`)
- **`ALTER TABLE <table_name> RENAME TO <new_table_name>`**:
  Dynamically renames tables in the catalog and updates all referencing index metadata.
- **`ALTER TABLE <table_name> ADD COLUMN <column_def>`**:
  Appends new column definitions to existing tables. During record decoding, rows created before the schema alteration are automatically populated with the column's default value (`DEFAULT <val>`) or `NULL`.
- **`ALTER TABLE <table_name> RENAME COLUMN <old_name> TO <new_name>`**:
  Renames existing columns without data loss.
- **`CREATE VIEW <view_name> AS SELECT ...` / `DROP VIEW <view_name>`**:
  Supports virtual view creation and removal.

### 3. Native Python C-Extension Shared Library (`sqlean.so`)
- Exported ABI entrypoint: `@export def PyInit_sqlean() abi("C") -> PythonObject`.
- Module functions exposed via `PythonModuleBuilder`:
  - `sqlean.version() -> str`: Returns SQLean version string.
  - `sqlean.execute(db_path: str, sql: str) -> bool`: Executes DDL / DML commands (`CREATE TABLE`, `INSERT`, `ALTER TABLE`) with auto-commit.
  - `sqlean.execute_count(db_path: str, table_name: str) -> int`: Returns integer row count for a table.
  - `sqlean.execute_query(db_path: str, sql: str) -> str`: Executes queries and returns formatted output rows.
- Compiled via `mojo build --emit shared-lib -I . src/py_export.mojo -o sqlean.so`.

---

## Test Suites & Validation

### New Test Suites
1. **Suite 14**: [`tests/test_suite_14_pragma_schema.mojo`](file:///mnt/c/Documents/Mojo/SQLean/tests/test_suite_14_pragma_schema.mojo) (20 assertions)
   - Verified `PRAGMA table_info` column attributes, types, PKs, NOT NULL constraints.
   - Verified `PRAGMA index_list` indexing metadata.
   - Verified `PRAGMA user_version` getter and setter.
   - Verified `sqlite_master` multi-column ordered catalog queries.
2. **Suite 15**: [`tests/test_suite_15_alter_view.mojo`](file:///mnt/c/Documents/Mojo/SQLean/tests/test_suite_15_alter_view.mojo) (10 assertions)
   - Verified `ALTER TABLE RENAME TO`.
   - Verified `ALTER TABLE ADD COLUMN` with default values and schema evolution backfill.
   - Verified `ALTER TABLE RENAME COLUMN`.
   - Verified `CREATE VIEW` registration and `DROP VIEW`.
3. **Python Interop Test**: [`tests/test_python_interop.py`](file:///mnt/c/Documents/Mojo/SQLean/tests/test_python_interop.py)
   - Verified `import sqlean`, schema creation, row insertions, counting, and querying directly from Python 3!

### Master Test Suite Status
Running `bash tests/run_tests.sh` executes all 15 test suites:
- **Total Assertions Executed**: **227**
- **Passed**: **227**
- **Failed**: **0**
- **Success Rate**: **100%**
