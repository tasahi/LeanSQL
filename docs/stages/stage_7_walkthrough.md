# Walkthrough - Stage 7: Query Optimizer, WhereScan & Standalone Mojo SQLite Engine

Stage 7 completes the pure Mojo SQLite transcription roadmap by implementing the WhereScan query planner and query optimizer (`where.c`, `whereInt.h`), enabling $O(\log N)$ direct RowID seeks and optimal execution planning.

## Architecture & Codebase Structure

```
./
├── src/
│   ├── types.mojo           # SQLite result codes, open flags, and C pointer aliases
│   ├── c_api.mojo           # Low-level external_call bindings to libsqlite3.so
│   ├── error.mojo           # Error checking & exception raising helpers
│   ├── row.mojo             # Value and Row structs
│   ├── cursor.mojo          # Pythonic cursor
│   ├── connection.mojo      # Connection and connect factory
│   ├── varint.mojo          # Variable-length integer encoding & decoding (1-9 bytes)
│   ├── utf.mojo             # UTF-8 multi-byte codecs & ASCII nocase collation
│   ├── hash.mojo            # Knuth multiplicative string hash (0x9E3779B1)
│   ├── bitvec.mojo          # BitVec structure for page and rowid tracking
│   ├── serial.mojo          # Serial Type Codecs (0..14+) & integer compaction
│   ├── record.mojo          # Record layout engine (varint header + packed payload)
│   ├── page_header.mojo     # 100-byte DB file header & 8/12-byte B-tree page headers
│   ├── vfs.mojo             # Virtual File System & POSIX / In-Memory file I/O
│   ├── journal.mojo         # SQLite Rollback Journal (pre-images & header codecs)
│   ├── pager.mojo           # Pager state machine, LRU page cache, ACID transactions
│   ├── btree_cell.mojo      # Table Leaf and Interior Cell binary codecs
│   ├── btree.mojo           # MemBTree engine and BTreeCursor scanner
│   ├── opcode.mojo          # VDBE Opcode constants and Opcode instruction struct
│   ├── vdbe.mojo            # VDBE Virtual Machine interpreter and dispatch loop
│   ├── tokenizer.mojo       # SQL Lexer and token symbol scanner
│   ├── parser.mojo          # SQL AST Statement parser and VDBE bytecode compiler
│   ├── optimizer.mojo       # [NEW] WhereScan query planner and access path optimizer
│   └── __init__.mojo        # Public library interface
└── tests/
    ├── test_connect.mojo     # Stage 0: C-FFI connection
    ├── test_crud.mojo        # Stage 0: Client CRUD
    ├── test_types.mojo       # Stage 0: Type fidelity
    ├── test_transactions.mojo# Stage 0: Transactions
    ├── test_varint_diff.mojo # Stage 1: Varint codecs
    ├── test_utf.mojo         # Stage 1: UTF-8 & nocase collation
    ├── test_hash.mojo        # Stage 1: Knuth hash
    ├── test_bitvec.mojo      # Stage 1: BitVec allocation tracking
    ├── test_serial.mojo      # Stage 2: Serial types 0..14
    ├── test_record.mojo      # Stage 2: SQLite Record payload format
    ├── test_page_header.mojo # Stage 2: 100-byte DB & B-Tree Page headers
    ├── test_vfs.mojo         # Stage 3: VFS & POSIX / Memory file I/O
    ├── test_journal.mojo     # Stage 3: Rollback Journal & 28-byte header
    ├── test_pager.mojo       # Stage 3: Pager ACID transactions & crash recovery
    ├── test_btree_cell.mojo  # Stage 4: Leaf/Interior cell binary codecs
    ├── test_btree.mojo       # Stage 4: Sorted B-Tree table & bidirectional cursor
    ├── test_vdbe_math.mojo   # Stage 5: Arithmetic & jump execution
    ├── test_vdbe_scan.mojo   # Stage 5: B-Tree table scan & column projection
    ├── test_tokenizer.mojo   # Stage 6: SQL Lexer & Tokenizer
    ├── test_parser.mojo      # Stage 6: AST Statement parser & Bytecode compiler
    └── test_optimizer.mojo   # [NEW] Stage 7: WhereScan query planning & O(log N) rowid seek
```

---

## Implemented Components

### 1. WhereScan Query Planner ([`src/optimizer.mojo`](../src/optimizer.mojo))
- **`QueryPlan`**: Tracks chosen execution strategy:
  - `PLAN_FULL_SCAN`: Iterates all cells via `OP_REWIND` and `OP_NEXT`.
  - `PLAN_ROWID_SEEK`: Optimized $O(\log N)$ point seek via `OP_SEEK_ROWID`.
- **`optimize_where_clause(stmt: SelectStmt)`**: Analyzes query filters (`WHERE id = 7` or `WHERE rowid = 7`) and matches them to primary key B-Tree index structures.
- **`compile_optimized_select(stmt: SelectStmt, table_btree_idx: Int)`**: Generates targeted bytecode avoiding redundant table scans.

---

## Verification & Test Results

### 1. WhereScan Optimizer Tests ([`tests/test_optimizer.mojo`](../tests/test_optimizer.mojo))
```
=== Testing WhereScan Query Optimization (RowID Seek) ===
  Optimizer successfully selected PLAN_ROWID_SEEK (O(log N))!
  Optimized RowID seek returned exact record: ID: 7, Name: Record #7
WhereScan Query Optimizer tests passed successfully!
```
