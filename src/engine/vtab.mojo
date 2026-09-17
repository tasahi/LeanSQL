""" SQLite Virtual Table Interface and Module Registry.

Implements the SQLite3 Virtual Table architecture in pure Mojo:
- VirtualTableModule (xCreate, xConnect, xDestroy, xOpen, xClose, xFilter, xNext, xEof, xColumn, xRowid, xUpdate)
- VirtualTable and VirtualTableCursor abstractions
- Dynamic module registration and lifecycle dispatch
- Dynamic Library loader (std.ffi dlopen/dlsym wrapper)
"""

from std.ffi import external_call, c_char
from std.memory import Pointer
from src.core.types import *
from src.engine.row import Value, Row
from src.core.utf import nocase_compare


struct DynamicLibrary(ImplicitlyCopyable, Copyable, Movable):
    """ Safe abstraction for dynamic library loading using platform dlopen/dlsym."""
    var handle_addr: Int
    var path: String

    def __init__(out self, path: String, flags: Int32 = 2) raises: # RTLD_NOW = 2
        self.path = path
        var path_bytes = path.as_bytes()
        var path_ptr = path_bytes.unsafe_ptr()
        var h = external_call["dlopen", Pointer[NoneType, MutAnyOrigin]](path_ptr, flags)
        self.handle_addr = Int(h)
        if self.handle_addr == 0:
            var err_ptr = external_call["dlerror", Pointer[c_char, ImmutAnyOrigin]]()
            var err_msg = "Failed to load dynamic library: " + path
            if Int(err_ptr) != 0:
                var s = String(err_ptr)
                err_msg += " (" + s + ")"
            raise Error(err_msg)

    def __init__(out self, *, copy: Self):
        self.handle_addr = copy.handle_addr
        self.path = copy.path

    def __init__(out self, *, deinit move: Self):
        self.handle_addr = move.handle_addr
        self.path = move.path^

    def get_symbol_addr(self, symbol_name: String) raises -> Int:
        var sym_bytes = symbol_name.as_bytes()
        var sym_ptr = sym_bytes.unsafe_ptr()
        var h = Pointer[NoneType, MutAnyOrigin](unsafe_from_address=self.handle_addr)
        var s = external_call["dlsym", Pointer[NoneType, MutAnyOrigin]](h, sym_ptr)
        var addr = Int(s)
        if addr == 0:
            raise Error("Symbol not found: " + symbol_name)
        return addr

    def close(mut self):
        if self.handle_addr != 0:
            var h = Pointer[NoneType, MutAnyOrigin](unsafe_from_address=self.handle_addr)
            _ = external_call["dlclose", Int32](h)
            self.handle_addr = 0


struct IndexConstraint(ImplicitlyCopyable, Copyable, Movable):
    var column: Int
    var op: String
    var usable: Bool

    def __init__(out self, column: Int, op: String, usable: Bool = True):
        self.column = column
        self.op = op
        self.usable = usable

    def __init__(out self, *, copy: Self):
        self.column = copy.column
        self.op = copy.op
        self.usable = copy.usable

    def __init__(out self, *, deinit move: Self):
        self.column = move.column
        self.op = move.op^
        self.usable = move.usable


struct VirtualTable(ImplicitlyCopyable, Copyable, Movable):
    var table_name: String
    var module_name: String
    var schema_sql: String
    var column_names: List[String]
    var rows: List[Row]

    def __init__(out self, table_name: String = "", module_name: String = "", schema_sql: String = ""):
        self.table_name = table_name
        self.module_name = module_name
        self.schema_sql = schema_sql
        self.column_names = List[String]()
        self.rows = List[Row]()

    def __init__(out self, *, copy: Self):
        self.table_name = copy.table_name
        self.module_name = copy.module_name
        self.schema_sql = copy.schema_sql
        self.column_names = copy.column_names.copy()
        self.rows = copy.rows.copy()

    def __init__(out self, *, deinit move: Self):
        self.table_name = move.table_name^
        self.module_name = move.module_name^
        self.schema_sql = move.schema_sql^
        self.column_names = move.column_names^
        self.rows = move.rows^


