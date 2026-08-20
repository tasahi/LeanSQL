"""Virtual File System (VFS) and POSIX File IO Abstraction.

Corresponds to `sqlite/src/os.h`, `sqlite/src/os.c`, and `sqlite/src/os_unix.c`.

Provides:
- `FileLock`: SQLite 5-level concurrency locks (NONE, SHARED, RESERVED, PENDING, EXCLUSIVE).
- `MemFile`: Dynamic in-memory simulated file for `:memory:` databases and journals.
- `DiskFile`: POSIX libc file wrapper via libc syscalls (`open`, `read`, `write`, `lseek`, `close`, `unlink`).
- `VFS`: File opening, existence check, deletion, and random byte generator.
"""

from std.ffi import external_call, c_char, c_int, c_long
from std.memory import UnsafePointer, alloc
from src.types import *

# === SQLite File Lock Levels ===
comptime NO_LOCK = 0
comptime SHARED_LOCK = 1
comptime RESERVED_LOCK = 2
comptime PENDING_LOCK = 3
comptime EXCLUSIVE_LOCK = 4

# === POSIX open() flags ===
comptime O_RDONLY = 0
comptime O_WRONLY = 1
comptime O_RDWR = 2
comptime O_CREAT = 64
comptime O_TRUNC = 512

# === POSIX lseek() whence ===
comptime SEEK_SET = 0
comptime SEEK_CUR = 1
comptime SEEK_END = 2


struct MemFile(ImplicitlyCopyable, Copyable, Movable):
    """In-memory simulated file supporting seeking, writing, and truncating."""
    var _data: List[UInt8]
    var _lock_level: Int

    def __init__(out self):
        self._data = List[UInt8]()
        self._lock_level = NO_LOCK

    def __init__(out self, *, copy: Self):
        self._data = copy._data.copy()
        self._lock_level = copy._lock_level

    def __init__(out self, *, deinit move: Self):
        self._data = move._data^
        self._lock_level = move._lock_level

    def read(self, offset: Int64, amount: Int, p_dest: UnsafePointer[UInt8, MutAnyOrigin]) -> Int:
        """Reads up to `amount` bytes starting at `offset` into `p_dest`."""
        var n_total = len(self._data)
        var off = Int(offset)
        if off >= n_total:
            return 0
        var can_read = amount if (off + amount <= n_total) else (n_total - off)
        for i in range(can_read):
            p_dest[i] = self._data[off + i]
        return can_read

    def write(mut self, offset: Int64, amount: Int, p_src: UnsafePointer[UInt8, ImmutAnyOrigin]) -> Int:
        """Writes `amount` bytes from `p_src` starting at `offset`."""
        var off = Int(offset)
        var needed_size = off + amount
        while len(self._data) < needed_size:
            self._data.append(0)
        for i in range(amount):
            self._data[off + i] = p_src[i]
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

        var c_path = alloc[c_char](path.byte_length() + 1)
        var b = path.as_bytes()
        for i in range(len(b)):
            c_path[i] = c_char(b[i])
        c_path[len(b)] = 0

        var fd = external_call["open", c_int, UnsafePointer[c_char, MutAnyOrigin], c_int, c_int](
            c_path, c_int(flags), c_int(0o644)
        )
        c_path.free()

        if Int(fd) < 0:
            raise Error("Failed to open file: " + path)
        self._fd = Int(fd)

    def __init__(out self, *, deinit move: Self):
        self._fd = move._fd
        self._path = move._path
        self._lock_level = move._lock_level

    def read(self, offset: Int64, amount: Int, p_dest: UnsafePointer[UInt8, MutAnyOrigin]) raises -> Int:
        """Reads `amount` bytes starting at `offset` into `p_dest`."""
        var seek_res = external_call["lseek", c_long, c_int, c_long, c_int](
            c_int(self._fd), c_long(offset), c_int(SEEK_SET)
        )
        if Int(seek_res) < 0:
            raise Error("lseek failed for file: " + self._path)

        var n_read = external_call["read", Int, Int, UnsafePointer[NoneType, MutAnyOrigin], Int](
            self._fd, p_dest.bitcast[NoneType](), amount
        )
        return n_read

    def write(self, offset: Int64, amount: Int, p_src: UnsafePointer[UInt8, ImmutAnyOrigin]) raises -> Int:
        """Writes `amount` bytes from `p_src` starting at `offset`."""
        var seek_res = external_call["lseek", c_long, c_int, c_long, c_int](
            c_int(self._fd), c_long(offset), c_int(SEEK_SET)
        )
        if Int(seek_res) < 0:
            raise Error("lseek failed for file: " + self._path)

        var mut_ptr = UnsafePointer[NoneType, MutAnyOrigin](unsafe_from_address=Int(p_src))
        var n_written = external_call["write", Int, Int, UnsafePointer[NoneType, MutAnyOrigin], Int](
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

    def sync(self) raises:
        """Flushes written file buffers to physical disk."""
        var res = external_call["fsync", c_int, c_int](c_int(self._fd))
        if Int(res) != 0:
            raise Error("fsync failed for file: " + self._path)

    def file_size(self) raises -> Int64:
        """Returns the current file size in bytes."""
        var sz = external_call["lseek", c_long, c_int, c_long, c_int](
            c_int(self._fd), c_long(0), c_int(SEEK_END)
        )
        return Int64(sz)

    def lock(mut self, lock_level: Int) -> Bool:
        self._lock_level = lock_level
        return True

    def unlock(mut self, lock_level: Int) -> Bool:
        self._lock_level = lock_level
        return True

    def lock_level(self) -> Int:
        return self._lock_level

    def close(mut self):
        """Closes the underlying file descriptor."""
        if self._fd >= 0:
            _ = external_call["close", c_int, c_int](c_int(self._fd))
            self._fd = -1


struct VFS(ImplicitlyCopyable, Copyable, Movable):
    """Virtual File System Manager."""
    var _name: String

    def __init__(out self, name: String = "mojo_vfs"):
        self._name = name

    def __init__(out self, *, copy: Self):
        self._name = copy._name

    def __init__(out self, *, deinit move: Self):
        self._name = move._name

    def open_disk(self, path: String, read_only: Bool = False, create: Bool = True) raises -> DiskFile:
        """Opens a POSIX disk file."""
        return DiskFile(path, read_only, create)

    def open_memory(self) -> MemFile:
        """Creates an in-memory simulated file."""
        return MemFile()

    def delete_file(self, path: String) raises:
        """Deletes a file from the filesystem."""
        var c_path = alloc[c_char](path.byte_length() + 1)
        var b = path.as_bytes()
        for i in range(len(b)):
            c_path[i] = c_char(b[i])
        c_path[len(b)] = 0
        var res = external_call["unlink", c_int, UnsafePointer[c_char, MutAnyOrigin]](c_path)
        c_path.free()
        if Int(res) != 0:
            raise Error("unlink failed for file: " + path)

    def file_exists(self, path: String) -> Bool:
        """Returns True if the file exists."""
        var c_path = alloc[c_char](path.byte_length() + 1)
        var b = path.as_bytes()
        for i in range(len(b)):
            c_path[i] = c_char(b[i])
        c_path[len(b)] = 0
        var res = external_call["access", c_int, UnsafePointer[c_char, MutAnyOrigin], c_int](c_path, c_int(0))
        c_path.free()
        return Int(res) == 0
