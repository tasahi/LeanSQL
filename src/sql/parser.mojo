""" SQLite SQL Parser and Abstract Syntax Tree (AST).

Corresponds to `sqlite/src/parse.y`, `sqlite/src/select.c`, `sqlite/src/insert.c`,
`sqlite/src/update.c`, and `sqlite/src/delete.c`.

Parses token streams into structured AST statement nodes with full expression trees.
"""

from src.core.types import *
from src.engine.row import Value
from src.engine.schema import ColumnDef, TableDef, IndexDef
from src.core.utf import nocase_compare
from src.sql.tokenizer import (
    Token,
    TK_SELECT,
    TK_INSERT,
    TK_INTO,
    TK_VALUES,
    TK_FROM,
    TK_WHERE,
    TK_CREATE,
    TK_TABLE,
    TK_UPDATE,
    TK_SET,
    TK_DELETE,
    TK_DEFAULT,
    TK_PRIMARY,
    TK_KEY,
    TK_ORDER,
    TK_BY,
    TK_ASC,
    TK_DESC,
    TK_LIMIT,
    TK_OFFSET,
    TK_NULL,
    TK_IS,
    TK_NOT,
    TK_LIKE,
    TK_IN,
    TK_BETWEEN,
    TK_CASE,
    TK_WHEN,
    TK_THEN,
    TK_ELSE,
    TK_END,
    TK_INDEX,
    TK_DROP,
    TK_AS,
    TK_DISTINCT,
    TK_GROUP,
    TK_HAVING,
    TK_BEGIN,
    TK_COMMIT,
    TK_ROLLBACK,
    TK_SAVEPOINT,
    TK_RELEASE,
    TK_TRANSACTION,
    TK_TO,
    TK_UNIQUE,
    TK_CAST,
    TK_ID,
    TK_INTEGER,
    TK_FLOAT,
    TK_STRING,
    TK_COMMA,
    TK_SEMI,
    TK_LP,
    TK_RP,
    TK_STAR,
    TK_EQ,
    TK_LT,
    TK_GT,
    TK_LE,
    TK_GE,
    TK_NE,
    TK_PLUS,
    TK_MINUS,
    TK_SLASH,
    TK_PERCENT,
    TK_CONCAT,
    TK_AND,
    TK_OR,
    TK_DOT,
    TK_JOIN,
    TK_INNER,
    TK_LEFT,
    TK_OUTER,
    TK_CROSS,
    TK_ON,
    TK_UNION,
    TK_ALL,
    TK_INTERSECT,
    TK_EXCEPT,
    TK_PRAGMA,
    TK_ALTER,
    TK_RENAME,
    TK_ADD,
    TK_COLUMN,
    TK_VIEW,
    TK_WITH,
    TK_RECURSIVE,
    TK_OVER,
    TK_PARTITION,
    TK_TRIGGER,
    TK_BEFORE,
    TK_AFTER,
    TK_FOR,
    TK_EACH,
    TK_ROW,
    TK_ARROW,
    TK_ARROW_TEXT,
    TK_END,
    TK_EOF,
)

# === Expression Node Types ===
comptime EXPR_LITERAL = 1
comptime EXPR_COLUMN = 2
comptime EXPR_BINARY = 3
comptime EXPR_UNARY = 4
comptime EXPR_FUNC = 5
comptime EXPR_CASE = 6
comptime EXPR_BETWEEN = 7
comptime EXPR_IN = 8
comptime EXPR_CAST = 9
comptime EXPR_STAR = 10


struct Expr(ImplicitlyCopyable, Copyable, Movable):
    """ Represents an expression node in the AST."""
    var kind: Int
    var val: Value
    var col_name: String
    var op: String
    var func_name: String
    var args: List[Expr]
    var is_desc: Bool
    var is_window: Bool
    var window_partition: List[Expr]
    var window_order: List[Expr]

    def __init__(out self, kind: Int = EXPR_LITERAL):
        self.kind = kind
        self.val = Value.of_null()
        self.col_name = ""
        self.op = ""
        self.func_name = ""
        self.args = List[Expr]()
        self.is_desc = False
        self.is_window = False
        self.window_partition = List[Expr]()
        self.window_order = List[Expr]()

    def __init__(out self, *, copy: Self):
        self.kind = copy.kind
        self.val = copy.val.copy()
        self.col_name = copy.col_name
        self.op = copy.op
        self.func_name = copy.func_name
        self.args = copy.args.copy()
        self.is_desc = copy.is_desc
        self.is_window = copy.is_window
        self.window_partition = copy.window_partition.copy()
        self.window_order = copy.window_order.copy()

    def __init__(out self, *, deinit move: Self):
        self.kind = move.kind
        self.val = move.val^
        self.col_name = move.col_name^
        self.op = move.op^
        self.func_name = move.func_name^
        self.args = move.args^
        self.is_desc = move.is_desc
        self.is_window = move.is_window
        self.window_partition = move.window_partition^
        self.window_order = move.window_order^

    def __deinit__(deinit self):
        pass

    def copy(self) -> Expr:
        var res = Expr(self.kind)
        res.val = self.val.copy()
        res.col_name = self.col_name
        res.op = self.op
        res.func_name = self.func_name
        res.args = self.args.copy()
        res.is_desc = self.is_desc
        res.is_window = self.is_window
        res.window_partition = self.window_partition.copy()
        res.window_order = self.window_order.copy()
        return res^

    @staticmethod
    def literal(v: Value) -> Expr:
        var e = Expr(EXPR_LITERAL)
        e.val = v.copy()
        return e^

    @staticmethod
    def column(name: String) -> Expr:
        var e = Expr(EXPR_COLUMN)
        e.col_name = name
        return e^

    @staticmethod
    def star() -> Expr:
        return Expr(EXPR_STAR)

    @staticmethod
    def binary(op: String, left: Expr, right: Expr) -> Expr:
        var e = Expr(EXPR_BINARY)
        e.op = op
        e.args.append(left.copy())
        e.args.append(right.copy())
        return e^

    @staticmethod
    def unary(op: String, child: Expr) -> Expr:
        var e = Expr(EXPR_UNARY)
        e.op = op
        e.args.append(child.copy())
        return e^

    @staticmethod
    def function(name: String, args: List[Expr]) -> Expr:
        var e = Expr(EXPR_FUNC)
        e.func_name = name
        e.args = args.copy()
        return e^


# === Statement Types ===
comptime STMT_SELECT = 1
comptime STMT_INSERT = 2
comptime STMT_UPDATE = 3
comptime STMT_DELETE = 4
comptime STMT_CREATE_TABLE = 5
comptime STMT_CREATE_INDEX = 6
comptime STMT_DROP_INDEX = 7
comptime STMT_DROP_TABLE = 8
comptime STMT_TRANS = 9


struct SelectColumn(ImplicitlyCopyable, Copyable, Movable):
    var expr: Expr
    var col_alias: String

    def __init__(out self, expr: Expr, col_alias: String = ""):
        self.expr = expr.copy()
        self.col_alias = col_alias

    def __init__(out self, *, copy: Self):
        self.expr = copy.expr.copy()
        self.col_alias = copy.col_alias

    def __init__(out self, *, deinit move: Self):
        self.expr = move.expr^
        self.col_alias = move.col_alias^


comptime JOIN_INNER = 1
comptime JOIN_LEFT = 2
comptime JOIN_CROSS = 3

comptime COMPOUND_NONE = 0
comptime COMPOUND_UNION = 1
comptime COMPOUND_UNION_ALL = 2
comptime COMPOUND_INTERSECT = 3
comptime COMPOUND_EXCEPT = 4


struct JoinClause(ImplicitlyCopyable, Copyable, Movable):
    var join_type: Int
    var table_name: String
    var table_alias: String
    var on_expr: List[Expr]

    def __init__(out self, join_type: Int, table_name: String, table_alias: String = ""):
        self.join_type = join_type
        self.table_name = table_name
        self.table_alias = table_alias
        self.on_expr = List[Expr]()

    def __init__(out self, *, copy: Self):
        self.join_type = copy.join_type
        self.table_name = copy.table_name
        self.table_alias = copy.table_alias
        self.on_expr = copy.on_expr.copy()

    def __init__(out self, *, deinit move: Self):
        self.join_type = move.join_type
        self.table_name = move.table_name^
        self.table_alias = move.table_alias^
        self.on_expr = move.on_expr^