struct VirtualTableCursor(ImplicitlyCopyable, Copyable, Movable):
    var row_idx: Int
    var filtered_rows: List[Row]

    def __init__(out self):
        self.row_idx = 0
        self.filtered_rows = List[Row]()

    def __init__(out self, *, copy: Self):
        self.row_idx = copy.row_idx
        self.filtered_rows = copy.filtered_rows.copy()

    def __init__(out self, *, deinit move: Self):
        self.row_idx = move.row_idx
        self.filtered_rows = move.filtered_rows^

    def filter(mut self, rows: List[Row], constraints: List[IndexConstraint], args: List[Value]):
        self.filtered_rows = List[Row]()
        for r_idx in range(len(rows)):
            var r = rows[r_idx]
            var matches = True
            for c_idx in range(len(constraints)):
                var cons = constraints[c_idx]
                if cons.column >= 0 and cons.column < len(r) and c_idx < len(args):
                    var arg_v = args[c_idx]
                    var row_v = r[cons.column]
                    if cons.op == "=":
                        if nocase_compare(row_v.to_string(), arg_v.to_string()) != 0:
                            matches = False
                            break
                    elif cons.op == "MATCH":
                        # MATCH operator for virtual table search
                        if nocase_compare(row_v.to_string(), arg_v.to_string()) != 0:
                            matches = False
                            break
            if matches:
                self.filtered_rows.append(r.copy())
        self.row_idx = 0

    def next(mut self):
        self.row_idx += 1

    def eof(self) -> Bool:
        return self.row_idx >= len(self.filtered_rows)

    def column(self, col_idx: Int) -> Value:
        if self.row_idx >= 0 and self.row_idx < len(self.filtered_rows):
            var r = self.filtered_rows[self.row_idx]
            if col_idx >= 0 and col_idx < len(r):
                return r[col_idx].copy()
        return Value.of_null()

    def rowid(self) -> Int64:
        return Int64(self.row_idx + 1)


struct VirtualTableModule(ImplicitlyCopyable, Copyable, Movable):
    var module_name: String
    var tables: List[VirtualTable]

    def __init__(out self, module_name: String = ""):
        self.module_name = module_name
        self.tables = List[VirtualTable]()

    def __init__(out self, *, copy: Self):
        self.module_name = copy.module_name
        self.tables = copy.tables.copy()

    def __init__(out self, *, deinit move: Self):
        self.module_name = move.module_name^
        self.tables = move.tables^

    def create(mut self, table_name: String, args_str: String) raises -> VirtualTable:
        var vtab = VirtualTable(table_name, self.module_name, args_str)
        # Parse column declarations from arguments if present
        if args_str != "":
            var parts = args_str.split(",")
            for i in range(len(parts)):
                var p = String(parts[i].strip())
                if p != "":
                    var words = p.split(" ")
                    if len(words) > 0 and words[0].byte_length() > 0:
                        vtab.column_names.append(String(words[0].strip()))
        if len(vtab.column_names) == 0:
            vtab.column_names.append("value")
        
        # Check if table already exists in this module
        var found = False
        for i in range(len(self.tables)):
            if nocase_compare(self.tables[i].table_name, table_name) == 0:
                self.tables[i] = vtab.copy()
                found = True
                break
        if not found:
            self.tables.append(vtab.copy())
        return vtab^

    def get_table(self, table_name: String) -> Optional[VirtualTable]:
        for i in range(len(self.tables)):
            if nocase_compare(self.tables[i].table_name, table_name) == 0:
                return Optional(self.tables[i].copy())
        return None

    def open(self, table_name: String) -> VirtualTableCursor:
        var cur = VirtualTableCursor()
        for i in range(len(self.tables)):
            if nocase_compare(self.tables[i].table_name, table_name) == 0:
                cur.filtered_rows = self.tables[i].rows.copy()
                break
        return cur^

    def update_insert(mut self, table_name: String, values: List[Value]) -> Int64:
        for i in range(len(self.tables)):
            if nocase_compare(self.tables[i].table_name, table_name) == 0:
                var r = Row(values.copy(), self.tables[i].column_names.copy())
                self.tables[i].rows.append(r^)
                return Int64(len(self.tables[i].rows))
        return 0

    def update_delete(mut self, table_name: String, rowid: Int64) -> Bool:
        for i in range(len(self.tables)):
            if nocase_compare(self.tables[i].table_name, table_name) == 0:
                var idx = Int(rowid) - 1
                if idx >= 0 and idx < len(self.tables[i].rows):
                    var new_rows = List[Row]()
                    for r_i in range(len(self.tables[i].rows)):
                        if r_i != idx:
                            new_rows.append(self.tables[i].rows[r_i].copy())
                    self.tables[i].rows = new_rows^
                    return True
        return False
