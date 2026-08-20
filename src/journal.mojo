"""SQLite Rollback Journal Management.

Corresponds to `sqlite/src/pager.c` (journal subroutines) and `sqlite/src/wal.c`.

Implements:
- 28-byte SQLite Rollback Journal Header:
  - Magic string: 0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7
  - Page count in journal (-1 if not finalized, 0 after commit)
  - Random nonce (checksum seed)
  - Initial database size in pages
  - Sector size
  - Page size
- Journal record format: (4-byte pgno, page_data[page_size], 4-byte checksum)
"""

from std.memory import Pointer
from src.types import *
from src.vfs import MemFile

# Rollback Journal 8-byte magic: 0xd9d505f920a163d7
comptime JOURNAL_MAGIC_0 = 0xD9
comptime JOURNAL_MAGIC_1 = 0xD5
comptime JOURNAL_MAGIC_2 = 0x05
comptime JOURNAL_MAGIC_3 = 0xF9
comptime JOURNAL_MAGIC_4 = 0x20
comptime JOURNAL_MAGIC_5 = 0xA1
comptime JOURNAL_MAGIC_6 = 0x63
comptime JOURNAL_MAGIC_7 = 0xD7

# Journal Modes
comptime JOURNAL_MODE_DELETE = 1
comptime JOURNAL_MODE_PERSIST = 2
comptime JOURNAL_MODE_OFF = 3
comptime JOURNAL_MODE_TRUNCATE = 4
comptime JOURNAL_MODE_MEMORY = 5


struct JournalRecord(ImplicitlyCopyable, Copyable, Movable):
    """ Holds an uncommitted page snapshot for rollback."""
    var pgno: UInt32
    var data: List[UInt8]
    var checksum: UInt32

    def __init__(out self, pgno: UInt32, data: List[UInt8], checksum: UInt32 = 0):
        self.pgno = pgno
        self.data = data.copy()
        self.checksum = checksum

    def __init__(out self, *, copy: Self):
        self.pgno = copy.pgno
        self.data = copy.data.copy()
        self.checksum = copy.checksum

    def __init__(out self, *, deinit move: Self):
        self.pgno = move.pgno
        self.data = move.data^
        self.checksum = move.checksum


struct Journal(Movable):
    """ Manages rollback journal records for an in-flight transaction."""
    var _records: List[JournalRecord]
    var _page_size: Int
    var _initial_db_size: UInt32
    var _journal_mode: Int
    var _is_active: Bool

    def __init__(out self, page_size: Int = 4096, mode: Int = JOURNAL_MODE_DELETE):
        self._records = List[JournalRecord]()
        self._page_size = page_size
        self._initial_db_size = 0
        self._journal_mode = mode
        self._is_active = False

    def __init__(out self, *, deinit move: Self):
        self._records = move._records^
        self._page_size = move._page_size
        self._initial_db_size = move._initial_db_size
        self._journal_mode = move._journal_mode
        self._is_active = move._is_active

    def begin_transaction(mut self, db_size: UInt32):
        """ Starts recording page modifications."""
        self._records = List[JournalRecord]()
        self._initial_db_size = db_size
        self._is_active = True

    def is_active(self) -> Bool:
        return self._is_active

    def record_count(self) -> Int:
        return len(self._records)

    def initial_db_size(self) -> UInt32:
        return self._initial_db_size

    def has_page(self, pgno: UInt32) -> Bool:
        """ Returns True if the original version of `pgno` has already been recorded."""
        for i in range(len(self._records)):
            if self._records[i].pgno == pgno:
                return True
        return False

    def record_page(mut self, pgno: UInt32, data: List[UInt8]):
        """ Snapshots the original page content before it is modified."""
        if not self._is_active:
            return
        if not self.has_page(pgno):
            # Compute a simple 32-bit checksum
            var cs: UInt32 = 0
            for i in range(len(data)):
                cs = (cs * 33) + UInt32(data[i])
            self._records.append(JournalRecord(pgno, data, cs))

    def commit(mut self):
        """ Finalizes transaction by clearing journal records."""
        self._records = List[JournalRecord]()
        self._is_active = False

    def rollback(mut self) -> List[JournalRecord]:
        """ Returns all preserved original pages to be restored."""
        var recs = self._records.copy()
        self._records = List[JournalRecord]()
        self._is_active = False
        return recs^

    def encode_header(self, page_count: Int) -> List[UInt8]:
        """ Serializes 28-byte SQLite Rollback Journal Header."""
        var res = List[UInt8]()
        # 8-byte magic
        res.append(UInt8(JOURNAL_MAGIC_0))
        res.append(UInt8(JOURNAL_MAGIC_1))
        res.append(UInt8(JOURNAL_MAGIC_2))
        res.append(UInt8(JOURNAL_MAGIC_3))
        res.append(UInt8(JOURNAL_MAGIC_4))
        res.append(UInt8(JOURNAL_MAGIC_5))
        res.append(UInt8(JOURNAL_MAGIC_6))
        res.append(UInt8(JOURNAL_MAGIC_7))

        # 4-byte Page count (-1 for unfinalized, or actual count)
        var pc = UInt32(page_count)
        res.append(UInt8((pc >> 24) & 0xFF))
        res.append(UInt8((pc >> 16) & 0xFF))
        res.append(UInt8((pc >> 8) & 0xFF))
        res.append(UInt8(pc & 0xFF))

        # 4-byte random nonce
        res.append(0x12)
        res.append(0x34)
        res.append(0x56)
        res.append(0x78)

        # 4-byte initial db size
        var init_sz = self._initial_db_size
        res.append(UInt8((init_sz >> 24) & 0xFF))
        res.append(UInt8((init_sz >> 16) & 0xFF))
        res.append(UInt8((init_sz >> 8) & 0xFF))
        res.append(UInt8(init_sz & 0xFF))

        # 4-byte sector size (default 512)
        res.append(0)
        res.append(0)
        res.append(2)
        res.append(0)

        # 4-byte page size
        var ps = UInt32(self._page_size)
        res.append(UInt8((ps >> 24) & 0xFF))
        res.append(UInt8((ps >> 16) & 0xFF))
        res.append(UInt8((ps >> 8) & 0xFF))
        res.append(UInt8(ps & 0xFF))

        return res^
