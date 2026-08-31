from std.memory import alloc, UnsafePointer
from src.core.types import *
from src.core.utf import read_utf8, write_utf8, utf8_char_length, nocase_compare


def test_utf8_codecs() raises:
    print("=== Testing UTF-8 Codecs ===")
    var p = alloc[UInt8](10)

    # 1. ASCII (1 byte) - 'A' = 0x41
    var n1 = write_utf8(p, 0x41)
    if n1 != 1 or p[0] != 0x41:
        p.free()
        raise Error("UTF-8 1-byte write failed")
    var immut_p = UnsafePointer[UInt8, ImmutAnyOrigin](other=p)
    var cp1: UInt32 = 0
    var r1 = read_utf8(immut_p, cp1)
    if r1 != 1 or cp1 != 0x41:
        p.free()
        raise Error("UTF-8 1-byte read failed")
    print("  ASCII (0x41): write/read OK")

    # 2. 2-byte UTF-8 - 'é' = 0xE9
    var n2 = write_utf8(p, 0xE9)
    if n2 != 2:
        p.free()
        raise Error("UTF-8 2-byte write failed")
    var cp2: UInt32 = 0
    var r2 = read_utf8(immut_p, cp2)
    if r2 != 2 or cp2 != 0xE9:
        p.free()
        raise Error("UTF-8 2-byte read failed")
    print("  Latin-1 (0xE9): write/read OK")

    # 3. 3-byte UTF-8 - '語' = 0x8A9E
    var n3 = write_utf8(p, 0x8A9E)
    if n3 != 3:
        p.free()
        raise Error("UTF-8 3-byte write failed")
    var cp3: UInt32 = 0
    var r3 = read_utf8(immut_p, cp3)
    if r3 != 3 or cp3 != 0x8A9E:
        p.free()
        raise Error("UTF-8 3-byte read failed")
    print("  CJK (0x8A9E): write/read OK")

    # 4. 4-byte UTF-8 - '🔥' = 0x1F525
    var n4 = write_utf8(p, 0x1F525)
    if n4 != 4:
        p.free()
        raise Error("UTF-8 4-byte write failed")
    var cp4: UInt32 = 0
    var r4 = read_utf8(immut_p, cp4)
    if r4 != 4 or cp4 != 0x1F525:
        p.free()
        raise Error("UTF-8 4-byte read failed")
    print("  Emoji (0x1F525): write/read OK")

    p.free()
    print("UTF-8 codecs test passed!")


def test_nocase_collation() raises:
    print("=== Testing SQLite NOCASE Collation ===")
    if nocase_compare("table", "TABLE") != 0:
        raise Error("NOCASE compare failed for 'table' vs 'TABLE'")
    if nocase_compare("Alice", "alice") != 0:
        raise Error("NOCASE compare failed for 'Alice' vs 'alice'")
    if nocase_compare("abc", "abd") >= 0:
        raise Error("NOCASE ordering failed for 'abc' < 'abd'")
    if nocase_compare("abd", "abc") <= 0:
        raise Error("NOCASE ordering failed for 'abd' > 'abc'")
    if nocase_compare("abc", "abcd") >= 0:
        raise Error("NOCASE prefix compare failed")
    print("NOCASE collation test passed!")


def main() raises:
    test_utf8_codecs()
    test_nocase_collation()
