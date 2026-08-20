from std.memory import alloc, UnsafePointer
from src.types import *
from src.row import Value
from src.serial import get_serial_type, serial_type_len, encode_value, decode_value


def test_serial_type_mapping() raises:
    print("=== Testing Serial Type Mapping & Compaction ===")
    
    # 1. NULL
    var v_null = Value.of_null()
    if get_serial_type(v_null) != 0 or serial_type_len(0) != 0:
        raise Error("Serial type for NULL failed")

    # 2. Integer Constants (0 and 1)
    var v_0 = Value.of_int(0)
    var v_1 = Value.of_int(1)
    if get_serial_type(v_0) != 8 or serial_type_len(8) != 0:
        raise Error("Serial type for int 0 failed")
    if get_serial_type(v_1) != 9 or serial_type_len(9) != 0:
        raise Error("Serial type for int 1 failed")

    # 3. 1-byte Int
    var v_i8 = Value.of_int(42)
    if get_serial_type(v_i8) != 1 or serial_type_len(1) != 1:
        raise Error("Serial type for 1-byte int failed")

    # 4. 2-byte Int
    var v_i16 = Value.of_int(1000)
    if get_serial_type(v_i16) != 2 or serial_type_len(2) != 2:
        raise Error("Serial type for 2-byte int failed")

    # 5. 3-byte Int
    var v_i24 = Value.of_int(100000)
    if get_serial_type(v_i24) != 3 or serial_type_len(3) != 3:
        raise Error("Serial type for 3-byte int failed")

    # 6. 4-byte Int
    var v_i32 = Value.of_int(10000000)
    if get_serial_type(v_i32) != 4 or serial_type_len(4) != 4:
        raise Error("Serial type for 4-byte int failed")

    # 7. 6-byte Int
    var v_i48 = Value.of_int(1000000000000)
    if get_serial_type(v_i48) != 5 or serial_type_len(5) != 6:
        raise Error("Serial type for 6-byte int failed")

    # 8. 8-byte Int
    var v_i64 = Value.of_int(9223372036854775807)
    if get_serial_type(v_i64) != 6 or serial_type_len(6) != 8:
        raise Error("Serial type for 8-byte int failed")

    # 9. Float
    var v_f = Value.of_float(3.14159)
    if get_serial_type(v_f) != 7 or serial_type_len(7) != 8:
        raise Error("Serial type for float failed")

    # 10. String: "hello" (length 5) -> serial type = 13 + 2*5 = 23
    var v_str = Value.of_text("hello")
    if get_serial_type(v_str) != 23 or serial_type_len(23) != 5:
        raise Error("Serial type for string failed")

    print("Serial type mapping passed!")


def test_serial_roundtrip() raises:
    print("=== Testing Serial Value Encoding & Decoding Roundtrip ===")
    var p = alloc[UInt8](64)

    # Test numbers across boundary ranges
    var test_ints = List[Int64]()
    test_ints.append(0)
    test_ints.append(1)
    test_ints.append(-1)
    test_ints.append(127)
    test_ints.append(-128)
    test_ints.append(32767)
    test_ints.append(-32768)
    test_ints.append(8388607)
    test_ints.append(-8388608)
    test_ints.append(2147483647)
    test_ints.append(-2147483648)
    test_ints.append(140737488355327)
    test_ints.append(-140737488355328)
    test_ints.append(9223372036854775807)
    test_ints.append(-9223372036854775807 - 1)

    for i in range(len(test_ints)):
        var num = test_ints[i]
        var val = Value.of_int(num)
        var st = get_serial_type(val)
        var n_written = encode_value(val, p)
        if n_written != serial_type_len(st):
            p.free()
            raise Error("Encoded size mismatch for int " + String(num))

        var immut_p = UnsafePointer[UInt8, ImmutAnyOrigin](other=p)
        var decoded = decode_value(st, immut_p)
        if decoded.to_int() != num:
            p.free()
            raise Error("Value roundtrip mismatch for int " + String(num) + ", got: " + String(decoded.to_int()))

    # Test Float
    var val_float = Value.of_float(2.718281828459045)
    var st_f = get_serial_type(val_float)
    var n_f = encode_value(val_float, p)
    var immut_p_f = UnsafePointer[UInt8, ImmutAnyOrigin](other=p)
    var dec_f = decode_value(st_f, immut_p_f)
    if dec_f.to_float() != 2.718281828459045:
        p.free()
        raise Error("Float roundtrip mismatch")

    # Test Text
    var val_txt = Value.of_text("🔥 Mojo SQLean 🔥")
    var st_txt = get_serial_type(val_txt)
    var n_txt = encode_value(val_txt, p)
    var immut_p_txt = UnsafePointer[UInt8, ImmutAnyOrigin](other=p)
    var dec_txt = decode_value(st_txt, immut_p_txt)
    if dec_txt.to_string() != "🔥 Mojo SQLean 🔥":
        p.free()
        raise Error("Text roundtrip mismatch")

    p.free()
    print("Serial roundtrip tests passed successfully!")


def main() raises:
    test_serial_type_mapping()
    test_serial_roundtrip()
