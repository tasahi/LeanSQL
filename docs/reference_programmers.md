---
type: architecture
title: "LeanSQL Programmer's Reference Manual"
description: "Technical reference manual detailing the internal engine architecture, layered subsystems, type systems, and C/Python extension interfaces for LeanSQL developers."
tags:
  - mojo
  - sqlite
  - architecture
  - btree
  - vdbe
  - pager
  - compiler
  - internals
version: "1.0"
last_updated: "2026-09-16"
status: active
---

# LeanSQL: Programmer's Reference Manual

This technical manual details the internal architecture, subsystem decomposition, type systems, and C/Python extension APIs for developers working on or extending the **100% Pure-Mojo LeanSQL database engine**.

---

## 1. Engine Subsystems Overview

The LeanSQL architecture faithfully implements the layered SQLite database engine without any external C runtime dependencies:

```
+---------------------------------------------------------------------------------------------------+
|                                LeanSQL: Pure-Mojo Engine Architecture                               |
+---------------------------------------------------------------------------------------------------+
|  Python DB-API (leansql_driver.py)  |  Interactive CLI (leansql.mojo)  |  C-ABI (include/leansql.h)  |
+---------------------------------------------------------------------------------------------------+
|  SQL Parser & Lexer (parser.mojo)  |  Query Optimizer (optimizer)    |  VDBE VM (vdbe.mojo)       |
+---------------------------------------------------------------------------------------------------+
|  B-Tree & Cursors (btree.mojo)     |  ACID Pager & Journal (pager)   |  VFS Disk & Memory (vfs)   |
+---------------------------------------------------------------------------------------------------+
|  LeanSQL Extensions: FTS / BM25 (fts) | SIMD Vector Search (vector)   | Math & Crypto (crypto)     |
+---------------------------------------------------------------------------------------------------+
```

---

## 2. Subsystem Details & Source Mapping

### A. OS Interface & Storage (`src/vfs/vfs_os.mojo`, `src/vfs/pager.mojo`, `src/vfs/journal.mojo`)
- **Virtual File System (`VFS`)**: Provides abstractions over memory-backed storage (`MemFile`) and physical disk I/O (`DiskFile`). Implements SQLite's 5-level lock state machine (`NO_LOCK`, `SHARED_LOCK`, `RESERVED_LOCK`, `PENDING_LOCK`, `EXCLUSIVE_LOCK`).
- **Pager (`Pager`, `PCache`, `DbPage`)**: Coordinates memory page caching, dirty page tracking, and transaction boundaries.
- **Rollback Journal (`Journal`, `JournalRecord`)**: Implements ACID durability with rollback log replay under `JOURNAL_MODE_DELETE`, `PERSIST`, `TRUNCATE`, `MEMORY`, and `OFF`.

### B. B-Tree & Binary Codecs (`src/storage/btree.mojo`, `src/storage/btree_cell.mojo`, `src/storage/record.mojo`, `src/storage/serial.mojo`, `src/storage/page_header.mojo`)
- **B-Tree (`MemBTree`, `BTreeCursor`)**: Balanced tree structures for tables and secondary indexes with binary key search and ordered sequential traversal.
- **Record Codecs (`encode_record`, `decode_record`)**: Serializes dynamically-typed column values using SQLite's standard Serial Types (0–14).
- **Page Headers (`DbHeader`, `PageHeader`)**: Standard 100-byte database header (`"SQLite format 3\000"`) and 8/12-byte interior/leaf B-tree page headers.

### C. Bytecode Engine (`src/vdbe/vm.mojo`, `src/vdbe/opcode.mojo`)
- **VDBE Engine (`Vdbe`, `VdbeOp`)**: Register-based virtual machine executing bytecode instructions (`OP_Init`, `OP_OpenRead`, `OP_OpenWrite`, `OP_Column`, `OP_MakeRecord`, `OP_Insert`, `OP_Delete`, `OP_ResultRow`, `OP_Halt`).
- **Registers (`VdbeMem`)**: Supports dynamic value storage with explicit type affinities (`INTEGER`, `FLOAT`, `TEXT`, `BLOB`, `NULL`).