struct CTETable(ImplicitlyCopyable, Copyable, Movable):
    var name: String
    var columns: List[String]
    var subquery: List[SelectStmt]

    def __init__(out self, name: String):
        self.name = name
        self.columns = List[String]()
        self.subquery = List[SelectStmt]()

    def __init__(out self, *, copy: Self):
        self.name = copy.name
        self.columns = copy.columns.copy()
        self.subquery = copy.subquery.copy()

    def __init__(out self, *, deinit move: Self):
        self.name = move.name^
        self.columns = move.columns^
        self.subquery = move.subquery^

    def __deinit__(deinit self):
        pass


struct SelectStmt(ImplicitlyCopyable, Copyable, Movable):
    var columns: List[SelectColumn]
    var is_star: Bool
    var is_distinct: Bool
    var table_name: String
    var table_alias: String
    var joins: List[JoinClause]
    var where_expr: List[Expr]
    var group_by: List[String]
    var having_expr: List[Expr]
    var order_by: List[Expr]
    var limit_val: Int
    var offset_val: Int
    var compound_op: Int
    var compound_next: List[SelectStmt]
    var from_subquery: List[SelectStmt]
    var ctes: List[CTETable]
    var is_recursive_cte: Bool

    def __init__(out self):
        self.columns = List[SelectColumn]()
        self.is_star = False
        self.is_distinct = False
        self.table_name = ""
        self.table_alias = ""
        self.joins = List[JoinClause]()
        self.where_expr = List[Expr]()
        self.group_by = List[String]()
        self.having_expr = List[Expr]()
        self.order_by = List[Expr]()
        self.limit_val = -1
        self.offset_val = 0
        self.compound_op = COMPOUND_NONE
        self.compound_next = List[SelectStmt]()
        self.from_subquery = List[SelectStmt]()
        self.ctes = List[CTETable]()
        self.is_recursive_cte = False

    def __init__(out self, *, copy: Self):
        self.columns = copy.columns.copy()
        self.is_star = copy.is_star
        self.is_distinct = copy.is_distinct
        self.table_name = copy.table_name
        self.table_alias = copy.table_alias
        self.joins = copy.joins.copy()
        self.where_expr = copy.where_expr.copy()
        self.group_by = copy.group_by.copy()
        self.having_expr = copy.having_expr.copy()
        self.order_by = copy.order_by.copy()
        self.limit_val = copy.limit_val
        self.offset_val = copy.offset_val
        self.compound_op = copy.compound_op
        self.compound_next = copy.compound_next.copy()
        self.from_subquery = copy.from_subquery.copy()
        self.ctes = copy.ctes.copy()
        self.is_recursive_cte = copy.is_recursive_cte

    def __init__(out self, *, deinit move: Self):
        self.columns = move.columns^
        self.is_star = move.is_star
        self.is_distinct = move.is_distinct
        self.table_name = move.table_name^
        self.table_alias = move.table_alias^
        self.joins = move.joins^
        self.where_expr = move.where_expr^
        self.group_by = move.group_by^
        self.having_expr = move.having_expr^
        self.order_by = move.order_by^
        self.limit_val = move.limit_val
        self.offset_val = move.offset_val
        self.compound_op = move.compound_op
        self.compound_next = move.compound_next^
        self.from_subquery = move.from_subquery^
        self.ctes = move.ctes^
        self.is_recursive_cte = move.is_recursive_cte

    def __deinit__(deinit self):
        pass


struct InsertStmt(ImplicitlyCopyable, Copyable, Movable):
    var table_name: String
    var columns: List[String]
    var values: List[Expr]
    var select_stmt: List[SelectStmt]

    def __init__(out self, table_name: String):
        self.table_name = table_name
        self.columns = List[String]()
        self.values = List[Expr]()
        self.select_stmt = List[SelectStmt]()

    def __init__(out self, *, copy: Self):
        self.table_name = copy.table_name
        self.columns = copy.columns.copy()
        self.values = copy.values.copy()
        self.select_stmt = copy.select_stmt.copy()

    def __init__(out self, *, deinit move: Self):
        self.table_name = move.table_name^
        self.columns = move.columns^
        self.values = move.values^
        self.select_stmt = move.select_stmt^

    def __deinit__(deinit self):
        pass


struct UpdateAssignment(ImplicitlyCopyable, Copyable, Movable):
    var col_name: String
    var expr: Expr

    def __init__(out self, col_name: String, expr: Expr):
        self.col_name = col_name
        self.expr = expr.copy()

    def __init__(out self, *, copy: Self):
        self.col_name = copy.col_name
        self.expr = copy.expr.copy()

    def __init__(out self, *, deinit move: Self):
        self.col_name = move.col_name^
        self.expr = move.expr^


struct UpdateStmt(ImplicitlyCopyable, Copyable, Movable):
    var table_name: String
    var assignments: List[UpdateAssignment]
    var where_expr: List[Expr]

    def __init__(out self, table_name: String):
        self.table_name = table_name
        self.assignments = List[UpdateAssignment]()
        self.where_expr = List[Expr]()

    def __init__(out self, *, copy: Self):
        self.table_name = copy.table_name
        self.assignments = copy.assignments.copy()
        self.where_expr = copy.where_expr.copy()

    def __init__(out self, *, deinit move: Self):
        self.table_name = move.table_name^
        self.assignments = move.assignments^
        self.where_expr = move.where_expr^

    def __deinit__(deinit self):
        pass


struct DeleteStmt(ImplicitlyCopyable, Copyable, Movable):
    var table_name: String
    var where_expr: List[Expr]

    def __init__(out self, table_name: String):
        self.table_name = table_name
        self.where_expr = List[Expr]()

    def __init__(out self, *, copy: Self):
        self.table_name = copy.table_name
        self.where_expr = copy.where_expr.copy()

    def __init__(out self, *, deinit move: Self):
        self.table_name = move.table_name^
        self.where_expr = move.where_expr^

    def __deinit__(deinit self):
        pass


struct CreateTableStmt(ImplicitlyCopyable, Copyable, Movable):
    var table_name: String
    var columns: List[ColumnDef]

    def __init__(out self, table_name: String):
        self.table_name = table_name
        self.columns = List[ColumnDef]()

    def __init__(out self, *, copy: Self):
        self.table_name = copy.table_name
        self.columns = copy.columns.copy()

    def __init__(out self, *, deinit move: Self):
        self.table_name = move.table_name^
        self.columns = move.columns^

    def __deinit__(deinit self):
        pass


struct CreateIndexStmt(ImplicitlyCopyable, Copyable, Movable):
    var index_name: String
    var table_name: String
    var columns: List[String]
    var is_unique: Bool

    def __init__(out self, index_name: String, table_name: String, is_unique: Bool):
        self.index_name = index_name
        self.table_name = table_name
        self.columns = List[String]()
        self.is_unique = is_unique

    def __init__(out self, *, copy: Self):
        self.index_name = copy.index_name
        self.table_name = copy.table_name
        self.columns = copy.columns.copy()
        self.is_unique = copy.is_unique

    def __init__(out self, *, deinit move: Self):
        self.index_name = move.index_name^
        self.table_name = move.table_name^
        self.columns = move.columns^
        self.is_unique = move.is_unique

    def __deinit__(deinit self):
        pass


struct DropIndexStmt(ImplicitlyCopyable, Copyable, Movable):
    var index_name: String

    def __init__(out self, index_name: String):
        self.index_name = index_name

    def __init__(out self, *, copy: Self):
        self.index_name = copy.index_name

    def __init__(out self, *, deinit move: Self):
        self.index_name = move.index_name^

    def __deinit__(deinit self):
        pass


struct TransStmt(ImplicitlyCopyable, Copyable, Movable):
    var op_type: Int
    var name: String

    def __init__(out self, op_type: Int, name: String = ""):
        self.op_type = op_type
        self.name = name

    def __init__(out self, *, copy: Self):
        self.op_type = copy.op_type
        self.name = copy.name

    def __init__(out self, *, deinit move: Self):
        self.op_type = move.op_type
        self.name = move.name^

    def __deinit__(deinit self):
        pass


