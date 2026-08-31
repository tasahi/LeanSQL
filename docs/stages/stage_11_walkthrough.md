# Stage 11 Walkthrough: Advanced Relational Engine — Derived Subqueries in FROM, Common Table Expressions (CTEs), Window Functions, and Database Triggers

## Overview

Stage 11 adds full-featured relational query mechanisms to LeanSQL, expanding query processing beyond standard flat queries into hierarchical, iterative, windowed, and reactive workflows in **100% pure Mojo**.

The master test suite now verifies **264 canonical SQLite compatibility assertions across 18 distinct suites** with a **100% success rate**.

---

## Key Features Implemented

### 1. Derived Table Subqueries in FROM Clause
- Syntax: `SELECT ... FROM (SELECT ...) AS <alias> WHERE ...`
- Execution: Dynamically executes the nested subquery into an in-memory stream of candidate rows, applies column aliasing, and pipelines rows into the outer query's projection, `WHERE` filter, `ORDER BY`, and `LIMIT`/`OFFSET` operators.

### 2. Common Table Expressions (CTEs)
- **Non-Recursive CTEs**:
  - `WITH <name> AS (<subquery>) SELECT ...`
  - Populates in-memory schema table definitions with custom column specifications, enabling clean multi-stage query composition.
- **Recursive CTEs**:
  - `WITH RECURSIVE <name> AS (<anchor_subquery> UNION ALL <recursive_subquery>) SELECT ...`
  - Implements the formal SQLite working-table model:
    1. Evaluates anchor step.
    2. Initializes the working table with anchor results.
    3. Iteratively runs the recursive step against the working set until termination condition or fixed bounds.
    4. Accumulates results into the final virtual table.

### 3. Window Functions Engine
- Supported functions:
  - `ROW_NUMBER()`
  - `RANK()` / `DENSE_RANK()`
  - `LEAD(<expr> [, offset])`
  - `LAG(<expr> [, offset])`
- Clauses:
  - `OVER (ORDER BY ...)`
  - `OVER (PARTITION BY ... ORDER BY ...)`
- Execution: Inspects candidate row partitions, computes window metrics across sorted partition partitions, and integrates them into standard row projection expressions.

### 4. Database Triggers & Reactive DML Hooks
- Syntax:
  - `CREATE TRIGGER <name> AFTER [INSERT|UPDATE|DELETE] ON <tbl> FOR EACH ROW BEGIN <action>; END;`
  - `DROP TRIGGER <name>`
- Features:
  - Catalog registration: Triggers tracked in `SchemaCatalog` and queried via `sqlite_master`.
  - Column substitution: Dynamically expands `NEW.<column>` references during `INSERT` and `UPDATE` execution.
  - Synchronous execution: Fires corresponding action SQL statements within the active transaction context.

---

## Test Suites & Validation

### New Test Suites
1. **Suite 16: Derived Tables & CTEs** ([`tests/test_suite_16_subqueries_cte.mojo`](file:///mnt/c/Documents/Mojo/LeanSQL/tests/test_suite_16_subqueries_cte.mojo))
   - Verified filtered derived subquery in `FROM`.
   - Verified non-recursive CTE filtering and projection.
   - Verified recursive CTE sequence generation (`1..5`).
   - Verified recursive CTE powers of 2 (`1, 2, 4, 8, 16, 32`).
   - **Result**: 11 / 11 PASSED (100%).

2. **Suite 17: Window Functions** ([`tests/test_suite_17_window_funcs.mojo`](file:///mnt/c/Documents/Mojo/LeanSQL/tests/test_suite_17_window_funcs.mojo))
   - Verified `ROW_NUMBER() OVER (ORDER BY score DESC)`.
   - Verified partitioned `ROW_NUMBER() OVER (PARTITION BY team ORDER BY score DESC)`.
   - Verified `LEAD()` and `LAG()` over sorted sequences with NULL edge cases.
   - **Result**: 15 / 15 PASSED (100%).

3. **Suite 18: Database Triggers** ([`tests/test_suite_18_triggers.mojo`](file:///mnt/c/Documents/Mojo/LeanSQL/tests/test_suite_18_triggers.mojo))
   - Verified `CREATE TRIGGER AFTER INSERT` with `NEW.col` audit record insertion.
   - Verified `CREATE TRIGGER AFTER UPDATE` audit logging.
   - Verified `CREATE TRIGGER AFTER DELETE` audit logging.
   - Verified `DROP TRIGGER` catalog cleanup.
   - **Result**: 11 / 11 PASSED (100%).

### Full Master Test Suite Status
Running `bash tests/run_tests.sh` executes all 18 test suites:
- **Total Assertions Executed**: **264**
- **Passed**: **264**
- **Failed**: **0**
- **Success Rate**: **100%**
