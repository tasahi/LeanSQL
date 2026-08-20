# Stage 2 Specification: Storage Serialization, Record Format & Page Layout

This document provides the architectural and algorithmic specification for **Stage 2** of the SQLean (SQLite in Mojo) transcription project.

---

## 1. Overview & Objectives

In SQLite, data records (rows and index keys) and database pages are organized into binary formats optimized for minimal on-disk footprint, direct memory alignment, and cache performance.

Stage 2 translates SQLite's serialization engines into pure Mojo:
1. **Serial Type Codecs (Types 0–14+)**: Serial type length computation, binary encoding, and decoding for NULLs, 8/16/24/32/48/64-bit integers, IEEE 754 64-bit floats, constants 0 and 1, BLOBs, and UTF-8 strings.
2. **Record Format Serialization (`RecordEncoder` / `RecordDecoder`)**: Pack and unpack table record payloads (header containing varint serial types, followed by contiguous payload data).
3. **Database File Header (100-byte page 1 header)**: Parse and construct SQLite's 100-byte database header (`"SQLite format 3\0"`, page sizes $512$–$65536$, change counters, schema cookies).
4. **B-Tree Page Headers & Cell Pointers**: Decode and serialize 8-byte (leaf) and 12-byte (interior) page headers and 2-byte big-endian cell pointer arrays across all 4 page types:
   - `0x02` (`PTF_ZERODATA | PTF_INTKEY`): Interior Index Page
   - `0x05` (`PTF_INTKEY`): Interior Table Page
   - `0x0A` (`PTF_ZERODATA | PTF_LEAF`): Leaf Index Page
   - `0x0D` (`PTF_INTKEY | PTF_LEAFDATA | PTF_LEAF`): Leaf Table Page

---

## 2. SQLite Serial Type Map

SQLite encodes the data type and byte length of every column into a variable-length integer **Serial Type**:

| Serial Type | Content Size (Bytes) | Meaning / Representation |
|---|---|---|
| **0** | 0 | `NULL` value. |
| **1** | 1 | 8-bit signed two's complement integer. |
| **2** | 2 | 16-bit big-endian signed two's complement integer. |
| **3** | 3 | 24-bit big-endian signed two's complement integer. |
| **4** | 4 | 32-bit big-endian signed two's complement integer. |
| **5** | 6 | 48-bit big-endian signed two's complement integer. |
| **6** | 8 | 64-bit big-endian signed two's complement integer. |
| **7** | 8 | 64-bit IEEE 754 floating point number (big-endian). |
| **8** | 0 | Constant integer value **0** (no payload data stored). |
| **9** | 0 | Constant integer value **1** (no payload data stored). |
| **10, 11** | 0 | Reserved for internal SQLite usage. |
| **$N \ge 12$ (even)** | $(N - 12) / 2$ | BLOB of length $(N - 12) / 2$ bytes. |
| **$N \ge 13$ (odd)** | $(N - 13) / 2$ | UTF-8 String of length $(N - 13) / 2$ bytes. |

### Integer Width Optimization Rules
When encoding an integer $V$:
- $V = 0 \implies \text{Serial Type } 8$ (0 payload bytes)
- $V = 1 \implies \text{Serial Type } 9$ (0 payload bytes)
- $-128 \le V \le 127 \implies \text{Serial Type } 1$ (1 payload byte)
- $-32768 \le V \le 32767 \implies \text{Serial Type } 2$ (2 payload bytes)
- $-8388608 \le V \le 8388607 \implies \text{Serial Type } 3$ (3 payload bytes)
- $-2147483648 \le V \le 2147483647 \implies \text{Serial Type } 4$ (4 payload bytes)
- $-140737488355328 \le V \le 140737488355327 \implies \text{Serial Type } 5$ (6 payload bytes)
- Otherwise $\implies \text{Serial Type } 6$ (8 payload bytes)

---

## 3. Record Binary Layout

A single data record in SQLite is encoded as:
```
+-----------------------------------------------------------------------+
| Header Size (Varint) | Serial Type 1 | Serial Type 2 | ... | Body ... |
+-----------------------------------------------------------------------+
|<-------------------------- Header ------------------------>|<-- Data -->|
```

1. **Header Size**: A varint storing the total length of the header in bytes (including this varint).
2. **Serial Types**: An array of varints specifying the serial type of each field in column order.
3. **Body / Data**: Contiguous binary payload values concatenated in column order matching the serial types.

---

## 4. SQLite B-Tree Page Layout & Page Headers

### Page Organization
```
+-------------------------------------------------------------------+
| 100-byte File Header (Page 1 only)                                |
+-------------------------------------------------------------------+
| Page Header (8 bytes for leaves, 12 bytes for interior nodes)     |
+-------------------------------------------------------------------+
| Cell Pointer Array (2 bytes per cell, big-endian byte offsets)    |
+-------------------------------------------------------------------+
| Unallocated Space (grows downward from cell pointer array)        |
+-------------------------------------------------------------------+
| Cell Content Area (grows upward from bottom of the page)          |
+-------------------------------------------------------------------+
| Reserved Space (unused space at end of page, default 0)           |
+-------------------------------------------------------------------+
```

### Page Header Structure (Offsets from Page Start or +100 on Page 1)
| Offset | Size (Bytes) | Field Name              | Description                                                                       |
| --------| --------------| -------------------------| -----------------------------------------------------------------------------------|
| **0**  | 1            | `page_type`             | `0x02` (Int Index), `0x05` (Int Table), `0x0A` (Leaf Index), `0x0D` (Leaf Table). |
| **1**  | 2            | `first_freeblock`       | Byte offset to the first freeblock in the page (0 if none).                       |
| **3**  | 2            | `cell_count`            | Number of cells on this page.                                                     |
| **5**  | 2            | `cell_content_offset`   | Byte offset to the start of the cell content area ($0 \implies 65536$).           |
| **7**  | 1            | `fragmented_free_bytes` | Number of fragmented free bytes ($<4$ byte holes).                                |
| **8**  | 4            | `right_child_page`      | 4-byte Page Number of rightmost child (Interior pages only, omitted on leaves).   |

---

## 5. Implementation Files to Create in Stage 2

1. [`src/serial.mojo`](./src/serial.mojo):
   - `serial_type_len(serial_type: UInt32) -> Int`
   - `get_serial_type(val: Value) -> UInt32`
   - `encode_value(val: Value, p: UnsafePointer[UInt8, MutAnyOrigin]) -> Int`
   - `decode_value(serial_type: UInt32, p: UnsafePointer[UInt8, ImmutAnyOrigin]) -> Value`
2. [`src/record.mojo`](./src/record.mojo):
   - `encode_record(values: List[Value]) -> List[UInt8]`
   - `decode_record(payload: List[UInt8]) -> List[Value]`
3. [`src/page_header.mojo`](./src/page_header.mojo):
   - `DbHeader`: 100-byte file header parser and serializer.
   - `PageHeader`: 8/12-byte B-tree page header codec for all 4 page types.
4. Stage 2 Test Suites (`tests/`):
   - `test_serial.mojo`: Serial type calculation, width compaction, endianness.
   - `test_record.mojo`: Round-trip table record encoding/decoding.
   - `test_page_header.mojo`: Binary serialization of database file and page headers.
