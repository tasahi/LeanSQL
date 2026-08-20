from src.bitvec import BitVec


def test_bitvec_operations() raises:
    print("=== Testing BitVec Operations ===")
    
    var bv = BitVec(100)
    print("  Created BitVec of size:", bv.size())
    
    # 1. Initially all bits false
    for i in range(10):
        if bv.get(i):
            raise Error("Expected bit " + String(i) + " to be false initially")

    # 2. Set individual bits
    bv.set(0)
    bv.set(5)
    bv.set(31)  # word boundary
    bv.set(32)  # next word
    bv.set(99)  # last bit

    if not bv.get(0) or not bv.get(5) or not bv.get(31) or not bv.get(32) or not bv.get(99):
        raise Error("Failed to read back set bits")
    if bv.get(1) or bv.get(6) or bv.get(30) or bv.get(33) or bv.get(98):
        raise Error("Unset bit returned true")

    print("  Set and get bits passed!")

    # 3. Clear bit
    bv.clear(5)
    bv.clear(32)
    if bv.get(5) or bv.get(32):
        raise Error("Failed to clear bits 5 and 32")
    if not bv.get(0) or not bv.get(31) or not bv.get(99):
        raise Error("Clearing affected unrelated bits")

    print("  Clear bits passed!")
    print("BitVec test passed successfully!")


def main() raises:
    test_bitvec_operations()
