"""SQLite Row and Value Structs with Dynamic Type Support.

Corresponds to `sqlite3_value_*` in `sqlite/src/vdbemem.c`.
"""

from std.ffi import c_char, c_int, c_double
from std.memory import UnsafePointer
from src.types import *


struct Value(ImplicitlyCopyable, Copyable, Movable):
    """ Represents a dynamically typed SQLite column cell."""
    var type_tag: Int
    var int_val: Int64
    var float_val: Float64
    var text_val: String

    def __init__(out self):
        self.type_tag = SQLITE_NULL
        self.int_val = 0
        self.float_val = 0.0
        self.text_val = ""

    def __init__(out self, *, copy: Self):
        self.type_tag = copy.type_tag
        self.int_val = copy.int_val
        self.float_val = copy.float_val
        self.text_val = copy.text_val

    def __init__(out self, *, deinit move: Self):
        self.type_tag = move.type_tag
        self.int_val = move.int_val
        self.float_val = move.float_val
        self.text_val = move.text_val^

    @staticmethod
    def of_int(v: Int64) -> Value:
        var val = Value()
        val.type_tag = SQLITE_INTEGER
        val.int_val = v
        return val^

    @staticmethod
    def of_float(v: Float64) -> Value:
        var val = Value()
        val.type_tag = SQLITE_FLOAT
        val.float_val = v
        return val^

    @staticmethod
    def of_text(v: String) -> Value:
        var val = Value()
        val.type_tag = SQLITE_TEXT
        val.text_val = v
        return val^

    @staticmethod
    def of_null() -> Value:
        var val = Value()
        val.type_tag = SQLITE_NULL
        return val^

    def is_null(self) -> Bool:
        return self.type_tag == SQLITE_NULL

    def to_int(self) -> Int64:
        if self.type_tag == SQLITE_INTEGER:
            return self.int_val
        elif self.type_tag == SQLITE_FLOAT:
            return Int64(self.float_val)
        return 0

    def to_float(self) -> Float64:
        if self.type_tag == SQLITE_FLOAT:
            return self.float_val
        elif self.type_tag == SQLITE_INTEGER:
            return Float64(self.int_val)
        return 0.0

    def to_string(self) -> String:
        """Returns the string representation of the value."""
        if self.type_tag == SQLITE_TEXT:
            return self.text_val
        elif self.type_tag == SQLITE_INTEGER:
            return String(self.int_val)
        elif self.type_tag == SQLITE_FLOAT:
            return String(self.float_val)
        return "NULL"

    def __str__(self) -> String:
        return self.to_string()

    def repr_string(self) -> String:
        if self.type_tag == SQLITE_TEXT:
            return "'" + self.text_val + "'"
        return self.to_string()


struct Row(ImplicitlyCopyable, Copyable, Movable, Sized):
    """ Represents a single query result row with indexed column access."""
    var values: List[Value]
    var col_names: List[String]

    def __init__(out self):
        self.values = List[Value]()
        self.col_names = List[String]()

    def __init__(out self, values: List[Value], col_names: List[String]):
        self.values = values.copy()
        self.col_names = col_names.copy()

    def __init__(out self, *, copy: Self):
        self.values = copy.values.copy()
        self.col_names = copy.col_names.copy()

    def __init__(out self, *, deinit move: Self):
        self.values = move.values^
        self.col_names = move.col_names^

    def __len__(self) -> Int:
        """ Returns the number of columns in this row. """
        return len(self.values)

    def column_count(self) -> Int:
        """ Returns the number of columns in this row. """
        return len(self.values)

    def __getitem__(self, idx: Int) -> Value:
        """ Accesses column cell value at 0-indexed position `idx`. """
        return self.values[idx]

    def get_int(self, idx: Int) -> Int64:
        """ Retrieves column value at `idx` as an Int64. """
        return self.values[idx].to_int()

    def get_float(self, idx: Int) -> Float64:
        """ Retrieves column value at `idx` as a Float64. """
        return self.values[idx].to_float()

    def get_string(self, idx: Int) -> String:
        """ Retrieves column value at `idx` as a String. """
        return self.values[idx].to_string()

    def is_null(self, idx: Int) -> Bool:
        """ Checks whether column value at `idx` is NULL. """
        return self.values[idx].is_null()
