# Stage 9: Multi-Table JOINs, Compound Queries & Persistent Disk Storage

## Overview

Stage 9 extends SQLean's 100% standalone pure Mojo SQLite engine to support advanced multi-table querying, relational algebra compound set operations, and on-disk file persistence.

---

## 1. Features Implemented & Subsystems

### A. Multi-Table Relational JOINs
- **Supported Joins**:
  - `INNER JOIN` (explicit `JOIN` / `INNER JOIN ... ON ...`)
  - `LEFT OUTER JOIN` (with automatic `NULL` padding for unmatched right-side rows)
  - `CROSS JOIN` (full Cartesian product)
- **Table Aliases & Qualification**:
  - Table aliasing (`FROM users AS u JOIN depts AS d ON u.dept_id = d.id`)
  - Implicit aliasing (`FROM users u JOIN depts d ON u.dept_id = d.id`)
  - Qualified column identifiers (`u.name`, `depts.dept_name`, `t.*`)
  - Nested multi-way joins (e.g. 3+ tables simultaneously joined and projected)

### B. Compound Queries (Relational Set Operations)
- **`UNION`**: Combines results of two `SELECT` statements with duplicate deduplication (`DISTINCT`).
- **`UNION ALL`**: Combines results preserving all duplicate records.
- **`INTERSECT`**: Computes the set intersection (common rows present in both result sets).
- **`EXCEPT`**: Computes set difference (rows present in the left query but not in the right).

### C. Persistent On-Disk Storage Engine
- **POSIX VFS Integration**:
  - Connecting `Connection` to `VFS` and `DiskFile` (`src/vfs.mojo`).
  - Automatic on-disk database file creation and binary serialization (`SQLEAN01` magic header format).
  - Persists tables, columns, primary key metadata, auto-increment rowid state, and all `MemBTree` payload cells.
  - Automatic deserialization and restoration on `connect("path/to/db.db")`.
  - Atomic changes persisted upon `INSERT`, `UPDATE`, `DELETE`, and `commit()`.

---

## 2. Extended Test Suites

Three new comprehensive test suites were ported and added to SQLean's master test runner:

| Suite | File | Coverage | Assertions |
| :--- | :--- | :--- | :--- |
| **Suite 11** | [`tests/test_suite_11_joins.mojo`](../tests/test_suite_11_joins.mojo) | `INNER JOIN`, `LEFT JOIN`, `CROSS JOIN`, 3-table join, table aliases, qualified projections | 12 / 12 Passing |
| **Suite 12** | [`tests/test_suite_12_compound.mojo`](../tests/test_suite_12_compound.mojo) | `UNION`, `UNION ALL`, `INTERSECT`, `EXCEPT` | 8 / 8 Passing |
| **Suite 13** | [`tests/test_suite_13_persistence.mojo`](../tests/test_suite_13_persistence.mojo) | Disk file creation, cross-session reconnection, record durability, schema reload | 8 / 8 Passing |

---

## 3. Verification & Execution Results

Running the master test suite via `bash tests/run_tests.sh` in the conda `moj` environment:

```text
=======================================================================
           SQLean: TOP 100+ FUNDAMENTAL SQLITE TESTS SUITE             
=======================================================================

=== Suite 1: Basic SELECT & Literals (select1.test) ===  -> 13/13 PASS
=== Suite 2: INSERT Statements (insert.test) ===         -> 12/12 PASS
=== Suite 3: UPDATE & DELETE Statements (update.test) == -> 12/12 PASS
=== Suite 4: Expressions & Operators (expr.test) ===     -> 19/19 PASS
=== Suite 5: NULL Logic & 3VL (null.test) ===            -> 17/17 PASS
=== Suite 6: Types & Affinities (types.test) ===         -> 17/17 PASS
=== Suite 7: Transactions & Isolation (trans.test) ===   -> 13/13 PASS
=== Suite 8: Scalar Functions (func.test) ===            -> 20/20 PASS
=== Suite 9: Aggregate Functions (aggerror.test) ===     -> 19/19 PASS
=== Suite 10: WHERE Clauses & Indexes (where.test) ===   -> 11/11 PASS
=== Suite 11: Multi-Table JOINs (join.test) ===          -> 12/12 PASS
=== Suite 12: Compound Queries (union.test) ===          -> 8/8   PASS
=== Suite 13: File-Backed Persistence (persist.test) === -> 8/8   PASS

=======================================================================
                    FINAL EXTENDED TEST SUITE RESULTS                  
=======================================================================

--- Suite Summary: Full Extended SQLite Test Suites ---
  Passed: 197
  Failed: 0
  Total:  197
All fundamental test suites completed successfully!
```

---

## 4. Architectural Summary

```
                       +-----------------------------------+
                       |    SQL Query / DDL / Statements   |
                       +-----------------------------------+
                                         |
                                         v
                       +-----------------------------------+
                       |       src/tokenizer.mojo          |
                       | (JOIN, UNION, INTERSECT, EXCEPT)  |
                       +-----------------------------------+
                                         |
                                         v
                       +-----------------------------------+
                       |         src/parser.mojo           |
                       | (SelectStmt + Joins + Compounds)  |
                       +-----------------------------------+
                                         |
                                         v
                       +-----------------------------------+
                       |       src/connection.mojo         |
                       | - Multi-Table Loop / Left Join    |
                       | - Set Union / Intersect / Except  |
                       | - Disk Pager & VFS Persistence    |
                       +-----------------------------------+
                                    /         \
                                   v           v
                    +--------------------+   +-------------------+
                    |   src/btree.mojo   |   |   src/vfs.mojo    |
                    | (Record Payloads)  |   | (POSIX Disk File) |
                    +--------------------+   +-------------------+
```