comptime STMT_PRAGMA = 10
comptime STMT_ALTER_TABLE = 11
comptime STMT_CREATE_VIEW = 12
comptime STMT_DROP_VIEW = 13

comptime ALTER_RENAME_TABLE = 1
comptime ALTER_ADD_COLUMN = 2
comptime ALTER_RENAME_COLUMN = 3


struct PragmaStmt(ImplicitlyCopyable, Copyable, Movable):
    var pragma_name: String
    var pragma_arg: String
    var pragma_val: String
    var has_val: Bool

    def __init__(out self, pragma_name: String, pragma_arg: String = "", pragma_val: String = "", has_val: Bool = False):
        self.pragma_name = pragma_name
        self.pragma_arg = pragma_arg
        self.pragma_val = pragma_val
        self.has_val = has_val

    def __init__(out self, *, copy: Self):
        self.pragma_name = copy.pragma_name
        self.pragma_arg = copy.pragma_arg
        self.pragma_val = copy.pragma_val
        self.has_val = copy.has_val

    def __init__(out self, *, deinit move: Self):
        self.pragma_name = move.pragma_name^
        self.pragma_arg = move.pragma_arg^
        self.pragma_val = move.pragma_val^
        self.has_val = move.has_val

    def __deinit__(deinit self):
        pass


struct AlterTableStmt(ImplicitlyCopyable, Copyable, Movable):
    var op_type: Int
    var table_name: String
    var new_name: String
    var column_def: List[ColumnDef]

    def __init__(out self, op_type: Int, table_name: String, new_name: String = ""):
        self.op_type = op_type
        self.table_name = table_name
        self.new_name = new_name
        self.column_def = List[ColumnDef]()

    def __init__(out self, *, copy: Self):
        self.op_type = copy.op_type
        self.table_name = copy.table_name
        self.new_name = copy.new_name
        self.column_def = copy.column_def.copy()

    def __init__(out self, *, deinit move: Self):
        self.op_type = move.op_type
        self.table_name = move.table_name^
        self.new_name = move.new_name^
        self.column_def = move.column_def^

    def __deinit__(deinit self):
        pass


struct CreateViewStmt(ImplicitlyCopyable, Copyable, Movable):
    var view_name: String
    var select_stmt: List[SelectStmt]

    def __init__(out self, view_name: String):
        self.view_name = view_name
        self.select_stmt = List[SelectStmt]()

    def __init__(out self, *, copy: Self):
        self.view_name = copy.view_name
        self.select_stmt = copy.select_stmt.copy()

    def __init__(out self, *, deinit move: Self):
        self.view_name = move.view_name^
        self.select_stmt = move.select_stmt^

    def __deinit__(deinit self):
        pass


struct DropViewStmt(ImplicitlyCopyable, Copyable, Movable):
    var view_name: String

    def __init__(out self, view_name: String):
        self.view_name = view_name

    def __init__(out self, *, copy: Self):
        self.view_name = copy.view_name

    def __init__(out self, *, deinit move: Self):
        self.view_name = move.view_name^

    def __deinit__(deinit self):
        pass


comptime STMT_CREATE_TRIGGER = 14
comptime STMT_DROP_TRIGGER = 15

comptime TRIGGER_BEFORE = 1
comptime TRIGGER_AFTER = 2
comptime TRIGGER_EVENT_INSERT = 1
comptime TRIGGER_EVENT_UPDATE = 2
comptime TRIGGER_EVENT_DELETE = 3


struct CreateTriggerStmt(ImplicitlyCopyable, Copyable, Movable):
    var name: String
    var timing: Int # TRIGGER_BEFORE or TRIGGER_AFTER
    var event_type: Int # INSERT/UPDATE/DELETE
    var table_name: String
    var action_sql: String

    def __init__(out self, name: String, timing: Int, event_type: Int, table_name: String, action_sql: String):
        self.name = name
        self.timing = timing
        self.event_type = event_type
        self.table_name = table_name
        self.action_sql = action_sql

    def __init__(out self, *, copy: Self):
        self.name = copy.name
        self.timing = copy.timing
        self.event_type = copy.event_type
        self.table_name = copy.table_name
        self.action_sql = copy.action_sql

    def __init__(out self, *, deinit move: Self):
        self.name = move.name^
        self.timing = move.timing
        self.event_type = move.event_type
        self.table_name = move.table_name^
        self.action_sql = move.action_sql^

    def __deinit__(deinit self):
        pass


struct DropTriggerStmt(ImplicitlyCopyable, Copyable, Movable):
    var name: String

    def __init__(out self, name: String):
        self.name = name

    def __init__(out self, *, copy: Self):
        self.name = copy.name

    def __init__(out self, *, deinit move: Self):
        self.name = move.name^

    def __deinit__(deinit self):
        pass


struct ASTStatement(ImplicitlyCopyable, Copyable, Movable):
    var stmt_type: Int
    var select_stmt: List[SelectStmt]
    var insert_stmt: List[InsertStmt]
    var update_stmt: List[UpdateStmt]
    var delete_stmt: List[DeleteStmt]
    var create_table_stmt: List[CreateTableStmt]
    var create_index_stmt: List[CreateIndexStmt]
    var drop_index_stmt: List[DropIndexStmt]
    var trans_stmt: List[TransStmt]
    var pragma_stmt: List[PragmaStmt]
    var alter_table_stmt: List[AlterTableStmt]
    var create_view_stmt: List[CreateViewStmt]
    var drop_view_stmt: List[DropViewStmt]
    var create_trigger_stmt: List[CreateTriggerStmt]
    var drop_trigger_stmt: List[DropTriggerStmt]

    def __init__(out self, stmt_type: Int):
        self.stmt_type = stmt_type
        self.select_stmt = List[SelectStmt]()
        self.insert_stmt = List[InsertStmt]()
        self.update_stmt = List[UpdateStmt]()
        self.delete_stmt = List[DeleteStmt]()
        self.create_table_stmt = List[CreateTableStmt]()
        self.create_index_stmt = List[CreateIndexStmt]()
        self.drop_index_stmt = List[DropIndexStmt]()
        self.trans_stmt = List[TransStmt]()
        self.pragma_stmt = List[PragmaStmt]()
        self.alter_table_stmt = List[AlterTableStmt]()
        self.create_view_stmt = List[CreateViewStmt]()
        self.drop_view_stmt = List[DropViewStmt]()
        self.create_trigger_stmt = List[CreateTriggerStmt]()
        self.drop_trigger_stmt = List[DropTriggerStmt]()

    def __init__(out self, *, copy: Self):
        self.stmt_type = copy.stmt_type
        self.select_stmt = copy.select_stmt.copy()
        self.insert_stmt = copy.insert_stmt.copy()
        self.update_stmt = copy.update_stmt.copy()
        self.delete_stmt = copy.delete_stmt.copy()
        self.create_table_stmt = copy.create_table_stmt.copy()
        self.create_index_stmt = copy.create_index_stmt.copy()
        self.drop_index_stmt = copy.drop_index_stmt.copy()
        self.trans_stmt = copy.trans_stmt.copy()
        self.pragma_stmt = copy.pragma_stmt.copy()
        self.alter_table_stmt = copy.alter_table_stmt.copy()
        self.create_view_stmt = copy.create_view_stmt.copy()
        self.drop_view_stmt = copy.drop_view_stmt.copy()
        self.create_trigger_stmt = copy.create_trigger_stmt.copy()
        self.drop_trigger_stmt = copy.drop_trigger_stmt.copy()

    def __init__(out self, *, deinit move: Self):
        self.stmt_type = move.stmt_type
        self.select_stmt = move.select_stmt^
        self.insert_stmt = move.insert_stmt^
        self.update_stmt = move.update_stmt^
        self.delete_stmt = move.delete_stmt^
        self.create_table_stmt = move.create_table_stmt^
        self.create_index_stmt = move.create_index_stmt^
        self.drop_index_stmt = move.drop_index_stmt^
        self.trans_stmt = move.trans_stmt^
        self.pragma_stmt = move.pragma_stmt^
        self.alter_table_stmt = move.alter_table_stmt^
        self.create_view_stmt = move.create_view_stmt^
        self.drop_view_stmt = move.drop_view_stmt^
        self.create_trigger_stmt = move.create_trigger_stmt^
        self.drop_trigger_stmt = move.drop_trigger_stmt^

    def __deinit__(deinit self):
        pass


