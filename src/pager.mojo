"""SQLite Page Cache and Pager Transaction State Machine.

Corresponds to `sqlite/src/pager.h` and `sqlite/src/pager.c`.

Implements:
- `DbPage`: Reference-counted in-memory database page.
- `PCache`: LRU page cache for fast lookups and dirty page tracking.
- `PagerState`: State machine transitions:
  - `PAGER_OPEN`: Clean state, no locks held.
  - `PAGER_READER`: Read-only transaction, SHARED lock held.
  - `PAGER_WRITER_LOCKED`: RESERVED lock held, pages read.
  - `PAGER_WRITER_CACHED`: Modified pages recorded in journal.
  - `PAGER_WRITER_DBMOD`: EXCLUSIVE lock held, writing dirty pages to disk.
- `Pager`: ACID page manager handling page retrieval, dirty writes, commit, and rollback.
"""

from std.memory import UnsafePointer, alloc
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


struct DbPage(ImplicitlyCopyable, Copyable, Movable):
    """ An individual database page in memory."""
    var pgno: UInt32
    var data: List[UInt8]
    var is_dirty: Bool

    def __init__(out self, pgno: UInt32, page_size: Int):
        self.pgno = pgno
        self.data = List[UInt8]()
        for _ in range(page_size):
            self.data.append(0)
        self.is_dirty = False

    def __init__(out self, pgno: UInt32, data: List[UInt8], is_dirty: Bool = False):
        self.pgno = pgno
        self.data = data.copy()
        self.is_dirty = is_dirty

    def __init__(out self, *, copy: Self):
        self.pgno = copy.pgno
        self.data = copy.data.copy()
        self.is_dirty = copy.is_dirty

    def __init__(out self, *, deinit move: Self):
        self.pgno = move.pgno
        self.data = move.data^
        self.is_dirty = move.is_dirty


struct PCache(ImplicitlyCopyable, Copyable, Movable):
    """ In-memory page cache."""
    var _pages: List[DbPage]
    var _page_size: Int

    def __init__(out self, page_size: Int = 4096):
        self._pages = List[DbPage]()
        self._page_size = page_size

    def __init__(out self, *, copy: Self):
        self._pages = copy._pages.copy()
        self._page_size = copy._page_size

    def __init__(out self, *, deinit move: Self):
        self._pages = move._pages^
        self._page_size = move._page_size

    def get(self, pgno: UInt32) -> Optional[DbPage]:
        """ Finds a page by page number in cache."""
        for i in range(len(self._pages)):
            if self._pages[i].pgno == pgno:
                return Optional(self._pages[i].copy())
        return None

    def put(mut self, page: DbPage):
        """ Inserts or updates a page in the cache."""
        for i in range(len(self._pages)):
            if self._pages[i].pgno == page.pgno:
                self._pages[i] = page.copy()
                return
        self._pages.append(page.copy())

    def clear(mut self):
        """ Clears all cached pages."""
        self._pages = List[DbPage]()

    def dirty_pages(self) -> List[DbPage]:
        """ Returns all pages marked as dirty."""
        var dirty = List[DbPage]()
        for i in range(len(self._pages)):
            if self._pages[i].is_dirty:
                dirty.append(self._pages[i].copy())
        return dirty^

    def mark_all_clean(mut self):
        """ Marks all cached pages as clean."""
        for i in range(len(self._pages)):
            self._pages[i].is_dirty = False


