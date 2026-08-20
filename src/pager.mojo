""" SQLite ACID Pager Subsystem.

Corresponds to `sqlite/src/pager.c` and `sqlite/src/pcache.c`.

Implements:
- `Page`: Fixed-size page buffer with dirty tracking.
- `PCache`: LRU / hash-indexed in-memory page cache.
- `PagerState`: State machine tracking transaction transitions:
  - `PAGER_OPEN`: No transaction active, NO_LOCK.
  - `PAGER_READER`: Read-only transaction, SHARED lock held.
  - `PAGER_WRITER_LOCKED`: RESERVED lock held, pages read.
  - `PAGER_WRITER_CACHED`: Modified pages recorded in journal.
  - `PAGER_WRITER_DBMOD`: EXCLUSIVE lock held, writing dirty pages to disk.
- `Pager`: ACID page manager handling page retrieval, dirty writes, commit, and rollback.
"""

from std.memory import Pointer
from src.types import *
from src.vfs import MemFile, NO_LOCK, SHARED_LOCK, RESERVED_LOCK, EXCLUSIVE_LOCK
from src.journal import Journal, JournalRecord, JOURNAL_MODE_DELETE, JOURNAL_MODE_MEMORY

# === Pager States ===
comptime PAGER_OPEN = 0
comptime PAGER_READER = 1
comptime PAGER_WRITER_LOCKED = 2
comptime PAGER_WRITER_CACHED = 3
comptime PAGER_WRITER_DBMOD = 4
comptime PAGER_ERROR = 5


struct Page(ImplicitlyCopyable, Copyable, Movable):
    """Represents a single fixed-size SQLite B-Tree database page in memory."""
    var pgno: UInt32
    var data: List[UInt8]
    var is_dirty: Bool

    def __init__(out self, pgno: UInt32, page_size: Int):
        self.pgno = pgno
        self.data = List[UInt8]()
        for _ in range(page_size):
            self.data.append(0)
        self.is_dirty = False

    def __init__(out self, *, copy: Self):
        self.pgno = copy.pgno
        self.data = copy.data.copy()
        self.is_dirty = copy.is_dirty

    def __init__(out self, *, deinit move: Self):
        self.pgno = move.pgno
        self.data = move.data^
        self.is_dirty = move.is_dirty


struct PCache(Movable):
    """In-memory page cache managing loaded and dirty pages."""
    var _pages: List[Page]
    var _page_size: Int
    var _max_pages: Int

    def __init__(out self, page_size: Int, max_pages: Int = 100):
        self._pages = List[Page]()
        self._page_size = page_size
        self._max_pages = max_pages

    def __init__(out self, *, deinit move: Self):
        self._pages = move._pages^
        self._page_size = move._page_size
        self._max_pages = move._max_pages

    def get(self, pgno: UInt32) -> Optional[Page]:
        """Finds a cached page by pgno."""
        for i in range(len(self._pages)):
            if self._pages[i].pgno == pgno:
                return self._pages[i].copy()
        return None

    def put(mut self, page: Page):
        """Inserts or updates a page in the cache."""
        for i in range(len(self._pages)):
            if self._pages[i].pgno == page.pgno:
                self._pages[i] = page.copy()
                return
        self._pages.append(page.copy())

    def mark_dirty(mut self, pgno: UInt32):
        """Marks a cached page as dirty."""
        for i in range(len(self._pages)):
            if self._pages[i].pgno == pgno:
                self._pages[i].is_dirty = True
                return

    def dirty_pages(self) -> List[Page]:
        """Returns all currently dirty pages in the cache."""
        var res = List[Page]()
        for i in range(len(self._pages)):
            if self._pages[i].is_dirty:
                res.append(self._pages[i].copy())
        return res^

    def mark_all_clean(mut self):
        """Marks all cached pages as clean."""
        for i in range(len(self._pages)):
            self._pages[i].is_dirty = False

    def clear(mut self):
        """Clears all cached pages."""
        self._pages = List[Page]()


