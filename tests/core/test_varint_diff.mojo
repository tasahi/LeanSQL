from std.memory import alloc, UnsafePointer
from src.core.types import *
from src.core.varint import put_varint, get_varint, get_varint32, put_varint32, encode_varint, decode_varint


def test_varint_boundary_cases() raises:
    print("=== Testing Varint Boundary Cases ===")
    
    # Boundary values for 1, 2, 3, 4, ..., 9 byte varints
    var test_values = List[UInt64]()
    test_values.append(0)
    test_values.append(1)
    test_values.append(0x7F)                      # 1 byte max: 127
    test_values.append(0x80)                      # 2 byte min: 128
    test_values.append(0x3FFF)                    # 2 byte max: 16,383
    test_values.append(0x4000)                    # 3 byte min: 16,384
    test_values.append(0x1FFFFF)                  # 3 byte max: 2,097,151
    test_values.append(0x200000)                  # 4 byte min
    test_values.append(0xFFFFFFF)                 # 4 byte max
    test_values.append(0x10000000)                # 5 byte min
    test_values.append(0x7FFFFFFFF)               # 5 byte max
    test_values.append(0xFFFFFFFFFF)              # 6 byte max
    test_values.append(0x7FFFFFFFFFFFF)           # 7 byte max
    test_values.append(0xFFFFFFFFFFFFFF)          # 8 byte max
    test_values.append(0x7FFFFFFFFFFFFFFF)        # 9 byte min with top bit 0
    test_values.append(0xFFFFFFFFFFFFFFFF)        # 9 byte max: 18,446,744,073,709,551,615

    for i in range(len(test_values)):
        var val = test_values[i]
        var encoded = encode_varint(val)
        var decoded_tuple = decode_varint(encoded)
        var decoded_val = decoded_tuple[0]
        var decoded_len = decoded_tuple[1]

        if decoded_val != val:
            raise Error("Varint roundtrip mismatch! Expected: " + String(val) + ", Got: " + String(decoded_val))
        if decoded_len != len(encoded):
            raise Error("Varint length mismatch! Encoded: " + String(len(encoded)) + ", Read: " + String(decoded_len))
        print("  Value:", val, "->", len(encoded), "bytes:", encoded, "-> Decoded OK")

    print("Varint boundary cases passed!")


def test_varint32() raises:
    print("=== Testing Varint32 ===")
    var p = alloc[UInt8](10)
    var test_vals = List[UInt32]()
    test_vals.append(0)
    test_vals.append(127)
    test_vals.append(128)
    test_vals.append(16383)
    test_vals.append(16384)
    test_vals.append(0xFFFFFFFF)

    for i in range(len(test_vals)):
        var v = test_vals[i]
        var n_written = put_varint32(p, v)
        var immut_p = UnsafePointer[UInt8, ImmutAnyOrigin](other=p)
        var v_out: UInt32 = 0
        var n_read = get_varint32(immut_p, v_out)
        if v_out != v:
            p.free()
            raise Error("Varint32 mismatch! Expected " + String(v) + " got " + String(v_out))
        if n_read != n_written:
            p.free()
            raise Error("Varint32 length mismatch!")
        print("  Varint32:", v, "->", n_written, "bytes -> Decoded OK")

    p.free()
    print("Varint32 tests passed!")


def main() raises:
    test_varint_boundary_cases()
    test_varint32()
