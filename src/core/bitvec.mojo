"""Bit Vector (Bitmap) Data Structure.

Corresponds to `Bitvec` in `sqlite/src/bitvec.c`.

Used in SQLite to track boolean sets of integer keys (e.g., page numbers
modified in a transaction, visited rows in query processing).
"""

struct BitVec(Movable, Copyable):
    """Dynamic bit vector supporting indexed bit operations."""
    var _size: Int
    var _data: List[UInt32]

    def __init__(out self, size: Int):
        """Initializes a BitVec capable of holding `size` bits, all initially cleared."""
        self._size = size
        var num_words = (size + 31) // 32
        self._data = List[UInt32]()
        for _ in range(num_words):
            self._data.append(0)

    def __init__(out self, *, copy: Self):
        self._size = copy._size
        self._data = copy._data.copy()

    def __init__(out self, *, deinit move: Self):
        self._size = move._size
        self._data = move._data^

    def set(mut self, i: Int) raises:
        """Sets the bit at 0-indexed position `i` to 1."""
        if i < 0 or i >= self._size:
            raise Error("BitVec index out of bounds: " + String(i))
        var word_idx = i // 32
        var bit_idx = UInt32(i % 32)
        self._data[word_idx] |= (UInt32(1) << bit_idx)

    def get(self, i: Int) raises -> Bool:
        """Returns True if the bit at position `i` is 1, False otherwise."""
        if i < 0 or i >= self._size:
            raise Error("BitVec index out of bounds: " + String(i))
        var word_idx = i // 32
        var bit_idx = UInt32(i % 32)
        return Bool((self._data[word_idx] >> bit_idx) & 1)

    def clear(mut self, i: Int) raises:
        """Clears the bit at position `i` (resets to 0)."""
        if i < 0 or i >= self._size:
            raise Error("BitVec index out of bounds: " + String(i))
        var word_idx = i // 32
        var bit_idx = UInt32(i % 32)
        self._data[word_idx] &= ~(UInt32(1) << bit_idx)

    def size(self) -> Int:
        """Returns the total capacity in bits."""
        return self._size
