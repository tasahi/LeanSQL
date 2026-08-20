"""SQLite Type Constants, Status Codes, and Opaque C Pointer Aliases.

Corresponds to `sqlite/src/sqlite.h.in` and `sqlite/src/sqliteInt.h`.
"""

from std.ffi import c_char, c_int, c_double
from std.memory import UnsafePointer

# === SQLite Result Codes ===
comptime SQLITE_OK = 0          # Successful result
comptime SQLITE_ERROR = 1       # Generic error
comptime SQLITE_INTERNAL = 2    # Internal logic error in SQLite
comptime SQLITE_PERM = 3        # Access permission denied
comptime SQLITE_ABORT = 4       # Callback routine requested an abort
comptime SQLITE_BUSY = 5        # The database file is locked
comptime SQLITE_LOCKED = 6      # A table in the database is locked
comptime SQLITE_NOMEM = 7       # A malloc() failed
comptime SQLITE_READONLY = 8    # Attempt to write a readonly database
comptime SQLITE_INTERRUPT = 9   # Operation terminated by sqlite3_interrupt()
comptime SQLITE_IOERR = 10      # Some kind of disk I/O error occurred
comptime SQLITE_CORRUPT = 11    # The database disk image is malformed
comptime SQLITE_NOTFOUND = 12   # Unknown opcode in sqlite3_file_control()
comptime SQLITE_FULL = 13       # Insertion failed because database is full
comptime SQLITE_CANTOPEN = 14   # Unable to open the database file
comptime SQLITE_PROTOCOL = 15   # Database lock protocol error
comptime SQLITE_EMPTY = 16      # Internal use only
comptime SQLITE_SCHEMA = 17     # The database schema changed
comptime SQLITE_TOOBIG = 18     # String or BLOB exceeds size limit
comptime SQLITE_CONSTRAINT = 19 # Abort due to constraint violation
comptime SQLITE_MISMATCH = 20   # Data type mismatch
comptime SQLITE_MISUSE = 21     # Library used incorrectly
comptime SQLITE_NOLFS = 22      # Uses OS features not supported on host
comptime SQLITE_AUTH = 23       # Authorization denied
comptime SQLITE_FORMAT = 24     # Not used
comptime SQLITE_RANGE = 25      # 2nd parameter to sqlite3_bind out of range
comptime SQLITE_NOTADB = 26     # File opened that is not a database file
comptime SQLITE_NOTICE = 27     # Notifications from sqlite3_log()
comptime SQLITE_WARNING = 28    # Warnings from sqlite3_log()
comptime SQLITE_ROW = 100       # sqlite3_step() has another row ready
comptime SQLITE_DONE = 101      # sqlite3_step() has finished executing

# === SQLite Fundamental Datatypes ===
comptime SQLITE_INTEGER = 1
comptime SQLITE_FLOAT = 2
comptime SQLITE_TEXT = 3
comptime SQLITE_BLOB = 4
comptime SQLITE_NULL = 5

# === SQLite Open Flags ===
comptime SQLITE_OPEN_READONLY = 0x00000001
comptime SQLITE_OPEN_READWRITE = 0x00000002
comptime SQLITE_OPEN_CREATE = 0x00000004
comptime SQLITE_OPEN_DELETEONCLOSE = 0x00000008
comptime SQLITE_OPEN_EXCLUSIVE = 0x00000010
comptime SQLITE_OPEN_AUTOPROXY = 0x00000020
comptime SQLITE_OPEN_URI = 0x00000040
comptime SQLITE_OPEN_MEMORY = 0x00000080
comptime SQLITE_OPEN_MAIN_DB = 0x00000100
comptime SQLITE_OPEN_TEMP_DB = 0x00000200
comptime SQLITE_OPEN_TRANSIENT_DB = 0x00000400
comptime SQLITE_OPEN_MAIN_JOURNAL = 0x00000800
comptime SQLITE_OPEN_TEMP_JOURNAL = 0x00001000
comptime SQLITE_OPEN_SUBJOURNAL = 0x00002000
comptime SQLITE_OPEN_SUPER_JOURNAL = 0x00004000
comptime SQLITE_OPEN_NOMUTEX = 0x00008000
comptime SQLITE_OPEN_FULLMUTEX = 0x00010000
comptime SQLITE_OPEN_SHAREDCACHE = 0x00020000
comptime SQLITE_OPEN_PRIVATECACHE = 0x00040000
comptime SQLITE_OPEN_WAL = 0x00080000

# === Special Destructors ===
comptime SQLITE_STATIC_DESTRUCTOR = 0
comptime SQLITE_TRANSIENT_DESTRUCTOR = -1

# === Opaque C Pointer Aliases ===
comptime C_Db = UnsafePointer[NoneType, MutAnyOrigin]
comptime C_Stmt = UnsafePointer[NoneType, MutAnyOrigin]
comptime C_Char_Ptr = UnsafePointer[c_char, ImmutAnyOrigin]
comptime C_Char_Mut_Ptr = UnsafePointer[c_char, MutAnyOrigin]
comptime C_Void_Ptr = UnsafePointer[NoneType, ImmutAnyOrigin]
comptime C_Void_Mut_Ptr = UnsafePointer[NoneType, MutAnyOrigin]
