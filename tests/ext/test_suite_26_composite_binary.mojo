from tests.harness import TestHarness
from src.engine.connection import connect


def run_composite_binary_tests(mut h: TestHarness) raises:
    print("\n===================================================================")
    print("=== Suite 26: Composite & Binary Types (JSONB, MsgPack, PB, ST) ===")
    print("===================================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    # ---------------------------------------------------------
    # 1. SQLite JSONB Binary Extension Tests
    # ---------------------------------------------------------
    cur.execute("SELECT jsonb('{\"name\": \"Alice\", \"age\": 30, \"active\": true, \"scores\": [95, 99]}')")
    var r = cur.fetchone()
    h.assert_true("jsonb-1.1a", r.__bool__(), "jsonb() returned row")
    var hex_jsonb = r.value().get_string(0)
    h.assert_true("jsonb-1.1b", hex_jsonb.byte_length() > 0, "jsonb() returns binary hex string")

    # Extract fields directly from JSONB
    cur.execute("SELECT jsonb_extract(jsonb('{\"city\": \"London\", \"population\": 9000000}'), '$.city')")
    r = cur.fetchone()
    h.assert_equal("jsonb-1.2a", r.value().get_string(0), "London", "jsonb_extract extracts string from JSONB")

    cur.execute("SELECT jsonb_extract(jsonb('{\"values\": [10, 20, 30]}'), '$.values.1')")
    r = cur.fetchone()
    h.assert_equal_int("jsonb-1.2b", r.value().get_int(0), 20, "jsonb_extract extracts array index from JSONB")

    # Roundtrip JSONB -> JSON
    cur.execute("SELECT json(jsonb('{\"key\": \"value\"}'))")
    r = cur.fetchone()
    h.assert_equal("jsonb-1.3", r.value().get_string(0), "{\"key\": \"value\"}", "json(jsonb(...)) roundtrips to standard JSON")

    # ---------------------------------------------------------
    # 2. MessagePack Binary Extension Tests
    # ---------------------------------------------------------
    cur.execute("SELECT msgpack_pack(10, 'Mojo', 3.1415)")
    r = cur.fetchone()
    h.assert_true("msgpack-2.1a", r.__bool__(), "msgpack_pack returns a row")
    var mp_arr = r.value().get_string(0)

    cur.execute("SELECT msgpack_extract(msgpack_pack(10, 'Mojo', 3.1415), '1')")
    r = cur.fetchone()
    h.assert_equal("msgpack-2.1b", r.value().get_string(0), "Mojo", "msgpack_extract extracts array index 1")

    # MessagePack Map
    cur.execute("SELECT msgpack_map('user', 'admin', 'role_id', 42)")
    r = cur.fetchone()
    var mp_map = r.value().get_string(0)

    cur.execute("SELECT msgpack_extract(msgpack_map('user', 'admin', 'role_id', 42), 'role_id')")
    r = cur.fetchone()
    h.assert_equal_int("msgpack-2.2", r.value().get_int(0), 42, "msgpack_extract extracts map field 'role_id'")

    # ---------------------------------------------------------
    # 3. Protocol Buffers Wire Format Tests
    # ---------------------------------------------------------
    # Construct sample Protobuf message in hex:
    # Field 1 (tag 1, wire type 0 = varint): tag byte (1<<3|0 = 0x08), value 150 (0x96 0x01)
    # Field 2 (tag 2, wire type 2 = string): tag byte (2<<3|2 = 0x12), len 4 (0x04), "test" (0x74 0x65 0x73 0x74)
    var pb_hex = "089601120474657374"
    cur.execute("SELECT pb_extract_int('" + pb_hex + "', 1), pb_extract_string('" + pb_hex + "', 2)")
    r = cur.fetchone()
    h.assert_equal_int("pb-3.1a", r.value().get_int(0), 150, "pb_extract_int extracts varint tag 1")
    h.assert_equal("pb-3.1b", r.value().get_string(1), "test", "pb_extract_string extracts string tag 2")

    # ---------------------------------------------------------
    # 4. SpatiaLite / OGC Geometry Tests
    # ---------------------------------------------------------
    cur.execute("SELECT ST_Point(12.5, 45.0)")
    r = cur.fetchone()
    h.assert_true("spatial-4.1a", r.__bool__(), "ST_Point returns row")
    var geom_hex = r.value().get_string(0)
    # 21 bytes = 42 hex chars
    h.assert_equal_int("spatial-4.1b", geom_hex.byte_length(), 42, "OGC WKB Point is exactly 21 bytes / 42 hex chars")

    cur.execute("SELECT ST_X(ST_Point(12.5, 45.0)), ST_Y(ST_Point(12.5, 45.0))")
    r = cur.fetchone()
    h.assert_true("spatial-4.2a", abs(r.value().get_float(0) - 12.5) < 0.0001, "ST_X retrieves 12.5")
    h.assert_true("spatial-4.2b", abs(r.value().get_float(1) - 45.0) < 0.0001, "ST_Y retrieves 45.0")

    # ST_Distance: (0, 0) to (3, 4) -> 5.0
    cur.execute("SELECT ST_Distance(ST_Point(0.0, 0.0), ST_Point(3.0, 4.0))")
    r = cur.fetchone()
    h.assert_true("spatial-4.3", abs(r.value().get_float(0) - 5.0) < 0.0001, "ST_Distance between (0,0) and (3,4) is 5.0")

    # ST_AsText
    cur.execute("SELECT ST_AsText(ST_Point(10.0, 20.0))")
    r = cur.fetchone()
    h.assert_equal("spatial-4.4", r.value().get_string(0), "POINT(10.0 20.0)", "ST_AsText formats WKT point")

    # ---------------------------------------------------------
    # 5. Table Integration: Composite Column in Table & Filter
    # ---------------------------------------------------------
    cur.execute("CREATE TABLE locations (id INT PRIMARY KEY, name TEXT, geom TEXT, props TEXT)")
    cur.execute("INSERT INTO locations VALUES (1, 'Station A', ST_Point(0.0, 0.0), jsonb('{\"zone\": 1, \"active\": true}'))")
    cur.execute("INSERT INTO locations VALUES (2, 'Station B', ST_Point(6.0, 8.0), jsonb('{\"zone\": 2, \"active\": false}'))")
    cur.execute("INSERT INTO locations VALUES (3, 'Station C', ST_Point(3.0, 4.0), jsonb('{\"zone\": 1, \"active\": true}'))")

    # Query with Spatial Distance and JSONB filtering
    cur.execute("""
        SELECT name, ST_Distance(geom, ST_Point(0.0, 0.0)) AS dist
        FROM locations
        WHERE jsonb_extract(props, '$.zone') = 1
        ORDER BY dist ASC
    """)
    var rows = cur.fetchall()
    h.assert_equal_int("table-5.1a", len(rows), 2, "2 locations in zone 1")
    h.assert_equal("table-5.1b", rows[0].get_string(0), "Station A", "Closest is Station A (dist 0.0)")
    h.assert_equal("table-5.1c", rows[1].get_string(0), "Station C", "Next is Station C (dist 5.0)")

    cur.close()
    con.close()


def main() raises:
    var h = TestHarness("Suite 26 - Composite & Binary Types")
    run_composite_binary_tests(h)
    h.summary()