struct Pager(Movable):
    """SQLite ACID Pager coordinating transactions, caching, locking, and disk I/O."""
    var _file: MemFile
    var _pcache: PCache
    var _journal: Journal
    var _page_size: Int
    var _state: Int
    var _db_size_pages: UInt32

    def __init__(out self, mut file: MemFile, page_size: Int = 4096):
        self._file = file^
        self._pcache = PCache(page_size)
        self._journal = Journal(page_size)
        self._page_size = page_size
        self._state = PAGER_OPEN
        self._db_size_pages = 0

    def __init__(out self, *, deinit move: Self):
        self._file = move._file^
        self._pcache = move._pcache^
        self._journal = move._journal^
        self._page_size = move._page_size
        self._state = move._state
        self._db_size_pages = move._db_size_pages

    def page_size(self) -> Int:
        return self._page_size

    def state(self) -> Int:
        return self._state

    def db_size(self) -> UInt32:
        return self._db_size_pages

    def read_page(mut self, pgno: UInt32) raises -> Page:
        """Retrieves a page by number, reading from disk if not cached."""
        # 1. Check cache first
        var cached = self._pcache.get(pgno)
        if cached:
            return cached.value()^

        # 2. Allocate and read from underlying file
        var page = Page(pgno, self._page_size)
        var offset = Int64(pgno - 1) * Int64(self._page_size)
        
        var mut_ptr = Pointer[UInt8, MutAnyOrigin](unsafe_from_address=Int(page.data.unsafe_ptr()))
        _ = self._file.read(offset, self._page_size, mut_ptr)

        self._pcache.put(page.copy())
        return page^

    def write_page(mut self, mut page: Page) raises:
        """Marks a page for writing, taking journal snapshot if necessary."""
        if self._state == PAGER_OPEN or self._state == PAGER_READER:
            self.begin_write()

        # If page not yet preserved in journal for this transaction, snapshot original
        if not self._journal.has_page(page.pgno):
            var orig_cached = self._pcache.get(page.pgno)
            if orig_cached:
                self._journal.record_page(page.pgno, orig_cached.value().data)
            else:
                self._journal.record_page(page.pgno, page.data)

        page.is_dirty = True
        self._pcache.put(page)
        if page.pgno > self._db_size_pages:
            self._db_size_pages = page.pgno

    def begin_read(mut self) raises:
        """Transitions to PAGER_READER under SHARED lock."""
        if self._state != PAGER_OPEN:
            return
        if not self._file.lock(SHARED_LOCK):
            raise Error("Failed to acquire SHARED lock on database")
        self._state = PAGER_READER

    def begin_write(mut self) raises:
        """Transitions to PAGER_WRITER_LOCKED under RESERVED lock."""
        if self._state == PAGER_OPEN:
            self.begin_read()
        if self._state == PAGER_READER:
            if not self._file.lock(RESERVED_LOCK):
                raise Error("Failed to acquire RESERVED lock on database")
            self._state = PAGER_WRITER_LOCKED
            self._journal.begin_transaction(self._db_size_pages)

    def commit(mut self) raises:
        """Flushes dirty pages, finalizes journal, and releases locks."""
        if self._state != PAGER_WRITER_LOCKED and self._state != PAGER_WRITER_CACHED and self._state != PAGER_WRITER_DBMOD:
            return

        # Elevate to EXCLUSIVE lock before writing to database
        if not self._file.lock(EXCLUSIVE_LOCK):
            raise Error("Failed to acquire EXCLUSIVE lock on database for commit")
        self._state = PAGER_WRITER_DBMOD

        # Flush dirty pages
        var dirty = self._pcache.dirty_pages()
        for i in range(len(dirty)):
            var d_page = dirty[i]
            var offset = Int64(d_page.pgno - 1) * Int64(self._page_size)
            _ = self._file.write(offset, self._page_size, d_page.data.unsafe_ptr())

        # Finalize journal and clean cache
        self._journal.commit()
        self._pcache.mark_all_clean()
        _ = self._file.unlock(NO_LOCK)
        self._state = PAGER_OPEN

    def rollback(mut self) raises:
        """Rolls back the active transaction by restoring original journaled pages."""
        if self._state != PAGER_WRITER_LOCKED and self._state != PAGER_WRITER_CACHED and self._state != PAGER_WRITER_DBMOD:
            return

        var orig_records = self._journal.rollback()
        for i in range(len(orig_records)):
            var rec = orig_records[i]
            var offset = Int64(rec.pgno - 1) * Int64(self._page_size)
            _ = self._file.write(offset, self._page_size, rec.data.unsafe_ptr())

        # Restore db size and clear dirty cache
        self._db_size_pages = self._journal.initial_db_size()
        self._pcache.clear()
        _ = self._file.unlock(NO_LOCK)
        self._state = PAGER_OPEN