### D. Tokenizer, Parser & Query Planner (`src/sql/tokenizer.mojo`, `src/sql/parser.mojo`, `src/sql/uast.mojo`, `src/sql/optimizer.mojo`)
- **Lexer (`tokenize_sql`)**: Converts SQL text into typed tokens.
- **Parser (`parse_sql`)**: Generates an abstract syntax tree (`ASTStatement`) for DDL, DML, and DQL statements.
- **Query Planner (`Optimizer`, `WhereScan`)**: Evaluates index usage, calculates cost metrics, and selects indexed B-Tree lookups over full table scans.

### E. Connection & Evaluation (`src/engine/connection.mojo`, `src/engine/cursor.mojo`, `src/engine/schema.mojo`, `src/engine/functions.mojo`)
- **Connection (`Connection`, `Cursor`)**: Central query dispatcher managing catalog state, transactions, savepoints, multi-table JOINs, subqueries, recursive CTEs, window functions, and triggers.
- **Functions (`evaluate_scalar_func`)**: Scalar dispatch table supporting built-in and extended functions.

---

## 3. Extension Subsystems

### A. Full-Text Search & BM25 (`src/ext/fts.mojo`)
- `tokenize_text(text: String) -> List[String]`: Case-folded alphanumeric tokenization.
- `fts_match(text: String, query: String) -> Bool`: Multi-term conjunctive search.
- `compute_bm25_score(query_tokens, doc_tokens, total_docs, doc_freqs, avg_doc_len, k1=1.2, b=0.75) -> Float64`: BM25 relevance scoring.
- `fts_highlight(text, query, open_tag="<b>", close_tag="</b>") -> String`: Match term markup.
- `fts_snippet(text, query, max_words=10) -> String`: Context window excerpt extractor.

### B. SIMD Vector Similarity (`src/ext/vector.mojo`)
- `Vector`: Contiguous Float64 array data structure.
- `parse_vector(raw_str: String) -> Vector`: String/JSON vector parser (e.g. `"[0.1, 0.2, 0.3]"`).
- `vec_dot_product(v1: Vector, v2: Vector) -> Float64`: Dot product kernel.
- `vec_distance_l2(v1: Vector, v2: Vector) -> Float64`: Euclidean ($L_2$) distance.
- `vec_distance_cosine(v1: Vector, v2: Vector) -> Float64`: Cosine distance ($1.0 - \text{sim}$).

### C. Cryptography & Encodings (`src/ext/crypto.mojo`)
- `md5_hash(text: String) -> String`: 128-bit MD5 digest.
- `sha256_hash(text: String) -> String`: 256-bit SHA-256 digest.
- `hex_encode_str(text: String) -> String`: Hex string encoder.
- `hex_decode(hex_str: String) -> String`: Hex string decoder.

---

## 4. C-ABI and Python Binding Exports

### A. C-ABI Header (`include/leansql.h` & `src/interop/c_api.mojo`)
Standard SQLite 3 ABI compatibility prototypes:
```c
int sqlite3_open(const char *filename, sqlite3 **ppDb);
int sqlite3_close(sqlite3 *db);
int sqlite3_prepare_v2(sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail);
int sqlite3_step(sqlite3_stmt *pStmt);
int sqlite3_finalize(sqlite3_stmt *pStmt);
const char *sqlite3_column_text(sqlite3_stmt *pStmt, int iCol);
int64_t sqlite3_column_int64(sqlite3_stmt *pStmt, int iCol);
double sqlite3_column_double(sqlite3_stmt *pStmt, int iCol);
int sqlite3_column_type(sqlite3_stmt *pStmt, int iCol);
int sqlite3_changes(sqlite3 *db);
int64_t sqlite3_last_insert_rowid(sqlite3 *db);
```

### B. Python C-Extension (`src/interop/py_export.mojo`)
Compiled with:
```bash
mojo build --emit shared-lib -I . src/interop/py_export.mojo -o leansql.so
```
Exports `PyInit_leansql` with `open`, `execute`, `fetch_all`, `commit`, `close`, `version`.

---

## 5. Adding New Built-In Scalar Functions

To add a new SQL function (e.g. `MY_FUNC(x)`):
1. Implement the kernel in Mojo (e.g., `src/engine/functions.mojo` or dedicated module).
2. Register the function name in `evaluate_scalar_func` in `src/engine/functions.mojo`:
```mojo
    elif nocase_compare(name, "MY_FUNC") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_text(my_kernel(args[0].to_string()))
        return Value.of_null()
```
3. Add tests to the corresponding test suite in `tests/`.
