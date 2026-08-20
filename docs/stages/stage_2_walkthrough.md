# Walkthrough - Stage 2: Storage Serialization, Record Format & Page Layout

Stage 2 translates SQLite's core storage serialization engines into pure Mojo 1.0. These modules provide binary-exact packing, unpacking, and header codecs corresponding to SQLite's internal storage format.

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
│   ├── serial.mojo          # [NEW] Serial Type Codecs (0..14+) & integer compaction
│   ├── record.mojo          # [NEW] Record layout engine (varint header + packed payload)
│   ├── page_header.mojo     # [NEW] 100-byte DB file header & 8/12-byte B-tree page headers
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
    ├── test_serial.mojo      # [NEW] Stage 2: Serial types & compaction tests
    ├── test_record.mojo      # [NEW] Stage 2: Table record encoding/decoding
    └── test_page_header.mojo # [NEW] Stage 2: 100-byte file header & B-Tree page headers
```

---

## Implemented Components

### 1. Serial Type Codecs ([`src/serial.mojo`](../src/serial.mojo))
- **`serial_type_len`**: Calculates binary byte size for SQLite serial types $0..14+$.
- **`get_serial_type`**: Maps a `Value` to the most compact representation:
  - Int 0 $\implies$ Type 8 (0 bytes)
  - Int 1 $\implies$ Type 9 (0 bytes)
  - $[-128..127] \implies$ Type 1 (1 byte)
  - $[-32768..32767] \implies$ Type 2 (2 bytes)
  - $[-8388608..8388607] \implies$ Type 3 (3 bytes)
  - $[-2^{31}..2^{31}-1] \implies$ Type 4 (4 bytes)
  - $[-2^{47}..2^{47}-1] \implies$ Type 5 (6 bytes)
  - Otherwise $\implies$ Type 6 (8 bytes)
  - Float $\implies$ Type 7 (IEEE 754 8 bytes)
  - Text $\implies$ Type $13 + 2N$ ($N$ bytes)
- **`encode_value` & `decode_value`**: Big-endian binary serialization and deserialization.

### 2. Record Format Engine ([`src/record.mojo`](../src/record.mojo))
- **`encode_record`**: Serializes heterogeneous rows into SQLite payload records (`[header_size_varint, st1_varint, st2_varint, ..., val1_bytes, val2_bytes, ...]`).
- **`decode_record`**: Deserializes raw payloads back into lists of typed `Value` cells.

### 3. Database File Header & B-Tree Page Headers ([`src/page_header.mojo`](../src/page_header.mojo))
- **`DbHeader`**: Encodes and decodes the 100-byte SQLite database header at offset 0 of page 1 (`"SQLite format 3\000"`, page sizes $512$–$65536$, change counters, schema cookies).
- **`PageHeader`**: 8-byte leaf and 12-byte interior page header codecs across all 4 page types:
  - `0x02` (`PAGE_TYPE_INTERIOR_INDEX`)
  - `0x05` (`PAGE_TYPE_INTERIOR_TABLE`)
  - `0x0A` (`PAGE_TYPE_LEAF_INDEX`)
  - `0x0D` (`PAGE_TYPE_LEAF_TABLE`)
- **`read_cell_pointer` & `write_cell_pointer`**: 2-byte big-endian cell pointer offsets.

---

## Verification & Test Results

### 1. Serial Type Tests ([`tests/test_serial.mojo`](../tests/test_serial.mojo))
```
=== Testing Serial Type Mapping & Compaction ===
Serial type mapping passed!
=== Testing Serial Value Encoding & Decoding Roundtrip ===
Serial roundtrip tests passed successfully!
```

### 2. Record Roundtrip Tests ([`tests/test_record.mojo`](../tests/test_record.mojo))
```
=== Testing SQLite Record Format Encoding & Decoding ===
  Encoded Record Payload Length: 31 bytes
  Decoded Columns:
    [0] ID: 101
    [1] Name: Alice Smith
    [2] Score: 98.75
    [3] Note: NULL
    [4] Active: 1
Record roundtrip test passed successfully!
```

### 3. Page Header Tests ([`tests/test_page_header.mojo`](../tests/test_page_header.mojo))
```
=== Testing SQLite 100-byte Database Header ===
  Page size: 4096
  Change counter: 1234
  DB size (pages): 42
DbHeader test passed!
=== Testing B-Tree Page Headers & Cell Pointers ===
  Leaf Table Page Header (0x0D): OK (8 bytes)
  Interior Table Page Header (0x05): OK (12 bytes, right_child=4)
  Cell Pointers (2-byte big endian offsets): OK
PageHeader tests passed successfully!
```