# === Parser Functions ===

def parse_expr_atom(tokens: List[Token], mut pos: Int) raises -> Expr:
    if pos >= len(tokens):
        raise Error("Unexpected end of tokens in expression")

    var t = tokens[pos]

    # 1. NULL
    if t.token_type == TK_NULL:
        pos += 1
        return Expr.literal(Value.of_null())

    # 2. Integer
    if t.token_type == TK_INTEGER:
        pos += 1
        var ival = Int64(atol(t.text))
        return Expr.literal(Value.of_int(ival))

    # 3. Float
    if t.token_type == TK_FLOAT:
        pos += 1
        var fval = Float64(atof(t.text))
        return Expr.literal(Value.of_float(fval))

    # 4. String
    if t.token_type == TK_STRING:
        pos += 1
        return Expr.literal(Value.of_text(t.text))

    # 5. Star (*)
    if t.token_type == TK_STAR:
        pos += 1
        return Expr.star()

    # 6. Unary minus
    if t.token_type == TK_MINUS:
        pos += 1
        var child = parse_expr_atom(tokens, pos)
        if child.kind == EXPR_LITERAL:
            if child.val.type_tag == SQLITE_INTEGER:
                return Expr.literal(Value.of_int(-child.val.int_val))
            elif child.val.type_tag == SQLITE_FLOAT:
                return Expr.literal(Value.of_float(-child.val.float_val))
        return Expr.unary("-", child)

    # 7. Parenthesized expression: (expr) or (SELECT ...)
    if t.token_type == TK_LP:
        pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_SELECT:
            var sub_tokens = List[Token]()
            var depth = 1
            while pos < len(tokens) and depth > 0:
                if tokens[pos].token_type == TK_LP:
                    depth += 1
                elif tokens[pos].token_type == TK_RP:
                    depth -= 1
                    if depth == 0:
                        pos += 1
                        break
                sub_tokens.append(tokens[pos].copy())
                pos += 1
            var sub_ast = parse_sql(sub_tokens)
            if len(sub_ast.select_stmt) > 0:
                var sub_e = Expr(EXPR_FUNC)
                sub_e.func_name = "SUBQUERY"
                var sub_sel = sub_ast.select_stmt[0].copy()
                sub_e.col_name = sub_sel.table_name
                if len(sub_sel.columns) > 0:
                    sub_e.args.append(sub_sel.columns[0].expr.copy())
                return sub_e^
        var e = parse_expr(tokens, pos)
        if pos < len(tokens) and tokens[pos].token_type == TK_RP:
            pos += 1
        return e^

    # 8. CASE ... WHEN ... THEN ... [ELSE ...] END
    if t.token_type == TK_CASE:
        pos += 1
        var case_expr = Expr(EXPR_CASE)
        while pos < len(tokens) and tokens[pos].token_type == TK_WHEN:
            pos += 1
            var cond = parse_expr(tokens, pos)
            case_expr.args.append(cond^)
            if pos < len(tokens) and tokens[pos].token_type == TK_THEN:
                pos += 1
            var res = parse_expr(tokens, pos)
            case_expr.args.append(res^)
        if pos < len(tokens) and tokens[pos].token_type == TK_ELSE:
            pos += 1
            var else_val = parse_expr(tokens, pos)
            case_expr.args.append(else_val^)
        if pos < len(tokens) and tokens[pos].token_type == TK_END:
            pos += 1
        return case_expr^

    # 9. CAST(expr AS type)
    if t.token_type == TK_CAST:
        pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_LP:
            pos += 1
        var inner_expr = parse_expr(tokens, pos)
        var target_type = "INTEGER"
        if pos < len(tokens) and tokens[pos].token_type == TK_AS:
            pos += 1
        if pos < len(tokens):
            target_type = tokens[pos].text
            pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_RP:
            pos += 1
        var cast_e = Expr(EXPR_CAST)
        cast_e.col_name = target_type
        cast_e.args.append(inner_expr^)
        return cast_e^

    # 10. Function call, Table-qualified column (t.col or t.*), or Column identifier
    if t.token_type == TK_ID:
        var name = t.text
        pos += 1
        # Check if table qualification: tbl.col or alias.col or alias.*
        if pos < len(tokens) and tokens[pos].token_type == TK_DOT:
            pos += 1
            if pos < len(tokens) and (tokens[pos].token_type == TK_ID or tokens[pos].token_type == TK_STAR):
                var sub_part = tokens[pos].text
                pos += 1
                if sub_part == "*":
                    var star_e = Expr.star()
                    star_e.col_name = name + ".*"
                    return star_e^
                name = name + "." + sub_part
        if pos < len(tokens) and tokens[pos].token_type == TK_LP:
            pos += 1
            var fn_args = List[Expr]()
            var is_distinct_call = False
            if pos < len(tokens) and tokens[pos].token_type == TK_DISTINCT:
                is_distinct_call = True
                pos += 1
            if pos < len(tokens) and tokens[pos].token_type != TK_RP:
                fn_args.append(parse_expr(tokens, pos))
                while pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                    pos += 1
                    fn_args.append(parse_expr(tokens, pos))
            if pos < len(tokens) and tokens[pos].token_type == TK_RP:
                pos += 1
            var fn_e = Expr.function(name, fn_args)
            if is_distinct_call:
                fn_e.op = "DISTINCT"

            # Check for Window function: OVER ( [PARTITION BY ...] [ORDER BY ...] )
            if pos < len(tokens) and tokens[pos].token_type == TK_OVER:
                pos += 1
                fn_e.is_window = True
                if pos < len(tokens) and tokens[pos].token_type == TK_LP:
                    pos += 1
                    # Check PARTITION BY
                    if pos < len(tokens) and tokens[pos].token_type == TK_PARTITION:
                        pos += 1
                        if pos < len(tokens) and tokens[pos].token_type == TK_BY:
                            pos += 1
                        fn_e.window_partition.append(parse_expr(tokens, pos))
                        while pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                            pos += 1
                            fn_e.window_partition.append(parse_expr(tokens, pos))
                    # Check ORDER BY
                    if pos < len(tokens) and tokens[pos].token_type == TK_ORDER:
                        pos += 1
                        if pos < len(tokens) and tokens[pos].token_type == TK_BY:
                            pos += 1
                        var ord_e = parse_expr(tokens, pos)
                        if pos < len(tokens) and tokens[pos].token_type == TK_DESC:
                            ord_e.is_desc = True
                            pos += 1
                        elif pos < len(tokens) and tokens[pos].token_type == TK_ASC:
                            ord_e.is_desc = False
                            pos += 1
                        fn_e.window_order.append(ord_e^)
                        while pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                            pos += 1
                            var ord_next = parse_expr(tokens, pos)
                            if pos < len(tokens) and tokens[pos].token_type == TK_DESC:
                                ord_next.is_desc = True
                                pos += 1
                            elif pos < len(tokens) and tokens[pos].token_type == TK_ASC:
                                ord_next.is_desc = False
                                pos += 1
                            fn_e.window_order.append(ord_next^)
                    if pos < len(tokens) and tokens[pos].token_type == TK_RP:
                        pos += 1

            return fn_e^
        return Expr.column(name)

    raise Error("Unrecognized expression token: " + t.text)


def parse_expr_mult(tokens: List[Token], mut pos: Int) raises -> Expr:
    var left = parse_expr_atom(tokens, pos)
    while pos < len(tokens):
        var tt = tokens[pos].token_type
        if tt == TK_STAR:
            pos += 1
            var right = parse_expr_atom(tokens, pos)
            left = Expr.binary("*", left, right)
        elif tt == TK_SLASH:
            pos += 1
            var right = parse_expr_atom(tokens, pos)
            left = Expr.binary("/", left, right)
        elif tt == TK_PERCENT:
            pos += 1
            var right = parse_expr_atom(tokens, pos)
            left = Expr.binary("%", left, right)
        elif tt == TK_CONCAT:
            pos += 1
            var right = parse_expr_atom(tokens, pos)
            left = Expr.binary("||", left, right)
        elif tt == TK_ARROW:
            pos += 1
            var right = parse_expr_atom(tokens, pos)
            left = Expr.binary("->", left, right)
        elif tt == TK_ARROW_TEXT:
            pos += 1
            var right = parse_expr_atom(tokens, pos)
            left = Expr.binary("->>", left, right)
        else:
            break
    return left^


