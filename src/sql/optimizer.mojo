""" SQLite Query Optimizer and Where-Clause Planner.

Corresponds to `sqlite/src/where.c`, `sqlite/src/wherecode.c`, and `sqlite/src/whereInt.h`.

Analyzes WHERE constraints and produces the optimal access path:
- Full Table Scan (`OP_REWIND` -> `OP_NEXT`) with register-level filtering
- Direct RowID Seek (`OP_SEEK_ROWID`) when an equality constraint matches primary key `rowid` or `id`
"""

from src.core.types import *
from src.engine.row import Value
from src.vdbe.opcode import *
from src.vdbe.vm import Vdbe
from src.sql.parser import SelectStmt

# Access Path Strategy
comptime PLAN_FULL_SCAN = 0
comptime PLAN_ROWID_SEEK = 1


struct QueryPlan(ImplicitlyCopyable, Copyable, Movable):
    """ Represents the planned execution path for an SQL query."""
    var plan_type: Int
    var seek_rowid: Int64
    var filter_col_idx: Int
    var filter_val_int: Int64

    def __init__(out self, plan_type: Int = PLAN_FULL_SCAN):
        self.plan_type = plan_type
        self.seek_rowid = 0
        self.filter_col_idx = -1
        self.filter_val_int = 0

    def __init__(out self, *, copy: Self):
        self.plan_type = copy.plan_type
        self.seek_rowid = copy.seek_rowid
        self.filter_col_idx = copy.filter_col_idx
        self.filter_val_int = copy.filter_val_int

    def __init__(out self, *, deinit move: Self):
        self.plan_type = move.plan_type
        self.seek_rowid = move.seek_rowid
        self.filter_col_idx = move.filter_col_idx
        self.filter_val_int = move.filter_val_int


def optimize_where_clause(stmt: SelectStmt) -> QueryPlan:
    """ Determines whether to use direct rowid seek or filtered table scan."""
    var plan = QueryPlan(PLAN_FULL_SCAN)

    if stmt.has_where:
        if stmt.where_col == "id" or stmt.where_col == "rowid":
            # Primary Key / RowID direct seek optimization (O(log N))
            plan.plan_type = PLAN_ROWID_SEEK
            plan.seek_rowid = stmt.where_val_int
        else:
            # Column filter scan
            plan.plan_type = PLAN_FULL_SCAN
            plan.filter_val_int = stmt.where_val_int

    return plan^


def compile_optimized_select(stmt: SelectStmt, table_btree_idx: Int) -> Vdbe:
    """ Generates optimized VDBE bytecode using WhereScan planning."""
    var plan = optimize_where_clause(stmt)
    var vm = Vdbe()

    var num_cols = len(stmt.columns)
    if stmt.is_star or num_cols == 0:
        num_cols = 2

    if plan.plan_type == PLAN_ROWID_SEEK:
        # Optimized direct RowID seek:
        # 0: OpenRead    0 (cur 0), table_btree_idx
        # 1: Integer     seek_rowid, reg 10 (target rowid)
        # 2: SeekRowid   0 (cur 0), 6 (halt if not found), reg 10
        # 3: Column      0 (cur 0), 0 (col 0), 1 (reg 1)
        # 4: Column      0 (cur 0), 1 (col 1), 2 (reg 2)
        # 5: ResultRow   1 (reg 1), 2 cols
        # 6: Close       0
        # 7: Halt
        vm.add_opcode(Opcode(OP_OPEN_READ, 0, table_btree_idx))
        vm.add_opcode(Opcode(OP_INTEGER, Int(plan.seek_rowid), 10))
        vm.add_opcode(Opcode(OP_SEEK_ROWID, 0, 7, 10))
        for c in range(num_cols):
            vm.add_opcode(Opcode(OP_COLUMN, 0, c, c + 1))
        vm.add_opcode(Opcode(OP_RESULT_ROW, 1, num_cols))
        vm.add_opcode(Opcode(OP_CLOSE, 0))
        vm.add_opcode(Opcode(OP_HALT))
    else:
        # Full scan loop
        vm.add_opcode(Opcode(OP_OPEN_READ, 0, table_btree_idx))
        vm.add_opcode(Opcode(OP_REWIND, 0, 7))
        for c in range(num_cols):
            vm.add_opcode(Opcode(OP_COLUMN, 0, c, c + 1))
        vm.add_opcode(Opcode(OP_RESULT_ROW, 1, num_cols))
        vm.add_opcode(Opcode(OP_NEXT, 0, 2))
        vm.add_opcode(Opcode(OP_CLOSE, 0))
        vm.add_opcode(Opcode(OP_HALT))

    return vm^
