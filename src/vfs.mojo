""" SQLite Virtual File System (VFS) and OS Portability Layer.

Corresponds to `sqlite3_vfs`, `sqlite3_io_methods`, and the default OS VFS implementations
in `sqlite/src/os.c`, `sqlite/src/os_unix.c`, and `sqlite/src/os_win.c`.

Defines:
- `VFS`: The OS interface abstraction factory
- `MemFile`: Zero-copy, in-memory file implementation (for `:memory:` and temporary databases)
- `DiskFile`: POSIX/Win32 disk-backed file implementation with locking primitives
"""

from std.ffi import c_char, c_int, c_long, external_call
from std.memory import Pointer
from src.types import *


# POSIX constants
comptime O_RDONLY: c_int = 0
comptime O_WRONLY: c_int = 1
comptime O_RDWR: c_int = 2
comptime O_CREAT: c_int = 64
comptime O_TRUNC: c_int = 512

comptime SEEK_SET: c_int = 0
comptime SEEK_CUR: c_int = 1
comptime SEEK_END: c_int = 2

# SQLite File Locking Levels (corresponds to `sqlite/src/os.h`)
comptime NO_LOCK: Int = 0
comptime SHARED_LOCK: Int = 1
comptime RESERVED_LOCK: Int = 2
comptime PENDING_LOCK: Int = 3
comptime EXCLUSIVE_LOCK: Int = 4


def _make_c_path(path: String) -> List[UInt8]:
    """Helper to convert a String to a null-terminated byte buffer."""
    var b = path.as_bytes()
    var buf = List[UInt8]()
    for i in range(len(b)):
        buf.append(b[i])
    buf.append(0)
    return buf^


struct MemFile(Movable):
    """In-memory file implementation for temporary and :memory: databases."""
    var _data: List[UInt8]
    var _lock_level: Int

    def __init__(out self):
        self._data = List[UInt8]()
        self._lock_level = NO_LOCK

    def __init__(out self, *, deinit move: Self):
        self._data = move._data^
        self._lock_level = move._lock_level

    def read[origin: Origin[mut=True]](self, offset: Int64, amount: Int, p_dest: Pointer[UInt8, origin]) -> Int:
        """Reads up to `amount` bytes starting at `offset` into `p_dest`."""
        var n_total = len(self._data)
        var off = Int(offset)
        if off >= n_total:
            return 0
        var can_read = amount if (off + amount <= n_total) else (n_total - off)
        for i in range(can_read):
            p_dest[unsafe_offset=i] = self._data[off + i]
        return can_read

    def write[origin: Origin](mut self, offset: Int64, amount: Int, p_src: Pointer[UInt8, origin]) -> Int:
        """Writes `amount` bytes from `p_src` starting at `offset`."""
        var off = Int(offset)
        var needed_size = off + amount
        while len(self._data) < needed_size:
            self._data.append(0)
        for i in range(amount):
            self._data[off + i] = p_src[unsafe_offset=i]
        return amount

    def truncate(mut self, size: Int64):
        """Truncates or extends the file to `size` bytes."""
        var sz = Int(size)
        if sz < len(self._data):
            var new_data = List[UInt8]()
            for i in range(sz):
                new_data.append(self._data[i])
            self._data = new_data^
        else:
            while len(self._data) < sz:
                self._data.append(0)

    def file_size(self) -> Int64:
        """Returns the current size of the in-memory file in bytes."""
        return Int64(len(self._data))

    def lock(mut self, lock_level: Int) -> Bool:
        """Sets the lock level (simulated in-memory)."""
        self._lock_level = lock_level
        return True

    def unlock(mut self, lock_level: Int) -> Bool:
        """Lowers the lock level."""
        self._lock_level = lock_level
        return True

    def lock_level(self) -> Int:
        return self._lock_level


