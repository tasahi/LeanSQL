# Walkthrough - Stage 3: OS Interface (VFS), File IO & Pager Engine

Stage 3 translates SQLite's Virtual File System (VFS), POSIX OS file layer, page cache, rollback journal, and Pager transaction state machine into pure Mojo 1.0.

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
│   ├── vfs.mojo             # [NEW] Virtual File System & POSIX / In-Memory file I/O
│   ├── journal.mojo         # [NEW] SQLite Rollback Journal (pre-images & header codecs)
│   ├── pager.mojo           # [NEW] Pager state machine, LRU page cache, ACID transactions
│   └── __init__.mojo        # Public library interface
└── tests/
    ├── test_connect.mojo     # Stage 0
    ├── test_crud.mojo        # Stage 0
    ├── test_types.mojo       # Stage 0
    ├── test_transactions.mojo# Stage 0
    ├── test_varint_diff.mojo # Stage 1
    ├── test_utf.mojo         # Stage 1
    ├── test_hash.mojo        # Stage 1
    ├── test_bitvec.mojo      # Stage 1
    ├── test_serial.mojo      # Stage 2
    ├── test_record.mojo      # Stage 2
    ├── test_page_header.mojo # Stage 2
    ├── test_vfs.mojo         # [NEW] Stage 3: File seek, sparse write, truncate & lock tests
    ├── test_journal.mojo     # [NEW] Stage 3: Journal 28-byte header, pre-image recording & rollback
    └── test_pager.mojo       # [NEW] Stage 3: ACID transaction commit and recovery tests
```

---

## Implemented Components

### 1. Virtual File System & OS Layer ([`src/vfs.mojo`](../src/vfs.mojo))
- **`FileLock`**: SQLite 5-level concurrency locks (`NO_LOCK`, `SHARED_LOCK`, `RESERVED_LOCK`, `PENDING_LOCK`, `EXCLUSIVE_LOCK`).
- **`MemFile`**: In-memory dynamic file simulator for `:memory:` databases, temporary files, and in-memory rollback journals.
- **`DiskFile`**: Direct POSIX filesystem abstraction using libc syscalls (`open`, `read`, `write`, `lseek`, `ftruncate`, `fsync`, `close`).
- **`VFS`**: Manager for opening disk/memory files, checking file existence, and deleting files.

### 2. Rollback Journal Engine ([`src/journal.mojo`](../src/journal.mojo))
- **`Journal`**: Pre-image recorder storing unmodified pages prior to in-place mutation.
- **`JournalHeader`**: 28-byte SQLite Rollback Journal Header codec with magic bytes `0xd9d505f920a163d7`, page counts, checksum seeds, and sector sizes.
- **`rollback()` & `commit()`**: Restores original pages upon abort or frees journal records upon commit.

### 3. Pager Subsystem & Page Cache ([`src/pager.mojo`](../src/pager.mojo))
- **`DbPage`**: In-memory page representation (`pgno`, `data: List[UInt8]`, `is_dirty`).
- **`PCache`**: LRU page cache for fast lookups and dirty page management.
- **`Pager`**: Complete ACID transaction manager:
  - `acquire_page(pgno: UInt32)`: Reads from cache or storage.
  - `write_page(mut page: DbPage)`: Captures pre-image into journal and marks page dirty.
  - `commit()`: Writes all dirty pages to storage, flushes to disk, and commits journal.
  - `rollback()`: Restores original database state from journal.

---

## Verification & Test Results

### 1. VFS Tests ([`tests/test_vfs.mojo`](../tests/test_vfs.mojo))
```
=== Testing MemFile Operations ===
MemFile test passed successfully!
=== Testing VFS Factory ===
VFS factory test passed successfully!
```

### 2. Journal Tests ([`tests/test_journal.mojo`](../tests/test_journal.mojo))
```
=== Testing Rollback Journal Recording & Header ===
Journal recording and rollback test passed!
```

### 3. Pager ACID Tests ([`tests/test_pager.mojo`](../tests/test_pager.mojo))
```
=== Testing Pager ACID Transactions & Rollback ===
  Created Pager with page size: 512
  Committed Page 1 to storage. Total DB pages: 1
  Rolled back active transaction.
  Page 1 pre-image successfully verified after rollback!
Pager ACID transaction tests passed successfully!
```
