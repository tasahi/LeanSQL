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

from std.memory import UnsafePointer, alloc
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

    def __init__(out self, pgno: UInt32, data: List[UInt8]):
        self.pgno = pgno
        self.data = data.copy()

    def __init__(out self, *, copy: Self):
        self.pgno = copy.pgno
        self.data = copy.data.copy()

    def __init__(out self, *, deinit move: Self):
        self.pgno = move.pgno
        self.data = move.data^


struct Journal(ImplicitlyCopyable, Copyable, Movable):
    """ Manages rollback journal recording and transaction rollback."""
    var _records: List[JournalRecord]
    var _initial_db_size: UInt32
    var _page_size: Int
    var _mode: Int
    var _is_active: Bool

    def __init__(out self, page_size: Int = 4096, mode: Int = JOURNAL_MODE_DELETE):
        self._records = List[JournalRecord]()
        self._initial_db_size = 0
        self._page_size = page_size
        self._mode = mode
        self._is_active = False

    def __init__(out self, *, copy: Self):
        self._records = copy._records.copy()
        self._initial_db_size = copy._initial_db_size
        self._page_size = copy._page_size
        self._mode = copy._mode
        self._is_active = copy._is_active

    def __init__(out self, *, deinit move: Self):
        self._records = move._records^
        self._initial_db_size = move._initial_db_size
        self._page_size = move._page_size
        self._mode = move._mode
        self._is_active = move._is_active

    def begin(mut self, initial_db_size: UInt32):
        """ Starts a new journal session for a transaction."""
        self._records = List[JournalRecord]()
        self._initial_db_size = initial_db_size
        self._is_active = True

    def record_page(mut self, pgno: UInt32, page_data: List[UInt8]):
        """ Records a page before it is modified for the first time in the transaction."""
        if not self._is_active or self._mode == JOURNAL_MODE_OFF:
            return
        # Check if already journaled in this transaction
        for i in range(len(self._records)):
            if self._records[i].pgno == pgno:
                return
        self._records.append(JournalRecord(pgno, page_data))

    def has_page(self, pgno: UInt32) -> Bool:
        """ Returns True if the page has already been journaled."""
        for i in range(len(self._records)):
            if self._records[i].pgno == pgno:
                return True
        return False

    def get_page_count(self) -> Int:
        """ Returns number of pages currently preserved in the journal."""
        return len(self._records)

    def get_record(self, idx: Int) -> JournalRecord:
        """ Accesses journaled record at `idx`."""
        return self._records[idx]

    def initial_db_size(self) -> UInt32:
        return self._initial_db_size

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
        var p = alloc[UInt8](28)
        # 8-byte magic
        p[0] = UInt8(JOURNAL_MAGIC_0)
        p[1] = UInt8(JOURNAL_MAGIC_1)
        p[2] = UInt8(JOURNAL_MAGIC_2)
        p[3] = UInt8(JOURNAL_MAGIC_3)
        p[4] = UInt8(JOURNAL_MAGIC_4)
        p[5] = UInt8(JOURNAL_MAGIC_5)
        p[6] = UInt8(JOURNAL_MAGIC_6)
        p[7] = UInt8(JOURNAL_MAGIC_7)

        # 4-byte Page count (-1 for unfinalized, or actual count)
        var pc = UInt32(page_count)
        p[8] = UInt8((pc >> 24) & 0xFF)
        p[9] = UInt8((pc >> 16) & 0xFF)
        p[10] = UInt8((pc >> 8) & 0xFF)
        p[11] = UInt8(pc & 0xFF)

        # 4-byte random nonce
        p[12] = 0x12
        p[13] = 0x34
        p[14] = 0x56
        p[15] = 0x78

        # 4-byte initial db size
        var init_sz = self._initial_db_size
        p[16] = UInt8((init_sz >> 24) & 0xFF)
        p[17] = UInt8((init_sz >> 16) & 0xFF)
        p[18] = UInt8((init_sz >> 8) & 0xFF)
        p[19] = UInt8(init_sz & 0xFF)

        # 4-byte sector size (default 512)
        p[20] = 0
        p[21] = 0
        p[22] = 2
        p[23] = 0

        # 4-byte page size
        var ps = UInt32(self._page_size)
        p[24] = UInt8((ps >> 24) & 0xFF)
        p[25] = UInt8((ps >> 16) & 0xFF)
        p[26] = UInt8((ps >> 8) & 0xFF)
        p[27] = UInt8(ps & 0xFF)

        var res = List[UInt8]()
        for i in range(28):
            res.append(p[i])
        p.free()
        return res^
