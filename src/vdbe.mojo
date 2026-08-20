""" SQLite VDBE (Virtual Database Engine) Virtual Machine and Interpreter.

Corresponds to `sqlite/src/vdbe.c`, `sqlite/src/vdbeaux.c`, and `sqlite/src/vdbemem.c`.

Implements:
- Registers (Mem cells holding Value types)
- Cursor slots holding active `BTreeCursor` instances
- Bytecode program counter and opcode evaluation loop (`step() -> Int`)
- `ResultRow` buffering for high-level query iterations
- Scalar function evaluation and casting support
"""

from src.types import *
from src.row import Value, Row
from src.opcode import *
from src.record import encode_record, decode_record
from src.btree import MemBTree, BTreeCursor
from src.functions import evaluate_scalar_func, sql_cast

# VDBE Step Results
comptime VDBE_RESULT_ROW = 100
comptime VDBE_RESULT_DONE = 101
comptime VDBE_RESULT_ERROR = 1


struct Vdbe(ImplicitlyCopyable, Copyable, Movable):
    """ SQLite Virtual Database Engine Bytecode Interpreter."""
    var _program: List[Opcode]
    var _pc: Int
    var _mem: List[Value]
    var _btrees: List[MemBTree]
    var _cursors: List[BTreeCursor]
    var _result_row: List[Value]
    var _halted: Bool
    var changes_count: Int
    var last_rowid: Int64

    def __init__(out self, num_mem: Int = 64):
        self._program = List[Opcode]()
        self._pc = 0
        self._mem = List[Value]()
        for _ in range(num_mem):
            self._mem.append(Value.of_null())
        self._btrees = List[MemBTree]()
        self._cursors = List[BTreeCursor]()
        self._result_row = List[Value]()
        self._halted = False
        self.changes_count = 0
        self.last_rowid = 0

    def __init__(out self, *, copy: Self):
        self._program = copy._program.copy()
        self._pc = copy._pc
        self._mem = copy._mem.copy()
        self._btrees = copy._btrees.copy()
        self._cursors = copy._cursors.copy()
        self._result_row = copy._result_row.copy()
        self._halted = copy._halted
        self.changes_count = copy.changes_count
        self.last_rowid = copy.last_rowid

    def __init__(out self, *, deinit move: Self):
        self._program = move._program^
        self._pc = move._pc
        self._mem = move._mem^
        self._btrees = move._btrees^
        self._cursors = move._cursors^
        self._result_row = move._result_row^
        self._halted = move._halted
        self.changes_count = move.changes_count
        self.last_rowid = move.last_rowid

    def add_opcode(mut self, op: Opcode):
        """ Appends an opcode instruction to the program."""
        self._program.append(op)

    def attach_btree(mut self, btree: MemBTree) -> Int:
        """ Attaches a table B-Tree and returns its table index."""
        var idx = len(self._btrees)
        self._btrees.append(btree.copy())
        self._cursors.append(BTreeCursor(btree))
        return idx

    def get_attached_btree(self, idx: Int) -> MemBTree:
        """ Returns the state of the attached B-Tree."""
        return self._btrees[idx].copy()

    def get_mem(self, reg: Int) -> Value:
        """ Reads value from register `reg`."""
        if reg >= 0 and reg < len(self._mem):
            return self._mem[reg].copy()
        return Value.of_null()

    def set_mem(mut self, reg: Int, val: Value):
        """ Stores `val` into register `reg`."""
        while len(self._mem) <= reg:
            self._mem.append(Value.of_null())
        self._mem[reg] = val.copy()

    def current_result_row(self) -> List[Value]:
        """ Returns the columns buffered by the most recent OP_RESULT_ROW."""
        return self._result_row.copy()

    def step(mut self) raises -> Int:
        """ Executes bytecode until OP_RESULT_ROW or OP_HALT is encountered."""
        if self._halted:
            return VDBE_RESULT_DONE

        var n_ops = len(self._program)
        while self._pc < n_ops:
            var inst = self._program[self._pc]
            var op = inst.op
            var p1 = inst.p1
            var p2 = inst.p2
            var p3 = inst.p3
            var p4 = inst.p4_str

            if op == OP_INIT:
                self._pc = p2
                continue

            elif op == OP_GOTO:
                self._pc = p2
                continue

            elif op == OP_HALT:
                self._halted = True
                return VDBE_RESULT_DONE

            elif op == OP_INTEGER:
                self.set_mem(p2, Value.of_int(Int64(p1)))

            elif op == OP_REAL:
                var fval = Float64(atof(p4))
                self.set_mem(p2, Value.of_float(fval))

            elif op == OP_STRING8:
                self.set_mem(p2, Value.of_text(p4))

            elif op == OP_NULL:
                self.set_mem(p2, Value.of_null())

            elif op == OP_COPY:
                var src_val = self.get_mem(p1)
                self.set_mem(p2, src_val)

            elif op == OP_ADD:
                var v1 = self.get_mem(p1)
                var v2 = self.get_mem(p2)
                if v1.is_null() or v2.is_null():
                    self.set_mem(p3, Value.of_null())
                elif v1.type_tag == SQLITE_FLOAT or v2.type_tag == SQLITE_FLOAT:
                    self.set_mem(p3, Value.of_float(v1.to_float() + v2.to_float()))
                else:
                    self.set_mem(p3, Value.of_int(v1.to_int() + v2.to_int()))

            elif op == OP_SUBTRACT:
                var v1 = self.get_mem(p1)
                var v2 = self.get_mem(p2)
                if v1.is_null() or v2.is_null():
                    self.set_mem(p3, Value.of_null())
                elif v1.type_tag == SQLITE_FLOAT or v2.type_tag == SQLITE_FLOAT:
                    self.set_mem(p3, Value.of_float(v1.to_float() - v2.to_float()))
                else:
                    self.set_mem(p3, Value.of_int(v1.to_int() - v2.to_int()))

            elif op == OP_MULTIPLY:
                var v1 = self.get_mem(p1)
                var v2 = self.get_mem(p2)
                if v1.is_null() or v2.is_null():
                    self.set_mem(p3, Value.of_null())
                elif v1.type_tag == SQLITE_FLOAT or v2.type_tag == SQLITE_FLOAT:
                    self.set_mem(p3, Value.of_float(v1.to_float() * v2.to_float()))
                else:
                    self.set_mem(p3, Value.of_int(v1.to_int() * v2.to_int()))

            elif op == OP_DIVIDE:
                var v1 = self.get_mem(p1)
                var v2 = self.get_mem(p2)
                if v1.is_null() or v2.is_null():
                    self.set_mem(p3, Value.of_null())
                elif v1.type_tag == SQLITE_FLOAT or v2.type_tag == SQLITE_FLOAT:
                    var denom = v2.to_float()
                    if denom == 0.0:
                        self.set_mem(p3, Value.of_null())
                    else:
                        self.set_mem(p3, Value.of_float(v1.to_float() / denom))
                else:
                    var denom = v2.to_int()
                    if denom == 0:
                        self.set_mem(p3, Value.of_null())
                    else:
                        self.set_mem(p3, Value.of_int(v1.to_int() // denom))

            elif op == OP_REMAINDER:
                var v1 = self.get_mem(p1)
                var v2 = self.get_mem(p2)
                if v1.is_null() or v2.is_null() or v2.to_int() == 0:
                    self.set_mem(p3, Value.of_null())
                else:
                    self.set_mem(p3, Value.of_int(v1.to_int() % v2.to_int()))

            elif op == OP_CONCAT:
                var v1 = self.get_mem(p1)
                var v2 = self.get_mem(p2)
                if v1.is_null() or v2.is_null():
                    self.set_mem(p3, Value.of_null())
                else:
                    self.set_mem(p3, Value.of_text(v1.to_string() + v2.to_string()))

            elif op == OP_EQ:
                var v1 = self.get_mem(p1)
                var v3 = self.get_mem(p3)
                if not v1.is_null() and not v3.is_null() and v1.to_string() == v3.to_string():
                    self._pc = p2
                    continue

            elif op == OP_NE:
                var v1 = self.get_mem(p1)
                var v3 = self.get_mem(p3)
                if not v1.is_null() and not v3.is_null() and v1.to_string() != v3.to_string():
                    self._pc = p2
                    continue

            elif op == OP_LT:
                var v1 = self.get_mem(p1)
                var v3 = self.get_mem(p3)
                if not v1.is_null() and not v3.is_null() and v1.to_float() < v3.to_float():
                    self._pc = p2
                    continue

            elif op == OP_LE:
                var v1 = self.get_mem(p1)
                var v3 = self.get_mem(p3)
                if not v1.is_null() and not v3.is_null() and v1.to_float() <= v3.to_float():
                    self._pc = p2
                    continue

            elif op == OP_GT:
                var v1 = self.get_mem(p1)
                var v3 = self.get_mem(p3)
                if not v1.is_null() and not v3.is_null() and v1.to_float() > v3.to_float():
                    self._pc = p2
                    continue

            elif op == OP_GE:
                var v1 = self.get_mem(p1)
                var v3 = self.get_mem(p3)
                if not v1.is_null() and not v3.is_null() and v1.to_float() >= v3.to_float():
                    self._pc = p2
                    continue

            elif op == OP_IS_NULL:
                var v1 = self.get_mem(p1)
                if v1.is_null():
                    self._pc = p2
                    continue

            elif op == OP_NOT_NULL:
                var v1 = self.get_mem(p1)
                if not v1.is_null():
                    self._pc = p2
                    continue

            elif op == OP_IF_ZERO:
                var v1 = self.get_mem(p1)
                if v1.to_int() == 0:
                    self._pc = p2
                    continue

            elif op == OP_IF_NOT_ZERO:
                var v1 = self.get_mem(p1)
                if v1.to_int() != 0:
                    self._pc = p2
                    continue

            elif op == OP_OPEN_READ or op == OP_OPEN_WRITE:
                var cur_idx = p1
                var btree_idx = p2
                if btree_idx >= 0 and btree_idx < len(self._btrees):
                    while len(self._cursors) <= cur_idx:
                        self._cursors.append(BTreeCursor(self._btrees[btree_idx]))
                    self._cursors[cur_idx] = BTreeCursor(self._btrees[btree_idx])

            elif op == OP_REWIND:
                var cur_idx = p1
                if cur_idx < len(self._cursors):
                    var has_row = self._cursors[cur_idx].first()
                    if not has_row:
                        self._pc = p2
                        continue

            elif op == OP_NEXT:
                var cur_idx = p1
                if cur_idx < len(self._cursors):
                    var has_next = self._cursors[cur_idx].next()
                    if has_next:
                        self._pc = p2
                        continue

            elif op == OP_SEEK_ROWID:
                var cur_idx = p1
                var not_found_jump = p2
                var target_reg = p3
                var target_rowid = self.get_mem(target_reg).to_int()
                if cur_idx < len(self._cursors):
                    var found = self._cursors[cur_idx].seek_rowid(target_rowid)
                    if not found:
                        self._pc = not_found_jump
                        continue

            elif op == OP_ROWID:
                var cur_idx = p1
                var out_reg = p2
                if cur_idx < len(self._cursors) and self._cursors[cur_idx].is_valid():
                    var rid = self._cursors[cur_idx].get_rowid()
                    self.set_mem(out_reg, Value.of_int(rid))

            elif op == OP_COLUMN:
                var cur_idx = p1
                var col_idx = p2
                var out_reg = p3
                if cur_idx < len(self._cursors) and self._cursors[cur_idx].is_valid():
                    var rec = self._cursors[cur_idx].get_record()
                    if col_idx >= 0 and col_idx < len(rec):
                        self.set_mem(out_reg, rec[col_idx])
                    else:
                        self.set_mem(out_reg, Value.of_null())

            elif op == OP_MAKE_RECORD:
                var start_reg = p1
                var count = p2
                var out_reg = p3
                var record_vals = List[Value]()
                for i in range(count):
                    record_vals.append(self.get_mem(start_reg + i))
                var payload = encode_record(record_vals)
                var pl_str = String()
                for i in range(len(payload)):
                    pl_str += chr(Int(payload[i]))
                self.set_mem(out_reg, Value.of_text(pl_str))

            elif op == OP_INSERT:
                var cur_idx = p1
                var payload_reg = p2
                var rowid_reg = p3
                var rid = self.get_mem(rowid_reg).to_int()
                var pl_val = self.get_mem(payload_reg)
                var bytes = pl_val.text_val.as_bytes()
                var payload = List[UInt8]()
                for i in range(len(bytes)):
                    payload.append(bytes[i])
                if cur_idx < len(self._btrees):
                    self._btrees[cur_idx].insert(rid, payload)
                    self._cursors[cur_idx] = BTreeCursor(self._btrees[cur_idx])
                    self.changes_count += 1
                    self.last_rowid = rid

            elif op == OP_DELETE:
                var cur_idx = p1
                var rowid_reg = p2
                var rid = self.get_mem(rowid_reg).to_int()
                if cur_idx < len(self._btrees):
                    var deleted = self._btrees[cur_idx].delete(rid)
                    if deleted:
                        self._cursors[cur_idx] = BTreeCursor(self._btrees[cur_idx])
                        self.changes_count += 1

            elif op == OP_FUNCTION:
                var start_reg = p1
                var arg_count = p2
                var out_reg = p3
                var fn_name = p4
                var fn_args = List[Value]()
                for i in range(arg_count):
                    fn_args.append(self.get_mem(start_reg + i))
                var fn_res = evaluate_scalar_func(fn_name, fn_args)
                self.set_mem(out_reg, fn_res)

            elif op == OP_CAST:
                var src_val = self.get_mem(p1)
                var target_type = p4
                var casted_val = sql_cast(src_val, target_type)
                self.set_mem(p3, casted_val)

            elif op == OP_SET_CHANGES:
                self.changes_count = p1

            elif op == OP_SET_LAST_ROWID:
                self.last_rowid = Int64(p1)

            elif op == OP_RESULT_ROW:
                var start_reg = p1
                var count = p2
                self._result_row = List[Value]()
                for i in range(count):
                    self._result_row.append(self.get_mem(start_reg + i))
                self._pc += 1
                return VDBE_RESULT_ROW

            self._pc += 1

        self._halted = True
        return VDBE_RESULT_DONE
