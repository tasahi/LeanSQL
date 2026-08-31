from src.core.types import *
from src.engine.row import Value
from src.storage.record import encode_record, decode_record


def test_record_roundtrip() raises:
    print("=== Testing SQLite Record Format Encoding & Decoding ===")
    
    # 1. Construct a heterogeneous row: (id: 101, name: 'Alice Smith', score: 98.75, note: NULL, active: 1)
    var row_vals = List[Value]()
    row_vals.append(Value.of_int(101))
    row_vals.append(Value.of_text("Alice Smith"))
    row_vals.append(Value.of_float(98.75))
    row_vals.append(Value.of_null())
    row_vals.append(Value.of_int(1))

    # 2. Encode to raw SQLite record binary payload
    var encoded = encode_record(row_vals)
    print("  Encoded Record Payload Length:", len(encoded), "bytes")
    print("  Bytes:", encoded)

    # 3. Decode back
    var decoded = decode_record(encoded)
    if len(decoded) != len(row_vals):
        raise Error("Decoded column count mismatch! Expected: " + String(len(row_vals)) + ", got: " + String(len(decoded)))

    if decoded[0].to_int() != 101:
        raise Error("Col 0 mismatch")
    if decoded[1].to_string() != "Alice Smith":
        raise Error("Col 1 mismatch")
    if decoded[2].to_float() != 98.75:
        raise Error("Col 2 mismatch")
    if not decoded[3].is_null():
        raise Error("Col 3 should be NULL")
    if decoded[4].to_int() != 1:
        raise Error("Col 4 mismatch")

    print("  Decoded Columns:")
    print("    [0] ID:", decoded[0].to_int())
    print("    [1] Name:", decoded[1].to_string())
    print("    [2] Score:", decoded[2].to_float())
    print("    [3] Note:", decoded[3].to_string())
    print("    [4] Active:", decoded[4].to_int())

    print("Record roundtrip test passed successfully!")


def main() raises:
    test_record_roundtrip()
