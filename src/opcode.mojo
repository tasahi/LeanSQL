""" SQLite VDBE Opcode Definitions and Opcode Constants.

Corresponds to `sqlite/src/vdbe.h` and `sqlite/src/vdbe.c`.

Opcodes define the instruction set of the SQLite Virtual Database Engine.
"""

from src.types import *

# === VDBE Control Flow & Transaction Opcodes ===
comptime OP_INIT = 1
comptime OP_GOTO = 2
comptime OP_HALT = 3
comptime OP_TRANSACTION = 4
comptime OP_AUTOCOMMIT = 5

# === Register & Memory Opcodes ===
comptime OP_INTEGER = 10
comptime OP_REAL = 11
comptime OP_STRING8 = 12
comptime OP_NULL = 13
comptime OP_COPY = 14
comptime OP_MOVE = 15

# === Arithmetic & Vectorized Operations ===
comptime OP_ADD = 20
comptime OP_SUBTRACT = 21
comptime OP_MULTIPLY = 22
comptime OP_DIVIDE = 23
comptime OP_REMAINDER = 24
comptime OP_CONCAT = 25

# === Comparison & Conditional Jumps ===
comptime OP_EQ = 30
comptime OP_NE = 31
comptime OP_LT = 32
comptime OP_LE = 33
comptime OP_GT = 34
comptime OP_GE = 35
comptime OP_IS_NULL = 36
comptime OP_NOT_NULL = 37
comptime OP_IF_ZERO = 38
comptime OP_IF_NOT_ZERO = 39

# === B-Tree Table & Cursor Opcodes ===
comptime OP_OPEN_READ = 40
comptime OP_OPEN_WRITE = 41
comptime OP_CLOSE = 42
comptime OP_REWIND = 43
comptime OP_NEXT = 44
comptime OP_PREV = 45
comptime OP_SEEK_ROWID = 46
comptime OP_ROWID = 47
comptime OP_COLUMN = 48
comptime OP_INSERT = 49
comptime OP_DELETE = 50

# === Record Packing & Output ===
comptime OP_MAKE_RECORD = 60
comptime OP_RESULT_ROW = 61

# === Scalar Functions, Cast & Metadata ===
comptime OP_FUNCTION = 70
comptime OP_CAST = 71
comptime OP_SET_CHANGES = 72
comptime OP_SET_LAST_ROWID = 73


struct Opcode(ImplicitlyCopyable, Copyable, Movable):
    """ Represents a single 5-operand VDBE Bytecode Instruction (Opcode, P1, P2, P3, P4_str, P5)."""
    var op: Int
    var p1: Int
    var p2: Int
    var p3: Int
    var p4_str: String
    var p5: Int

    def __init__(out self, op: Int, p1: Int = 0, p2: Int = 0, p3: Int = 0, p4_str: String = "", p5: Int = 0):
        self.op = op
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
        self.p4_str = p4_str
        self.p5 = p5

    def __init__(out self, *, copy: Self):
        self.op = copy.op
        self.p1 = copy.p1
        self.p2 = copy.p2
        self.p3 = copy.p3
        self.p4_str = copy.p4_str
        self.p5 = copy.p5

    def __init__(out self, *, deinit move: Self):
        self.op = move.op
        self.p1 = move.p1
        self.p2 = move.p2
        self.p3 = move.p3
        self.p4_str = move.p4_str^
        self.p5 = move.p5
