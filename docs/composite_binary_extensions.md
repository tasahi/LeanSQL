# LeanSQL Composite & Binary Types Extensions

LeanSQL introduces native pure-Mojo extensions for handling composite and binary structured data inside standard SQLite columns. These extensions mirror popular SQLite counterparts without external C libraries:

1. **SQLite JSONB (`src/ext/jsonb.mojo`)**: Binary JSON serialization and tree navigation (SQLite 3.45+).
2. **MessagePack (`src/ext/msgpack.mojo`)**: Fast binary serialization format (mirroring `sqlite-msgpack`).
3. **Protocol Buffers (`src/ext/protobuf.mojo`)**: Direct wire-format field extraction (mirroring `sqlite_protobuf`).
4. **SpatiaLite / OGC Geometry (`src/ext/spatial.mojo`)**: 2D OpenGIS Well-Known Binary (WKB) point geometry and spatial calculation.

---

## 1. SQLite JSONB Extension

Provides binary JSON format packing and path extraction without string re-parsing.

### SQL Functions
- `jsonb(json_text: TEXT) -> BLOB/HEX`
  Converts standard JSON text into a binary JSONB tagged layout.
- `json(jsonb_blob: BLOB/HEX) -> TEXT`
  Converts a JSONB payload back to human-readable JSON string.
- `jsonb_extract(jsonb_blob: BLOB/HEX, path: TEXT) -> VALUE`
  Extracts a value by path (e.g. `'$.user.address'`, `'$.items[0]'`).

### Example
```sql
-- Store binary JSONB in table
CREATE TABLE products (id INT PRIMARY KEY, details TEXT);
INSERT INTO products VALUES (1, jsonb('{"brand": "Acme", "specs": {"weight": 1.5, "in_stock": true}}'));

-- Extract fields
SELECT id, jsonb_extract(details, '$.specs.weight') AS weight
FROM products
WHERE jsonb_extract(details, '$.specs.in_stock') = 1;

-- Convert back to JSON
SELECT json(details) FROM products;
```

---

## 2. MessagePack Extension (`sqlite-msgpack`)

Encodes tuples, structs, and key-value maps as standard MessagePack payloads.

### SQL Functions
- `msgpack_pack(val1, val2, ...) -> BLOB/HEX`
  Packs positional values into a MessagePack array.
- `msgpack_map(k1, v1, k2, v2, ...) -> BLOB/HEX`
  Packs key/value pairs into a MessagePack map.
- `msgpack_extract(msgpack_blob, key_or_index) -> VALUE`
  Extracts a field by map key string or array index (0-based).

### Example
```sql
-- Pack a record struct
SELECT msgpack_pack(101, 'Mojo Kernel', 99.5) AS record_blob;

-- Pack a map and extract
SELECT msgpack_extract(msgpack_map('user', 'alice', 'role', 'admin'), 'role');
-- Returns: 'admin'

-- Extract array element
SELECT msgpack_extract(msgpack_pack(10, 20, 30), '1');
-- Returns: 20
```

---

## 3. Protocol Buffers Wire Format Extension (`sqlite_protobuf`)

Reads fields directly from Google Protobuf binary wire format without requiring compiled `.proto` descriptor files.

### SQL Functions
- `pb_extract_int(pb_blob, field_number: INT) -> INT`
  Extracts VarInt (wire type 0) or 32/64-bit integer by tag number.
- `pb_extract_float(pb_blob, field_number: INT) -> REAL`
  Extracts floating point (wire type 1 or 5) by tag number.
- `pb_extract_string(pb_blob, field_number: INT) -> TEXT`
  Extracts length-delimited string/bytes (wire type 2) by tag number.

### Example
```sql
-- pb_hex contains tag 1 = 150 (varint), tag 2 = 'test' (string)
SELECT pb_extract_int('089601120474657374', 1);     -- Returns: 150
SELECT pb_extract_string('089601120474657374', 2);  -- Returns: 'test'
```

---

## 4. SpatiaLite / OGC Geometry Extension (`src/ext/spatial.mojo`)

Implements OpenGIS Well-Known Binary (WKB) standard 2D point geometry and spatial queries.

### SQL Functions
- `ST_Point(x: REAL, y: REAL) -> BLOB/HEX`
  Encodes a 21-byte Little-Endian OGC WKB Point geometry.
- `ST_X(geom_blob) -> REAL`
  Retrieves the X coordinate.
- `ST_Y(geom_blob) -> REAL`
  Retrieves the Y coordinate.
- `ST_Distance(g1_blob, g2_blob) -> REAL`
  Calculates Euclidean distance between two geometries: $\sqrt{(x_1 - x_2)^2 + (y_1 - y_2)^2}$.
- `ST_AsText(geom_blob) -> TEXT`
  Formats geometry as Well-Known Text (WKT), e.g. `'POINT(10.0 20.0)'`.

### Example
```sql
CREATE TABLE points_of_interest (id INT PRIMARY KEY, name TEXT, geom TEXT);

-- Insert Points
INSERT INTO points_of_interest VALUES (1, 'Station Alpha', ST_Point(0.0, 0.0));
INSERT INTO points_of_interest VALUES (2, 'Station Beta', ST_Point(3.0, 4.0));

-- Query nearest station using spatial distance
SELECT name, ST_Distance(geom, ST_Point(0.0, 0.0)) AS distance
FROM points_of_interest
ORDER BY distance ASC;

-- WKT formatting
SELECT ST_AsText(geom) FROM points_of_interest;
-- Returns: 'POINT(0.0 0.0)', 'POINT(3.0 4.0)'
```