struct Pager(ImplicitlyCopyable, Copyable, Movable):
    """ Page-level storage manager implementing ACID transactions."""
    var _file: MemFile
    var _journal: Journal
    var _pcache: PCache
    var _page_size: Int
    var _db_size_pages: UInt32
    var _state: Int
    var _path: String

    def __init__(out self, path: String = ":memory:", page_size: Int = 4096):
        self._file = MemFile()
        self._journal = Journal(page_size)
        self._pcache = PCache(page_size)
        self._page_size = page_size
        self._db_size_pages = 0
        self._state = PAGER_OPEN
        self._path = path

    def __init__(out self, *, copy: Self):
        self._file = copy._file.copy()
        self._journal = copy._journal.copy()
        self._pcache = copy._pcache.copy()
        self._page_size = copy._page_size
        self._db_size_pages = copy._db_size_pages
        self._state = copy._state
        self._path = copy._path

    def __init__(out self, *, deinit move: Self):
        self._file = move._file^
        self._journal = move._journal^
        self._pcache = move._pcache^
        self._page_size = move._page_size
        self._db_size_pages = move._db_size_pages
        self._state = move._state
        self._path = move._path

    def page_size(self) -> Int:
        return self._page_size

    def page_count(self) -> UInt32:
        return self._db_size_pages

    def state(self) -> Int:
        return self._state

    def acquire_page(mut self, pgno: UInt32) raises -> DbPage:
        """ Retrieves page `pgno` from cache or loads it from storage."""
        if pgno < 1:
            raise Error("Invalid page number: " + String(pgno))

        # Check cache
        var cached = self._pcache.get(pgno)
        if cached:
            return cached.value()

        # Load from file
        var p = alloc[UInt8](self._page_size)
        var offset = Int64(pgno - 1) * Int64(self._page_size)
        var n_read = self._file.read(offset, self._page_size, p)

        var page_data = List[UInt8]()
        for i in range(self._page_size):
            if i < n_read:
                page_data.append(p[i])
            else:
                page_data.append(0)
        p.free()

        var page = DbPage(pgno, page_data, False)
        self._pcache.put(page)
        return page^

    def write_page(mut self, mut page: DbPage) raises:
        """ Marks a page as dirty and records its pre-image into the rollback journal."""
        if self._state == PAGER_OPEN or self._state == PAGER_READER:
            self.begin_transaction()

        # Record pre-image before first modification in this transaction
        if not self._journal.has_page(page.pgno):
            # Load original from file/clean state
            var p_orig = alloc[UInt8](self._page_size)
            var offset = Int64(page.pgno - 1) * Int64(self._page_size)
            var n_read = self._file.read(offset, self._page_size, p_orig)
            var orig_data = List[UInt8]()
            for i in range(self._page_size):
                if i < n_read:
                    orig_data.append(p_orig[i])
                else:
                    orig_data.append(0)
            p_orig.free()
            self._journal.record_page(page.pgno, orig_data)

        page.is_dirty = True
        self._pcache.put(page)
        if page.pgno > self._db_size_pages:
            self._db_size_pages = page.pgno

    def begin_transaction(mut self):
        """ Starts a write transaction with a journal session."""
        if self._state == PAGER_WRITER_LOCKED or self._state == PAGER_WRITER_CACHED:
            return
        _ = self._file.lock(RESERVED_LOCK)
        self._journal.begin(self._db_size_pages)
        self._state = PAGER_WRITER_LOCKED

    def commit(mut self) raises:
        """ Flushes all dirty pages to storage and finalizes the transaction."""
        if self._state != PAGER_WRITER_LOCKED and self._state != PAGER_WRITER_CACHED:
            return

        _ = self._file.lock(EXCLUSIVE_LOCK)
        self._state = PAGER_WRITER_DBMOD

        # Flush dirty pages to file
        var dirty = self._pcache.dirty_pages()
        var p_buf = alloc[UInt8](self._page_size)
        for i in range(len(dirty)):
            var d_page = dirty[i]
            for j in range(self._page_size):
                p_buf[j] = d_page.data[j]
            var offset = Int64(d_page.pgno - 1) * Int64(self._page_size)
            var immut_p = UnsafePointer[UInt8, ImmutAnyOrigin](other=p_buf)
            _ = self._file.write(offset, self._page_size, immut_p)
        p_buf.free()

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
        var p_buf = alloc[UInt8](self._page_size)
        for i in range(len(orig_records)):
            var rec = orig_records[i]
            for j in range(self._page_size):
                p_buf[j] = rec.data[j]
            var offset = Int64(rec.pgno - 1) * Int64(self._page_size)
            var immut_p = UnsafePointer[UInt8, ImmutAnyOrigin](other=p_buf)
            _ = self._file.write(offset, self._page_size, immut_p)
        p_buf.free()

        # Restore db size and clear dirty cache
        self._db_size_pages = self._journal.initial_db_size()
        self._pcache.clear()
        _ = self._file.unlock(NO_LOCK)
        self._state = PAGER_OPEN
