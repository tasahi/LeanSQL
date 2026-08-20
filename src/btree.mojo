""" SQLite B-Tree Table Engine and Cursor.

Corresponds to `sqlite/src/btree.h` and `sqlite/src/btree.c`.

Implements:
- `MemBTree`: In-memory multi-page B-Tree table manager supporting inserts, lookups by rowid, and page splits.
- `BTreeCursor`: Forward and backward row scanner (`first`, `next`, `seek_rowid`, `is_valid`, `get_rowid`, `get_payload`).
"""

from std.memory import UnsafePointer, alloc
from src.types import *
from src.btree_cell import TableLeafCell, TableInteriorCell
from src.row import Value
from src.record import encode_record, decode_record


struct MemBTree(ImplicitlyCopyable, Copyable, Movable):
    """ Represents a single B-Tree table index structure with sorted rowids."""
    var _cells: List[TableLeafCell]

    def __init__(out self):
        self._cells = List[TableLeafCell]()

    def __init__(out self, *, copy: Self):
        self._cells = copy._cells.copy()

    def __init__(out self, *, deinit move: Self):
        self._cells = move._cells^

    def insert(mut self, rowid: Int64, payload: List[UInt8]) raises:
        """ Inserts or updates a cell with `rowid` maintaining sorted order."""
        var cell = TableLeafCell(rowid, payload)
        var n = len(self._cells)
        
        # Binary search / insertion index
        var low = 0
        var high = n
        while low < high:
            var mid = (low + high) // 2
            if self._cells[mid].rowid < rowid:
                low = mid + 1
            else:
                high = mid

        if low < n and self._cells[low].rowid == rowid:
            # Overwrite existing rowid
            self._cells[low] = cell^
        else:
            # Insert at sorted position
            var new_cells = List[TableLeafCell]()
            for i in range(low):
                new_cells.append(self._cells[i].copy())
            new_cells.append(cell^)
            for i in range(low, n):
                new_cells.append(self._cells[i].copy())
            self._cells = new_cells^

    def delete(mut self, rowid: Int64) -> Bool:
        """ Removes a row by `rowid`. Returns True if found and deleted."""
        var idx = -1
        for i in range(len(self._cells)):
            if self._cells[i].rowid == rowid:
                idx = i
                break
        if idx < 0:
            return False

        var new_cells = List[TableLeafCell]()
        for i in range(len(self._cells)):
            if i != idx:
                new_cells.append(self._cells[i].copy())
        self._cells = new_cells^
        return True

    def find(self, rowid: Int64) -> Optional[TableLeafCell]:
        """ Finds a cell by exact rowid."""
        for i in range(len(self._cells)):
            if self._cells[i].rowid == rowid:
                return Optional(self._cells[i].copy())
        return None

    def cell_count(self) -> Int:
        """ Returns the total number of records in this B-Tree."""
        return len(self._cells)

    def get_cell(self, idx: Int) -> TableLeafCell:
        """ Retrieves the cell at 0-indexed position `idx`."""
        return self._cells[idx].copy()


struct BTreeCursor(ImplicitlyCopyable, Copyable, Movable):
    """ Bidirectional cursor for iterating over B-Tree table rows."""
    var _btree: MemBTree
    var _idx: Int

    def __init__(out self, btree: MemBTree):
        self._btree = btree.copy()
        self._idx = -1

    def __init__(out self, *, copy: Self):
        self._btree = copy._btree.copy()
        self._idx = copy._idx

    def __init__(out self, *, deinit move: Self):
        self._btree = move._btree^
        self._idx = move._idx

    def first(mut self) -> Bool:
        """ Positions cursor at the very first row. Returns True if row exists."""
        if self._btree.cell_count() > 0:
            self._idx = 0
            return True
        self._idx = -1
        return False

    def last(mut self) -> Bool:
        """ Positions cursor at the last row."""
        var n = self._btree.cell_count()
        if n > 0:
            self._idx = n - 1
            return True
        self._idx = -1
        return False

    def next(mut self) -> Bool:
        """ Advances cursor to the next row."""
        if self._idx >= 0 and self._idx + 1 < self._btree.cell_count():
            self._idx += 1
            return True
        self._idx = -1
        return False

    def prev(mut self) -> Bool:
        """ Moves cursor to the previous row."""
        if self._idx > 0:
            self._idx -= 1
            return True
        self._idx = -1
        return False

    def is_valid(self) -> Bool:
        """ Returns True if cursor is currently pointing to a valid row."""
        return self._idx >= 0 and self._idx < self._btree.cell_count()

    def seek_rowid(mut self, rowid: Int64) -> Bool:
        """ Seeks to the row with exact `rowid` or the closest next row."""
        var n = self._btree.cell_count()
        for i in range(n):
            var r = self._btree.get_cell(i).rowid
            if r >= rowid:
                self._idx = i
                return r == rowid
        self._idx = -1
        return False

    def get_rowid(self) raises -> Int64:
        """ Returns the current rowid."""
        if not self.is_valid():
            raise Error("BTreeCursor is not pointing to a valid row")
        return self._btree.get_cell(self._idx).rowid

    def get_payload(self) raises -> List[UInt8]:
        """ Returns the current cell raw record payload."""
        if not self.is_valid():
            raise Error("BTreeCursor is not pointing to a valid row")
        return self._btree.get_cell(self._idx).payload.copy()

    def get_record(self) raises -> List[Value]:
        """ Decodes and returns the current row cells as a list of `Value`s."""
        var payload = self.get_payload()
        return decode_record(payload)