def parse_expr_add(tokens: List[Token], mut pos: Int) raises -> Expr:
    var left = parse_expr_mult(tokens, pos)
    while pos < len(tokens):
        var tt = tokens[pos].token_type
        if tt == TK_PLUS:
            pos += 1
            var right = parse_expr_mult(tokens, pos)
            left = Expr.binary("+", left, right)
        elif tt == TK_MINUS:
            pos += 1
            var right = parse_expr_mult(tokens, pos)
            left = Expr.binary("-", left, right)
        else:
            break
    return left^


def parse_expr_cmp(tokens: List[Token], mut pos: Int) raises -> Expr:
    var left = parse_expr_add(tokens, pos)
    while pos < len(tokens):
        var tt = tokens[pos].token_type
        if tt == TK_EQ:
            pos += 1
            var right = parse_expr_add(tokens, pos)
            left = Expr.binary("=", left, right)
        elif tt == TK_NE:
            pos += 1
            var right = parse_expr_add(tokens, pos)
            left = Expr.binary("!=", left, right)
        elif tt == TK_LT:
            pos += 1
            var right = parse_expr_add(tokens, pos)
            left = Expr.binary("<", left, right)
        elif tt == TK_LE:
            pos += 1
            var right = parse_expr_add(tokens, pos)
            left = Expr.binary("<=", left, right)
        elif tt == TK_GT:
            pos += 1
            var right = parse_expr_add(tokens, pos)
            left = Expr.binary(">", left, right)
        elif tt == TK_GE:
            pos += 1
            var right = parse_expr_add(tokens, pos)
            left = Expr.binary(">=", left, right)
        elif tt == TK_IS:
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_NOT:
                pos += 1
                var right = parse_expr_add(tokens, pos)
                left = Expr.binary("IS NOT", left, right)
            else:
                var right = parse_expr_add(tokens, pos)
                left = Expr.binary("IS", left, right)
        elif tt == TK_LIKE:
            pos += 1
            var right = parse_expr_add(tokens, pos)
            left = Expr.binary("LIKE", left, right)
        elif tt == TK_BETWEEN:
            pos += 1
            var low = parse_expr_add(tokens, pos)
            if pos < len(tokens) and tokens[pos].token_type == TK_AND:
                pos += 1
            var high = parse_expr_add(tokens, pos)
            var b_expr = Expr(EXPR_BETWEEN)
            b_expr.args.append(left^)
            b_expr.args.append(low^)
            b_expr.args.append(high^)
            left = b_expr^
        elif tt == TK_IN:
            pos += 1
            var in_expr = Expr(EXPR_IN)
            in_expr.args.append(left^)
            if pos < len(tokens) and tokens[pos].token_type == TK_LP:
                pos += 1
            while pos < len(tokens) and tokens[pos].token_type != TK_RP and tokens[pos].token_type != TK_SEMI and tokens[pos].token_type != TK_EOF:
                in_expr.args.append(parse_expr(tokens, pos))
                if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                    pos += 1
                else:
                    break
            if pos < len(tokens) and tokens[pos].token_type == TK_RP:
                pos += 1
            left = in_expr^
        elif tt == TK_NOT:
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_IN:
                pos += 1
                var in_expr = Expr(EXPR_IN)
                in_expr.op = "NOT IN"
                in_expr.args.append(left^)
                if pos < len(tokens) and tokens[pos].token_type == TK_LP:
                    pos += 1
                while pos < len(tokens) and tokens[pos].token_type != TK_RP and tokens[pos].token_type != TK_SEMI and tokens[pos].token_type != TK_EOF:
                    in_expr.args.append(parse_expr(tokens, pos))
                    if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                        pos += 1
                    else:
                        break
                if pos < len(tokens) and tokens[pos].token_type == TK_RP:
                    pos += 1
                left = in_expr^
            else:
                var right = parse_expr_add(tokens, pos)
                left = Expr.unary("NOT", right)
        else:
            break
    return left^


def parse_expr_and(tokens: List[Token], mut pos: Int) raises -> Expr:
    var left = parse_expr_cmp(tokens, pos)
    while pos < len(tokens) and tokens[pos].token_type == TK_AND:
        pos += 1
        var right = parse_expr_cmp(tokens, pos)
        left = Expr.binary("AND", left, right)
    return left^


def parse_expr_or(tokens: List[Token], mut pos: Int) raises -> Expr:
    var left = parse_expr_and(tokens, pos)
    while pos < len(tokens) and tokens[pos].token_type == TK_OR:
        pos += 1
        var right = parse_expr_and(tokens, pos)
        left = Expr.binary("OR", left, right)
    return left^


def parse_expr(tokens: List[Token], mut pos: Int) raises -> Expr:
    return parse_expr_or(tokens, pos)