struct DiskFile(Movable):
    """POSIX file descriptor wrapper."""
    var _fd: Int
    var _path: String
    var _lock_level: Int

    def __init__(out self, path: String, read_only: Bool, create: Bool) raises:
        self._path = path
        self._lock_level = NO_LOCK
        
        var flags = O_RDWR
        if read_only:
            flags = O_RDONLY
        if create:
            flags |= O_CREAT

        var c_path_buf = _make_c_path(path)
        var c_path = Pointer[c_char, ImmutAnyOrigin](unsafe_from_address=Int(c_path_buf.unsafe_ptr()))

        var fd = external_call["open", c_int, Pointer[c_char, ImmutAnyOrigin], c_int, c_int](
            c_path, c_int(flags), c_int(0o644)
        )

        if Int(fd) < 0:
            raise Error("Failed to open file: " + path)
        self._fd = Int(fd)

    def __init__(out self, *, deinit move: Self):
        self._fd = move._fd
        self._path = move._path
        self._lock_level = move._lock_level

    def read[origin: Origin[mut=True]](self, offset: Int64, amount: Int, p_dest: Pointer[UInt8, origin]) raises -> Int:
        """Reads `amount` bytes starting at `offset` into `p_dest`."""
        var seek_res = external_call["lseek", c_long, c_int, c_long, c_int](
            c_int(self._fd), c_long(offset), c_int(SEEK_SET)
        )
        if Int(seek_res) < 0:
            raise Error("lseek failed for file: " + self._path)

        var p_dest_mut = Pointer[NoneType, MutAnyOrigin](unsafe_from_address=Int(p_dest))
        var n_read = external_call["read", Int, Int, Pointer[NoneType, MutAnyOrigin], Int](
            self._fd, p_dest_mut, amount
        )
        return n_read

    def write[origin: Origin](self, offset: Int64, amount: Int, p_src: Pointer[UInt8, origin]) raises -> Int:
        """Writes `amount` bytes from `p_src` starting at `offset`."""
        var seek_res = external_call["lseek", c_long, c_int, c_long, c_int](
            c_int(self._fd), c_long(offset), c_int(SEEK_SET)
        )
        if Int(seek_res) < 0:
            raise Error("lseek failed for file: " + self._path)

        var mut_ptr = Pointer[NoneType, MutAnyOrigin](unsafe_from_address=Int(p_src))
        var n_written = external_call["write", Int, Int, Pointer[NoneType, MutAnyOrigin], Int](
            self._fd, mut_ptr, amount
        )
        return n_written

    def truncate(self, size: Int64) raises:
        """Truncates file to `size` bytes."""
        var res = external_call["ftruncate", c_int, c_int, c_long](
            c_int(self._fd), c_long(size)
        )
        if Int(res) != 0:
            raise Error("ftruncate failed for file: " + self._path)

    def file_size(self) -> Int64:
        """Returns the file size in bytes using lseek."""
        var cur = external_call["lseek", c_long, c_int, c_long, c_int](
            c_int(self._fd), c_long(0), c_int(SEEK_CUR)
        )
        var sz = external_call["lseek", c_long, c_int, c_long, c_int](
            c_int(self._fd), c_long(0), c_int(SEEK_END)
        )
        _ = external_call["lseek", c_long, c_int, c_long, c_int](
            c_int(self._fd), cur, c_int(SEEK_SET)
        )
        return Int64(sz)

    def sync(self) raises:
        """Flushes written buffers to physical storage."""
        var res = external_call["fsync", c_int, c_int](c_int(self._fd))
        if Int(res) != 0:
            raise Error("fsync failed for file: " + self._path)

    def close(mut self):
        """Closes the underlying file descriptor."""
        if self._fd >= 0:
            _ = external_call["close", c_int, c_int](c_int(self._fd))
            self._fd = -1

    def lock(mut self, lock_level: Int) -> Bool:
        """Simulates POSIX locking transitions."""
        if lock_level > self._lock_level:
            self._lock_level = lock_level
            return True
        return True

    def unlock(mut self, lock_level: Int) -> Bool:
        """Lowers lock level."""
        if lock_level < self._lock_level:
            self._lock_level = lock_level
            return True
        return True

    def lock_level(self) -> Int:
        return self._lock_level


struct VFS:
    """The central VFS interface dispatcher."""
    var vfs_name: String
    var max_pathname: Int

    def __init__(out self, name: String = "unix"):
        self.vfs_name = name
        self.max_pathname = 1024

    def open_disk(self, path: String, read_only: Bool = False, create: Bool = True) raises -> DiskFile:
        """Opens a disk-backed file."""
        return DiskFile(path, read_only, create)

    def open_memory(self) -> MemFile:
        """Opens an anonymous in-memory file."""
        return MemFile()

    def delete_file(self, path: String) raises:
        """Deletes a file from the filesystem."""
        var c_path_buf = _make_c_path(path)
        var c_path = Pointer[c_char, ImmutAnyOrigin](unsafe_from_address=Int(c_path_buf.unsafe_ptr()))
        var res = external_call["unlink", c_int, Pointer[c_char, ImmutAnyOrigin]](c_path)
        if Int(res) != 0:
            raise Error("unlink failed for file: " + path)

    def file_exists(self, path: String) -> Bool:
        """Returns True if the file exists."""
        var c_path_buf = _make_c_path(path)
        var c_path = Pointer[c_char, ImmutAnyOrigin](unsafe_from_address=Int(c_path_buf.unsafe_ptr()))
        var res = external_call["access", c_int, Pointer[c_char, ImmutAnyOrigin], c_int](c_path, c_int(0))
        return Int(res) == 0
