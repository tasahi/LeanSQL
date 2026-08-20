""" Universal Abstract Syntax Tree (UAST) Integration for SQLean.

Aligns SQLean AST structures with Unimo's Universal AST specification (`/mnt/c/Documents/Mojo/unimo/uast.mojo`).

Extends Unimo UAST with SQL domain AST node tags:
- Core Universal AST tags (0..15):
  UAST_PROGRAM, UAST_VAR_DECL, UAST_ASSIGN, UAST_BINOP, UAST_UNARYOP, UAST_CALL,
  UAST_IF, UAST_FOR, UAST_WHILE, UAST_RETURN, UAST_BODY, UAST_NAME, UAST_LITERAL,
  UAST_LITERAL_STR, UAST_LITERAL_BOOL, UAST_LITERAL_NUM
- Extended SQL UAST tags (100..112):
  UAST_SQL_SELECT, UAST_SQL_INSERT, UAST_SQL_UPDATE, UAST_SQL_DELETE,
  UAST_SQL_CREATE_TABLE, UAST_SQL_COLUMN_LIST, UAST_SQL_COLUMN_DEF,
  UAST_SQL_FROM, UAST_SQL_WHERE, UAST_SQL_VALUES, UAST_SQL_STAR,
  UAST_SQL_JOIN, UAST_SQL_ORDER_BY
"""

from src.types import *

# === Universal AST Node Kinds (Matched exactly to unimo/uast.mojo) ===
comptime UAST_PROGRAM = 0
comptime UAST_VAR_DECL = 1
comptime UAST_ASSIGN = 2
comptime UAST_BINOP = 3
comptime UAST_UNARYOP = 4
comptime UAST_CALL = 5
comptime UAST_IF = 6
comptime UAST_FOR = 7
comptime UAST_WHILE = 8
comptime UAST_RETURN = 9
comptime UAST_BODY = 10
comptime UAST_NAME = 11
comptime UAST_LITERAL = 12
comptime UAST_LITERAL_STR = 13
comptime UAST_LITERAL_BOOL = 14
comptime UAST_LITERAL_NUM = 15

# === Extended SQL Universal AST Node Kinds ===
comptime UAST_SQL_SELECT = 100
comptime UAST_SQL_INSERT = 101
comptime UAST_SQL_UPDATE = 102
comptime UAST_SQL_DELETE = 103
comptime UAST_SQL_CREATE_TABLE = 104
comptime UAST_SQL_COLUMN_LIST = 105
comptime UAST_SQL_COLUMN_DEF = 106
comptime UAST_SQL_FROM = 107
comptime UAST_SQL_WHERE = 108
comptime UAST_SQL_VALUES = 109
comptime UAST_SQL_STAR = 110
comptime UAST_SQL_JOIN = 111
comptime UAST_SQL_ORDER_BY = 112


struct UASTNode(ImplicitlyCopyable, Copyable, Movable):
    """ Universal AST Node compatible with unimo UASTNode structure."""
    var kind: Int
    var value: String
    var children: List[Int]
    var line: Int

    def __init__(out self):
        self.kind = UAST_PROGRAM
        self.value = ""
        self.children = List[Int]()
        self.line = 0

    def __init__(out self, kind: Int):
        self.kind = kind
        self.value = ""
        self.children = List[Int]()
        self.line = 0

    def __init__(out self, kind: Int, value: String):
        self.kind = kind
        self.value = value
        self.children = List[Int]()
        self.line = 0

    def __init__(out self, kind: Int, value: String, line: Int):
        self.kind = kind
        self.value = value
        self.children = List[Int]()
        self.line = line

    def __init__(out self, *, copy: Self):
        self.kind = copy.kind
        self.value = copy.value
        self.children = copy.children.copy()
        self.line = copy.line

    def __init__(out self, *, deinit move: Self):
        self.kind = move.kind
        self.value = move.value^
        self.children = move.children^
        self.line = move.line

    def add_child(mut self, child_idx: Int):
        """ Adds a child node index to this node."""
        self.children.append(child_idx)

    def num_children(self) -> Int:
        """ Returns the count of direct children."""
        return len(self.children)


struct UASTPool(ImplicitlyCopyable, Copyable, Movable):
    """ Flat pool allocator storing UAST nodes by integer indices."""
    var nodes: List[UASTNode]

    def __init__(out self):
        self.nodes = List[UASTNode]()

    def __init__(out self, *, copy: Self):
        self.nodes = copy.nodes.copy()

    def __init__(out self, *, deinit move: Self):
        self.nodes = move.nodes^

    def add(mut self, var node: UASTNode) -> Int:
        """ Appends a node to the pool and returns its index."""
        var idx = len(self.nodes)
        self.nodes.append(node^)
        return idx

    def get(self, idx: Int) -> UASTNode:
        """ Returns the node at index `idx`."""
        return self.nodes[idx].copy()

    def __len__(self) -> Int:
        """ Returns total number of nodes in the pool."""
        return len(self.nodes)
