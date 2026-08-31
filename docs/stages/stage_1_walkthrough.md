# Walkthrough - Stage 1: Low-Level Primitives & Dual-Harness Testing

Stage 1 has translated SQLite's fundamental leaf primitives into pure Mojo 1.0. These modules have zero external dependencies and provide full byte-for-byte and behavioral parity with SQLite's internal routines.

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
│   ├── varint.mojo          # [NEW] Variable-length integer encoding & decoding (1-9 bytes)
│   ├── utf.mojo             # [NEW] UTF-8 multi-byte codecs & ASCII nocase collation
│   ├── hash.mojo            # [NEW] Knuth multiplicative string hash (0x9E3779B1)
│   ├── bitvec.mojo          # [NEW] BitVec structure for page and rowid tracking
│   └── __init__.mojo        # Public library interface
└── tests/
    ├── test_connect.mojo    # Stage 0: in-memory connection
    ├── test_crud.mojo       # Stage 0: CRUD operations
    ├── test_types.mojo      # Stage 0: type round-tripping
    ├── test_transactions.mojo # Stage 0: transactions & rollback
    ├── test_varint_diff.mojo # [NEW] Stage 1: varint boundary & 32-bit tests
    ├── test_utf.mojo         # [NEW] Stage 1: UTF-8 & NOCASE collation tests
    ├── test_hash.mojo        # [NEW] Stage 1: SQLite string hash tests
    └── test_bitvec.mojo      # [NEW] Stage 1: BitVec set/get/clear tests
```

---

## Implemented Primitives

### 1. Varint Codecs ([`src/core/varint.mojo`](../src/core/varint.mojo))
- **`put_varint` / `put_varint64`**: Full 1–9 byte encoding matching SQLite `sqlite3PutVarint`.
- **`get_varint`**: 1–9 byte decoding with bit-cancellation logic matching `sqlite3GetVarint`.
- **`get_varint32` & `put_varint32`**: Fast paths for 32-bit integers.
- **`encode_varint` & `decode_varint`**: High-level helpers returning `List[UInt8]` / `Tuple[UInt64, Int]`.

### 2. UTF Codecs & Collation ([`src/core/utf.mojo`](../src/core/utf.mojo))
- **`write_utf8` & `read_utf8`**: Encodes/decodes 1 to 4 byte UTF-8 codepoints (including ASCII, Latin, CJK, and SMP emojis).
- **`utf8_char_length`**: Computes character count by skipping continuation bytes (`(b & 0xC0) == 0x80`).
- **`nocase_compare`**: SQLite-compatible case-insensitive ASCII comparison.

### 3. String Hash ([`src/core/hash.mojo`](../src/core/hash.mojo))
- **`str_hash`**: Knuth multiplicative hash (`h = (h + (0xDF & c)) * 0x9E3779B1`) used by SQLite for identifier lookup tables.

### 4. BitVector ([`src/core/bitvec.mojo`](../src/core/bitvec.mojo))
- **`BitVec`**: Dynamic bitset with word-aligned bit operations (`set`, `get`, `clear`, `size`).

---

## Verification & Test Results

### 1. Varint Tests ([`tests/test_varint_diff.mojo`](../tests/test_varint_diff.mojo))
```
=== Testing Varint Boundary Cases ===
  Value: 0 -> 1 bytes: [0] -> Decoded OK
  Value: 1 -> 1 bytes: [1] -> Decoded OK
  Value: 127 -> 1 bytes: [127] -> Decoded OK
  Value: 128 -> 2 bytes: [129, 0] -> Decoded OK
  Value: 16383 -> 2 bytes: [255, 127] -> Decoded OK
  Value: 16384 -> 3 bytes: [129, 128, 0] -> Decoded OK
  Value: 2097151 -> 3 bytes: [255, 255, 127] -> Decoded OK
  Value: 2097152 -> 4 bytes: [129, 128, 128, 0] -> Decoded OK
  Value: 268435455 -> 4 bytes: [255, 255, 255, 127] -> Decoded OK
  Value: 268435456 -> 5 bytes: [129, 128, 128, 128, 0] -> Decoded OK
  Value: 34359738367 -> 5 bytes: [255, 255, 255, 255, 127] -> Decoded OK
  Value: 1099511627775 -> 6 bytes: [159, 255, 255, 255, 255, 127] -> Decoded OK
  Value: 2251799813685247 -> 8 bytes: [131, 255, 255, 255, 255, 255, 255, 127] -> Decoded OK
  Value: 72057594037927935 -> 8 bytes: [255, 255, 255, 255, 255, 255, 255, 127] -> Decoded OK
  Value: 9223372036854775807 -> 9 bytes: [191, 255, 255, 255, 255, 255, 255, 255, 255] -> Decoded OK
  Value: 18446744073709551615 -> 9 bytes: [255, 255, 255, 255, 255, 255, 255, 255, 255] -> Decoded OK
Varint boundary cases passed!
=== Testing Varint32 ===
  Varint32: 0 -> 1 bytes -> Decoded OK
  Varint32: 127 -> 1 bytes -> Decoded OK
  Varint32: 128 -> 2 bytes -> Decoded OK
  Varint32: 16383 -> 2 bytes -> Decoded OK
  Varint32: 16384 -> 3 bytes -> Decoded OK
  Varint32: 4294967295 -> 5 bytes -> Decoded OK
Varint32 tests passed!
```

### 2. UTF Tests ([`tests/test_utf.mojo`](../tests/test_utf.mojo))
```
=== Testing UTF-8 Codecs ===
  ASCII (0x41): write/read OK
  Latin-1 (0xE9): write/read OK
  CJK (0x8A9E): write/read OK
  Emoji (0x1F525): write/read OK
UTF-8 codecs test passed!
=== Testing SQLite NOCASE Collation ===
NOCASE collation test passed!
```

### 3. Hash Tests ([`tests/test_hash.mojo`](../tests/test_hash.mojo))
```
=== Testing SQLite Multiplicative String Hash ===
  'table': 2390805177 | 'TABLE': 2390805177 | 'Table': 2390805177
  'users': 2320498705 | 'posts': 1056586611
String hash test passed!
```

### 4. BitVec Tests ([`tests/test_bitvec.mojo`](../tests/test_bitvec.mojo))
```
=== Testing BitVec Operations ===
  Created BitVec of size: 100
  Set and get bits passed!
  Clear bits passed!
BitVec test passed successfully!
```
