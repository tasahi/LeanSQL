from std.memory import alloc, UnsafePointer
from src.core.types import *
from src.vfs.vfs_os import VFS, MemFile, NO_LOCK, SHARED_LOCK, RESERVED_LOCK, EXCLUSIVE_LOCK


def test_memfile() raises:
    print("=== Testing MemFile Operations ===")
    var f = MemFile()
    var p = alloc[UInt8](64)

    # 1. Write data at offset 0
    p[0] = 0xAA
    p[1] = 0xBB
    p[2] = 0xCC
    var immut_p = UnsafePointer[UInt8, ImmutAnyOrigin](other=p)
    var n1 = f.write(0, 3, immut_p)
    if n1 != 3 or f.file_size() != 3:
        p.free()
        raise Error("MemFile write failed")

    # 2. Write data with gap (offset 10)
    p[0] = 0xFF
    var n2 = f.write(10, 1, immut_p)
    if n2 != 1 or f.file_size() != 11:
        p.free()
        raise Error("MemFile sparse write failed")

    # 3. Read back
    var p_read = alloc[UInt8](64)
    var nr = f.read(0, 4, p_read)
    if nr != 4 or p_read[0] != 0xAA or p_read[1] != 0xBB or p_read[2] != 0xCC or p_read[3] != 0:
        p.free()
        p_read.free()
        raise Error("MemFile read back mismatch")

    # 4. Truncate
    f.truncate(2)
    if f.file_size() != 2:
        p.free()
        p_read.free()
        raise Error("MemFile truncate failed")

    # 5. Locks
    _ = f.lock(SHARED_LOCK)
    if f.lock_level() != SHARED_LOCK:
        p.free()
        p_read.free()
        raise Error("MemFile lock level mismatch")
    _ = f.unlock(NO_LOCK)

    p.free()
    p_read.free()
    print("MemFile test passed successfully!")


def test_vfs() raises:
    print("=== Testing VFS Factory ===")
    var vfs = VFS("test_vfs")
    var mem = vfs.open_memory()
    if mem.file_size() != 0:
        raise Error("VFS open_memory should create empty file")
    print("VFS factory test passed successfully!")


def main() raises:
    test_memfile()
    test_vfs()