def parse_sql(tokens: List[Token]) raises -> ASTStatement:
    """ Parses a complete tokenized SQL statement into an ASTStatement."""
    if len(tokens) == 0 or tokens[0].token_type == TK_EOF:
        raise Error("Empty SQL statement")

    var pos = 0
    var first_type = tokens[0].token_type
    # 0. WITH [RECURSIVE] name [(col, ...)] AS (subquery) ... SELECT ...
    var ctes_parsed = List[CTETable]()
    var is_recursive = False
    if first_type == TK_WITH:
        pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_RECURSIVE:
            is_recursive = True
            pos += 1
        while pos < len(tokens) and tokens[pos].token_type == TK_ID:
            var cte_name = tokens[pos].text
            pos += 1
            var cte_obj = CTETable(cte_name)
            if pos < len(tokens) and tokens[pos].token_type == TK_LP:
                pos += 1
                while pos < len(tokens) and tokens[pos].token_type == TK_ID:
                    cte_obj.columns.append(tokens[pos].text)
                    pos += 1
                    if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                        pos += 1
                    else:
                        break
                if pos < len(tokens) and tokens[pos].token_type == TK_RP:
                    pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_AS:
                pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_LP:
                pos += 1
                var sub_tokens = List[Token]()
                var depth = 1
                while pos < len(tokens) and depth > 0:
                    if tokens[pos].token_type == TK_LP:
                        depth += 1
                    elif tokens[pos].token_type == TK_RP:
                        depth -= 1
                        if depth == 0:
                            pos += 1
                            break
                    sub_tokens.append(tokens[pos].copy())
                    pos += 1
                var sub_ast = parse_sql(sub_tokens)
                if len(sub_ast.select_stmt) > 0:
                    cte_obj.subquery.append(sub_ast.select_stmt[0].copy())
            ctes_parsed.append(cte_obj^)
            if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                pos += 1
            else:
                break
        if pos < len(tokens):
            first_type = tokens[pos].token_type

    # 1. SELECT
    if first_type == TK_SELECT:
        var select = SelectStmt()
        select.ctes = ctes_parsed.copy()
        select.is_recursive_cte = is_recursive
        pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_DISTINCT:
            select.is_distinct = True
            pos += 1

        # Columns
        if pos < len(tokens) and tokens[pos].token_type == TK_STAR:
            select.is_star = True
            select.columns.append(SelectColumn(Expr.star()))
            pos += 1
        else:
            while pos < len(tokens) and tokens[pos].token_type != TK_FROM and tokens[pos].token_type != TK_SEMI and tokens[pos].token_type != TK_EOF:
                var col_expr = parse_expr(tokens, pos)
                var alias_name = String()
                if pos < len(tokens) and tokens[pos].token_type == TK_AS:
                    pos += 1
                    if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                        alias_name = tokens[pos].text
                        pos += 1
                elif pos < len(tokens) and tokens[pos].token_type == TK_ID and tokens[pos].token_type != TK_FROM and tokens[pos].token_type != TK_COMMA:
                    alias_name = tokens[pos].text
                    pos += 1
                select.columns.append(SelectColumn(col_expr^, alias_name))
                if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                    pos += 1
                else:
                    break

        # FROM table [AS alias] or FROM (SELECT ...) [AS alias]
        if pos < len(tokens) and tokens[pos].token_type == TK_FROM:
            pos += 1
            # Subquery in FROM: FROM (SELECT ...)
            if pos < len(tokens) and tokens[pos].token_type == TK_LP:
                pos += 1
                var sub_tokens = List[Token]()
                var depth = 1
                while pos < len(tokens) and depth > 0:
                    if tokens[pos].token_type == TK_LP:
                        depth += 1
                    elif tokens[pos].token_type == TK_RP:
                        depth -= 1
                        if depth == 0:
                            pos += 1
                            break
                    sub_tokens.append(tokens[pos].copy())
                    pos += 1
                var sub_ast = parse_sql(sub_tokens)
                if len(sub_ast.select_stmt) > 0:
                    select.from_subquery.append(sub_ast.select_stmt[0].copy())
                if pos < len(tokens) and tokens[pos].token_type == TK_AS:
                    pos += 1
                    if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                        select.table_alias = tokens[pos].text
                        pos += 1
                elif pos < len(tokens) and tokens[pos].token_type == TK_ID and tokens[pos].token_type != TK_WHERE and tokens[pos].token_type != TK_JOIN and tokens[pos].token_type != TK_INNER and tokens[pos].token_type != TK_LEFT and tokens[pos].token_type != TK_CROSS and tokens[pos].token_type != TK_ORDER and tokens[pos].token_type != TK_GROUP and tokens[pos].token_type != TK_LIMIT and tokens[pos].token_type != TK_UNION and tokens[pos].token_type != TK_INTERSECT and tokens[pos].token_type != TK_EXCEPT and tokens[pos].token_type != TK_SEMI:
                    select.table_alias = tokens[pos].text
                    pos += 1
            elif pos < len(tokens) and tokens[pos].token_type == TK_ID:
                select.table_name = tokens[pos].text
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_AS:
                    pos += 1
                    if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                        select.table_alias = tokens[pos].text
                        pos += 1
                elif pos < len(tokens) and tokens[pos].token_type == TK_ID and tokens[pos].token_type != TK_WHERE and tokens[pos].token_type != TK_JOIN and tokens[pos].token_type != TK_INNER and tokens[pos].token_type != TK_LEFT and tokens[pos].token_type != TK_CROSS and tokens[pos].token_type != TK_ORDER and tokens[pos].token_type != TK_GROUP and tokens[pos].token_type != TK_LIMIT and tokens[pos].token_type != TK_UNION and tokens[pos].token_type != TK_INTERSECT and tokens[pos].token_type != TK_EXCEPT and tokens[pos].token_type != TK_SEMI:
                    select.table_alias = tokens[pos].text
                    pos += 1

        # JOIN clauses: [INNER | LEFT [OUTER] | CROSS] JOIN table [AS alias] ON expr
        while pos < len(tokens) and (tokens[pos].token_type == TK_JOIN or tokens[pos].token_type == TK_INNER or tokens[pos].token_type == TK_LEFT or tokens[pos].token_type == TK_CROSS):
            var j_type = JOIN_INNER
            if tokens[pos].token_type == TK_INNER:
                j_type = JOIN_INNER
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_JOIN:
                    pos += 1
            elif tokens[pos].token_type == TK_LEFT:
                j_type = JOIN_LEFT
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_OUTER:
                    pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_JOIN:
                    pos += 1
            elif tokens[pos].token_type == TK_CROSS:
                j_type = JOIN_CROSS
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_JOIN:
                    pos += 1
            elif tokens[pos].token_type == TK_JOIN:
                j_type = JOIN_INNER
                pos += 1

            var j_tbl = String()
            var j_alias = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                j_tbl = tokens[pos].text
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_AS:
                    pos += 1
                    if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                        j_alias = tokens[pos].text
                        pos += 1
                elif pos < len(tokens) and tokens[pos].token_type == TK_ID and tokens[pos].token_type != TK_ON and tokens[pos].token_type != TK_WHERE and tokens[pos].token_type != TK_JOIN and tokens[pos].token_type != TK_INNER and tokens[pos].token_type != TK_LEFT and tokens[pos].token_type != TK_CROSS:
                    j_alias = tokens[pos].text
                    pos += 1

            var join_cl = JoinClause(j_type, j_tbl, j_alias)
            if pos < len(tokens) and tokens[pos].token_type == TK_ON:
                pos += 1
                join_cl.on_expr.append(parse_expr(tokens, pos))
            select.joins.append(join_cl^)

        # WHERE clause
        if pos < len(tokens) and tokens[pos].token_type == TK_WHERE:
            pos += 1
            select.where_expr.append(parse_expr(tokens, pos))

        # GROUP BY
        if pos < len(tokens) and tokens[pos].token_type == TK_GROUP:
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_BY:
                pos += 1
            while pos < len(tokens) and tokens[pos].token_type == TK_ID:
                var col_n = tokens[pos].text
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_DOT:
                    pos += 1
                    if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                        col_n = tokens[pos].text
                        pos += 1
                select.group_by.append(col_n)
                if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                    pos += 1
                else:
                    break

        # HAVING
        if pos < len(tokens) and tokens[pos].token_type == TK_HAVING:
            pos += 1
            select.having_expr.append(parse_expr(tokens, pos))

        # ORDER BY
        if pos < len(tokens) and tokens[pos].token_type == TK_ORDER:
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_BY:
                pos += 1
            while pos < len(tokens) and tokens[pos].token_type != TK_LIMIT and tokens[pos].token_type != TK_UNION and tokens[pos].token_type != TK_INTERSECT and tokens[pos].token_type != TK_EXCEPT and tokens[pos].token_type != TK_SEMI and tokens[pos].token_type != TK_EOF:
                var order_e = parse_expr(tokens, pos)
                if pos < len(tokens) and tokens[pos].token_type == TK_DESC:
                    order_e.is_desc = True
                    pos += 1
                elif pos < len(tokens) and tokens[pos].token_type == TK_ASC:
                    order_e.is_desc = False
                    pos += 1
                select.order_by.append(order_e^)
                if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                    pos += 1
                else:
                    break

        # LIMIT & OFFSET
        if pos < len(tokens) and tokens[pos].token_type == TK_LIMIT:
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_INTEGER:
                select.limit_val = Int(atol(tokens[pos].text))
                pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_OFFSET:
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_INTEGER:
                    select.offset_val = Int(atol(tokens[pos].text))
                    pos += 1

        # Compound operators (UNION, UNION ALL, INTERSECT, EXCEPT)
        if pos < len(tokens) and (tokens[pos].token_type == TK_UNION or tokens[pos].token_type == TK_INTERSECT or tokens[pos].token_type == TK_EXCEPT):
            var c_op = COMPOUND_UNION
            if tokens[pos].token_type == TK_UNION:
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_ALL:
                    c_op = COMPOUND_UNION_ALL
                    pos += 1
                else:
                    c_op = COMPOUND_UNION
            elif tokens[pos].token_type == TK_INTERSECT:
                c_op = COMPOUND_INTERSECT
                pos += 1
            elif tokens[pos].token_type == TK_EXCEPT:
                c_op = COMPOUND_EXCEPT
                pos += 1

            select.compound_op = c_op
            var next_tokens = List[Token]()
            for s in range(pos, len(tokens)):
                next_tokens.append(tokens[s].copy())
            var next_ast = parse_sql(next_tokens)
            if len(next_ast.select_stmt) > 0:
                select.compound_next.append(next_ast.select_stmt[0].copy())

        var res_stmt = ASTStatement(STMT_SELECT)
        res_stmt.select_stmt.append(select^)
        return res_stmt^

    # 2. INSERT
    if first_type == TK_INSERT:
        pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_INTO:
            pos += 1
        var tbl_name = String()
        if pos < len(tokens) and tokens[pos].token_type == TK_ID:
            tbl_name = tokens[pos].text
            pos += 1
        var insert = InsertStmt(tbl_name)

        if pos < len(tokens) and tokens[pos].token_type == TK_LP:
            pos += 1
            while pos < len(tokens) and tokens[pos].token_type == TK_ID:
                insert.columns.append(tokens[pos].text)
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                    pos += 1
                elif pos < len(tokens) and tokens[pos].token_type == TK_RP:
                    pos += 1
                    break

        if pos < len(tokens) and tokens[pos].token_type == TK_VALUES:
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_LP:
                pos += 1
            while pos < len(tokens) and tokens[pos].token_type != TK_RP and tokens[pos].token_type != TK_SEMI and tokens[pos].token_type != TK_EOF:
                insert.values.append(parse_expr(tokens, pos))
                if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                    pos += 1
                else:
                    break
            if pos < len(tokens) and tokens[pos].token_type == TK_RP:
                pos += 1

        elif pos < len(tokens) and tokens[pos].token_type == TK_SELECT:
            var sub_tokens = List[Token]()
            for s in range(pos, len(tokens)):
                sub_tokens.append(tokens[s].copy())
            var sel_sub = parse_sql(sub_tokens)
            if len(sel_sub.select_stmt) > 0:
                insert.select_stmt.append(sel_sub.select_stmt[0].copy())

        var res_stmt = ASTStatement(STMT_INSERT)
        res_stmt.insert_stmt.append(insert^)
        return res_stmt^

    # 3. UPDATE
    if first_type == TK_UPDATE:
        pos += 1
        var tbl_name = String()
        if pos < len(tokens) and tokens[pos].token_type == TK_ID:
            tbl_name = tokens[pos].text
            pos += 1
        var update = UpdateStmt(tbl_name)
        if pos < len(tokens) and tokens[pos].token_type == TK_SET:
            pos += 1
        while pos < len(tokens) and tokens[pos].token_type == TK_ID:
            var col_name = tokens[pos].text
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_EQ:
                pos += 1
            var val_expr = parse_expr(tokens, pos)
            update.assignments.append(UpdateAssignment(col_name, val_expr^))
            if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                pos += 1
            else:
                break

        if pos < len(tokens) and tokens[pos].token_type == TK_WHERE:
            pos += 1
            update.where_expr.append(parse_expr(tokens, pos))

        var res_stmt = ASTStatement(STMT_UPDATE)
        res_stmt.update_stmt.append(update^)
        return res_stmt^

    # 4. DELETE
    if first_type == TK_DELETE:
        pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_FROM:
            pos += 1
        var tbl_name = String()
        if pos < len(tokens) and tokens[pos].token_type == TK_ID:
            tbl_name = tokens[pos].text
            pos += 1
        var del_stmt = DeleteStmt(tbl_name)
        if pos < len(tokens) and tokens[pos].token_type == TK_WHERE:
            pos += 1
            del_stmt.where_expr.append(parse_expr(tokens, pos))

        var res_stmt = ASTStatement(STMT_DELETE)
        res_stmt.delete_stmt.append(del_stmt^)
        return res_stmt^

    # 5. CREATE
    if first_type == TK_CREATE:
        pos += 1
        var is_unique_idx = False
        if pos < len(tokens) and tokens[pos].token_type == TK_UNIQUE:
            is_unique_idx = True
            pos += 1

        if pos < len(tokens) and tokens[pos].token_type == TK_TABLE:
            pos += 1
            var tbl_name = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                tbl_name = tokens[pos].text
                pos += 1
            var create_tbl = CreateTableStmt(tbl_name)

            if pos < len(tokens) and tokens[pos].token_type == TK_LP:
                pos += 1
                while pos < len(tokens) and tokens[pos].token_type != TK_RP and tokens[pos].token_type != TK_SEMI and tokens[pos].token_type != TK_EOF:
                    if tokens[pos].token_type == TK_ID or tokens[pos].token_type == TK_PRIMARY:
                        var col_name = tokens[pos].text
                        pos += 1
                        var col_type = SQLITE_TEXT
                        var is_pk = False
                        var not_null = False
                        var has_def = False
                        var def_val = Value.of_null()

                        while pos < len(tokens) and tokens[pos].token_type != TK_COMMA and tokens[pos].token_type != TK_RP:
                            var t_text = tokens[pos].text
                            if nocase_compare(t_text, "INTEGER") == 0 or nocase_compare(t_text, "INT") == 0:
                                col_type = SQLITE_INTEGER
                            elif nocase_compare(t_text, "REAL") == 0 or nocase_compare(t_text, "FLOAT") == 0:
                                col_type = SQLITE_FLOAT
                            elif nocase_compare(t_text, "TEXT") == 0 or nocase_compare(t_text, "VARCHAR") == 0:
                                col_type = SQLITE_TEXT
                            elif nocase_compare(t_text, "BLOB") == 0:
                                col_type = SQLITE_BLOB
                            elif tokens[pos].token_type == TK_PRIMARY:
                                is_pk = True
                            elif tokens[pos].token_type == TK_NOT:
                                if pos + 1 < len(tokens) and tokens[pos + 1].token_type == TK_NULL:
                                    not_null = True
                                    pos += 1
                            elif tokens[pos].token_type == TK_DEFAULT:
                                pos += 1
                                has_def = True
                                if pos < len(tokens):
                                    if tokens[pos].token_type == TK_STRING:
                                        def_val = Value.of_text(tokens[pos].text)
                                    elif tokens[pos].token_type == TK_INTEGER:
                                        def_val = Value.of_int(Int64(atol(tokens[pos].text)))
                                    elif tokens[pos].token_type == TK_FLOAT:
                                        def_val = Value.of_float(Float64(atof(tokens[pos].text)))
                            pos += 1

                        create_tbl.columns.append(ColumnDef(col_name, col_type, is_pk, has_def, def_val, not_null))

                    if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                        pos += 1
                    else:
                        break

            var res_stmt = ASTStatement(STMT_CREATE_TABLE)
            res_stmt.create_table_stmt.append(create_tbl^)
            return res_stmt^

        elif pos < len(tokens) and tokens[pos].token_type == TK_INDEX:
            pos += 1
            var idx_name = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                idx_name = tokens[pos].text
                pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_FROM:
                pos += 1
            elif pos < len(tokens) and tokens[pos].text == "ON":
                pos += 1
            var tbl_name = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                tbl_name = tokens[pos].text
                pos += 1
            var create_idx = CreateIndexStmt(idx_name, tbl_name, is_unique_idx)
            if pos < len(tokens) and tokens[pos].token_type == TK_LP:
                pos += 1
                while pos < len(tokens) and tokens[pos].token_type == TK_ID:
                    create_idx.columns.append(tokens[pos].text)
                    pos += 1
                    if pos < len(tokens) and tokens[pos].token_type == TK_COMMA:
                        pos += 1
                    else:
                        break

            var res_stmt = ASTStatement(STMT_CREATE_INDEX)
            res_stmt.create_index_stmt.append(create_idx^)
            return res_stmt^

        elif pos < len(tokens) and tokens[pos].token_type == TK_VIEW:
            pos += 1
            var v_name = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                v_name = tokens[pos].text
                pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_AS:
                pos += 1
            var view_tokens = List[Token]()
            for s in range(pos, len(tokens)):
                view_tokens.append(tokens[s].copy())
            var sub_ast = parse_sql(view_tokens)
            var res_stmt = ASTStatement(STMT_CREATE_VIEW)
            var cv = CreateViewStmt(v_name)
            if len(sub_ast.select_stmt) > 0:
                cv.select_stmt.append(sub_ast.select_stmt[0].copy())
            res_stmt.create_view_stmt.append(cv^)
            return res_stmt^

        elif pos < len(tokens) and tokens[pos].token_type == TK_TRIGGER:
            pos += 1
            var trg_name = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                trg_name = tokens[pos].text
                pos += 1
            var timing = TRIGGER_AFTER
            if pos < len(tokens) and tokens[pos].token_type == TK_BEFORE:
                timing = TRIGGER_BEFORE
                pos += 1
            elif pos < len(tokens) and tokens[pos].token_type == TK_AFTER:
                timing = TRIGGER_AFTER
                pos += 1
            var ev_type = TRIGGER_EVENT_INSERT
            if pos < len(tokens) and tokens[pos].token_type == TK_INSERT:
                ev_type = TRIGGER_EVENT_INSERT
                pos += 1
            elif pos < len(tokens) and tokens[pos].token_type == TK_UPDATE:
                ev_type = TRIGGER_EVENT_UPDATE
                pos += 1
            elif pos < len(tokens) and tokens[pos].token_type == TK_DELETE:
                ev_type = TRIGGER_EVENT_DELETE
                pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_ON:
                pos += 1
            var target_tbl = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                target_tbl = tokens[pos].text
                pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_FOR:
                pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_EACH:
                    pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_ROW:
                    pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_BEGIN:
                pos += 1
            var action_str = String()
            while pos < len(tokens) and tokens[pos].token_type != TK_END and tokens[pos].token_type != TK_EOF:
                var t_text = tokens[pos].text
                if tokens[pos].token_type == TK_STRING:
                    t_text = "'" + t_text + "'"
                if action_str != "" and t_text != "." and t_text != "," and t_text != ";" and t_text != ")" and not (len(action_str.as_bytes()) > 0 and action_str.as_bytes()[len(action_str.as_bytes()) - 1] == 46):
                    action_str += " "
                action_str += t_text
                pos += 1
            var res_stmt = ASTStatement(STMT_CREATE_TRIGGER)
            res_stmt.create_trigger_stmt.append(CreateTriggerStmt(trg_name, timing, ev_type, target_tbl, action_str))
            return res_stmt^

    # 6. DROP
    if first_type == TK_DROP:
        pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_INDEX:
            pos += 1
            var idx_name = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                idx_name = tokens[pos].text
            var res_stmt = ASTStatement(STMT_DROP_INDEX)
            res_stmt.drop_index_stmt.append(DropIndexStmt(idx_name))
            return res_stmt^
        elif pos < len(tokens) and tokens[pos].token_type == TK_VIEW:
            pos += 1
            var v_name = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                v_name = tokens[pos].text
            var res_stmt = ASTStatement(STMT_DROP_VIEW)
            res_stmt.drop_view_stmt.append(DropViewStmt(v_name))
            return res_stmt^
        elif pos < len(tokens) and tokens[pos].token_type == TK_TRIGGER:
            pos += 1
            var t_name = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                t_name = tokens[pos].text
            var res_stmt = ASTStatement(STMT_DROP_TRIGGER)
            res_stmt.drop_trigger_stmt.append(DropTriggerStmt(t_name))
            return res_stmt^

    # 7. Transactions
    if first_type == TK_BEGIN:
        var res_stmt = ASTStatement(STMT_TRANS)
        res_stmt.trans_stmt.append(TransStmt(TK_BEGIN))
        return res_stmt^
    elif first_type == TK_COMMIT:
        var res_stmt = ASTStatement(STMT_TRANS)
        res_stmt.trans_stmt.append(TransStmt(TK_COMMIT))
        return res_stmt^
    elif first_type == TK_ROLLBACK:
        pos += 1
        var name = String()
        if pos < len(tokens) and tokens[pos].token_type == TK_TO:
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_SAVEPOINT:
                pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                name = tokens[pos].text
        var res_stmt = ASTStatement(STMT_TRANS)
        res_stmt.trans_stmt.append(TransStmt(TK_ROLLBACK, name))
        return res_stmt^
    elif first_type == TK_SAVEPOINT:
        pos += 1
        var name = String()
        if pos < len(tokens) and tokens[pos].token_type == TK_ID:
            name = tokens[pos].text
        var res_stmt = ASTStatement(STMT_TRANS)
        res_stmt.trans_stmt.append(TransStmt(TK_SAVEPOINT, name))
        return res_stmt^
    elif first_type == TK_RELEASE:
        pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_SAVEPOINT:
            pos += 1
        var name = String()
        if pos < len(tokens) and tokens[pos].token_type == TK_ID:
            name = tokens[pos].text
        var res_stmt = ASTStatement(STMT_TRANS)
        res_stmt.trans_stmt.append(TransStmt(TK_RELEASE, name))
        return res_stmt^

    # 8. PRAGMA
    if first_type == TK_PRAGMA:
        pos += 1
        var p_name = String()
        if pos < len(tokens) and tokens[pos].token_type == TK_ID:
            p_name = tokens[pos].text
            pos += 1
        var p_arg = String()
        if pos < len(tokens) and tokens[pos].token_type == TK_LP:
            pos += 1
            if pos < len(tokens) and (tokens[pos].token_type == TK_ID or tokens[pos].token_type == TK_STRING):
                p_arg = tokens[pos].text
                pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_RP:
                pos += 1
        var p_val = String()
        var has_val = False
        if pos < len(tokens) and tokens[pos].token_type == TK_EQ:
            pos += 1
            if pos < len(tokens):
                p_val = tokens[pos].text
                has_val = True
                pos += 1
        var res_stmt = ASTStatement(STMT_PRAGMA)
        res_stmt.pragma_stmt.append(PragmaStmt(p_name, p_arg, p_val, has_val))
        return res_stmt^

    # 9. ALTER TABLE
    if first_type == TK_ALTER:
        pos += 1
        if pos < len(tokens) and tokens[pos].token_type == TK_TABLE:
            pos += 1
        var tbl_name = String()
        if pos < len(tokens) and tokens[pos].token_type == TK_ID:
            tbl_name = tokens[pos].text
            pos += 1

        if pos < len(tokens) and tokens[pos].token_type == TK_RENAME:
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_TO:
                pos += 1
                var new_tbl = String()
                if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                    new_tbl = tokens[pos].text
                var res_stmt = ASTStatement(STMT_ALTER_TABLE)
                res_stmt.alter_table_stmt.append(AlterTableStmt(ALTER_RENAME_TABLE, tbl_name, new_tbl))
                return res_stmt^
            elif pos < len(tokens) and (tokens[pos].token_type == TK_COLUMN or tokens[pos].token_type == TK_ID):
                if tokens[pos].token_type == TK_COLUMN:
                    pos += 1
                var old_col = String()
                if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                    old_col = tokens[pos].text
                    pos += 1
                if pos < len(tokens) and tokens[pos].token_type == TK_TO:
                    pos += 1
                var new_col = String()
                if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                    new_col = tokens[pos].text
                var res_stmt = ASTStatement(STMT_ALTER_TABLE)
                var alt = AlterTableStmt(ALTER_RENAME_COLUMN, tbl_name, old_col + ":" + new_col)
                res_stmt.alter_table_stmt.append(alt^)
                return res_stmt^

        elif pos < len(tokens) and tokens[pos].token_type == TK_ADD:
            pos += 1
            if pos < len(tokens) and tokens[pos].token_type == TK_COLUMN:
                pos += 1
            var col_name = String()
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                col_name = tokens[pos].text
                pos += 1
            var col_type = SQLITE_TEXT
            if pos < len(tokens) and tokens[pos].token_type == TK_ID:
                var tname = tokens[pos].text
                if nocase_compare(tname, "INT") == 0 or nocase_compare(tname, "INTEGER") == 0:
                    col_type = SQLITE_INTEGER
                elif nocase_compare(tname, "REAL") == 0 or nocase_compare(tname, "FLOAT") == 0:
                    col_type = SQLITE_FLOAT
                elif nocase_compare(tname, "BLOB") == 0:
                    col_type = SQLITE_BLOB
                pos += 1
            var is_pk = False
            var has_def = False
            var def_val = Value.of_null()
            while pos < len(tokens) and tokens[pos].token_type != TK_SEMI and tokens[pos].token_type != TK_EOF:
                if tokens[pos].token_type == TK_DEFAULT:
                    pos += 1
                    has_def = True
                    if pos < len(tokens):
                        if tokens[pos].token_type == TK_STRING:
                            def_val = Value.of_text(tokens[pos].text)
                        elif tokens[pos].token_type == TK_INTEGER:
                            def_val = Value.of_int(Int64(atol(tokens[pos].text)))
                        elif tokens[pos].token_type == TK_FLOAT:
                            def_val = Value.of_float(Float64(atof(tokens[pos].text)))
                pos += 1
            var res_stmt = ASTStatement(STMT_ALTER_TABLE)
            var alt = AlterTableStmt(ALTER_ADD_COLUMN, tbl_name)
            alt.column_def.append(ColumnDef(col_name, col_type, is_pk, has_def, def_val))
            res_stmt.alter_table_stmt.append(alt^)
            return res_stmt^

    var res_stmt = ASTStatement(STMT_SELECT)
    res_stmt.select_stmt.append(SelectStmt())
    return res_stmt^


# Backward compatibility helper for Stage 6/7 tests
def parse_select(tokens: List[Token]) raises -> SelectStmt:
    var parsed = parse_sql(tokens)
    if len(parsed.select_stmt) > 0:
        return parsed.select_stmt[0].copy()
    return SelectStmt()
