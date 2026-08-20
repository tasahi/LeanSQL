""" SQLite Database Connection and Cursor Management - Pure Mojo Engine.

Provides `Connection`, `Cursor`, and factory function `connect()` conforming to
Python's `sqlite3` interface, backed 100% by native Mojo subsystems without C FFI.
Supports multi-table JOINs, Compound queries (UNION/INTERSECT/EXCEPT), and On-Disk persistence.
"""

from std.memory import UnsafePointer, alloc
from src.types import *
from src.row import Value, Row
from src.schema import SchemaCatalog, TableDef, IndexDef, ColumnDef
from src.btree import MemBTree, BTreeCursor
from src.record import encode_record, decode_record
from src.page_header import DbHeader, SQLITE_FILE_HEADER_MAGIC
from src.btree_cell import TableLeafCell
from src.tokenizer import tokenize_sql, Token, TK_EOF
from src.parser import (
    parse_sql,
    ASTStatement,
    SelectStmt,
    SelectColumn,
    InsertStmt,
    UpdateStmt,
    DeleteStmt,
    CreateTableStmt,
    CreateIndexStmt,
    DropIndexStmt,
    TransStmt,
    JoinClause,
    JOIN_INNER,
    JOIN_LEFT,
    JOIN_CROSS,
    COMPOUND_NONE,
    COMPOUND_UNION,
    COMPOUND_UNION_ALL,
    COMPOUND_INTERSECT,
    COMPOUND_EXCEPT,
    Expr,
    EXPR_LITERAL,
    EXPR_COLUMN,
    EXPR_BINARY,
    EXPR_UNARY,
    EXPR_FUNC,
    EXPR_STAR,
    PragmaStmt,
    AlterTableStmt,
    CreateViewStmt,
    DropViewStmt,
    CreateTriggerStmt,
    DropTriggerStmt,
    CTETable,
    WindowSpec,
    STMT_SELECT,
    STMT_INSERT,
    STMT_UPDATE,
    STMT_DELETE,
    STMT_CREATE_TABLE,
    STMT_CREATE_INDEX,
    STMT_DROP_INDEX,
    STMT_TRANS,
    STMT_PRAGMA,
    STMT_ALTER_TABLE,
    STMT_CREATE_VIEW,
    STMT_DROP_VIEW,
    STMT_CREATE_TRIGGER,
    STMT_DROP_TRIGGER,
    ALTER_RENAME_TABLE,
    ALTER_ADD_COLUMN,
    ALTER_RENAME_COLUMN,
    TK_BEGIN,
    TK_COMMIT,
    TK_ROLLBACK,
    TK_SAVEPOINT,
    TK_RELEASE,
)
from src.schema import (
    SchemaCatalog,
    TableDef,
    IndexDef,
    ColumnDef,
    ViewDef,
    TriggerDef,
    TRIGGER_BEFORE,
    TRIGGER_AFTER,
    TRIGGER_EVENT_INSERT,
    TRIGGER_EVENT_UPDATE,
    TRIGGER_EVENT_DELETE,
)
from src.compiler import eval_expr_row
from src.functions import evaluate_scalar_func
from src.utf import nocase_compare
from src.vfs import VFS, DiskFile


struct SavepointSnapshot(ImplicitlyCopyable, Copyable, Movable):
    var name: String
    var tables: List[MemBTree]

    def __init__(out self, name: String, tables: List[MemBTree]):
        self.name = name
        self.tables = tables.copy()

    def __init__(out self, *, copy: Self):
        self.name = copy.name
        self.tables = copy.tables.copy()

    def __init__(out self, *, deinit move: Self):
        self.name = move.name^
        self.tables = move.tables^


struct Cursor(ImplicitlyCopyable, Copyable, Movable):
    """ Manages iteration over SQL query results and statement execution."""
    var _conn: UnsafePointer[Connection, MutAnyOrigin]
    var _rows: List[Row]
    var _idx: Int
    var _col_names: List[String]
    var rowcount: Int
    var lastrowid: Int64

    def __init__(out self, conn: UnsafePointer[Connection, MutAnyOrigin]):
        self._conn = conn
        self._rows = List[Row]()
        self._idx = 0
        self._col_names = List[String]()
        self.rowcount = -1
        self.lastrowid = 0

    def __init__(out self, *, copy: Self):
        self._conn = copy._conn
        self._rows = copy._rows.copy()
        self._idx = copy._idx
        self._col_names = copy._col_names.copy()
        self.rowcount = copy.rowcount
        self.lastrowid = copy.lastrowid

    def __init__(out self, *, deinit move: Self):
        self._conn = move._conn
        self._rows = move._rows^
        self._idx = move._idx
        self._col_names = move._col_names^
        self.rowcount = move.rowcount
        self.lastrowid = move.lastrowid

    def execute(mut self, sql: String) raises:
        """ Prepares and executes SQL through the parent Connection."""
        var res_rows = List[Row]()
        var res_cols = List[String]()
        self._conn[]._execute_internal(sql, res_rows, res_cols)
        self._rows = res_rows^
        self._idx = 0
        self._col_names = res_cols^
        self.rowcount = self._conn[].change_count
        self.lastrowid = self._conn[].last_rowid

    def execute_params(mut self, sql: String, params: List[Value]) raises:
        """ Prepares SQL with ? parameters and executes."""
        var bound_sql = self._conn[]._substitute_params(sql, params)
        self.execute(bound_sql)

    def fetchone(mut self) -> Optional[Row]:
        """ Fetches the next row in the result set, or None if exhausted."""
        if self._idx >= 0 and self._idx < len(self._rows):
            var row = self._rows[self._idx].copy()
            self._idx += 1
            return Optional(row^)
        return None

    def fetchall(mut self) -> List[Row]:
        """ Fetches all remaining rows in the result set."""
        var res = List[Row]()
        while self._idx < len(self._rows):
            res.append(self._rows[self._idx].copy())
            self._idx += 1
        return res^

    def column_names(self) -> List[String]:
        """ Returns the projected column names of the query."""
        return self._col_names.copy()

    def close(mut self):
        """ Releases cursor buffered rows."""
        self._rows = List[Row]()
        self._idx = 0


struct Connection(ImplicitlyCopyable, Copyable, Movable):
    """ Represents an open SQLite database connection in pure Mojo."""
    var database: String
    var schema: SchemaCatalog
    var tables: List[MemBTree]
    var savepoints: List[SavepointSnapshot]
    var tx_snapshot: List[MemBTree]
    var autocommit_mode: Bool
    var last_rowid: Int64
    var change_count: Int
    var total_change_count: Int

    def __init__(out self, database: String = ":memory:"):
        self.database = database
        self.schema = SchemaCatalog()
        self.tables = List[MemBTree]()
        self.savepoints = List[SavepointSnapshot]()
        self.tx_snapshot = List[MemBTree]()
        self.autocommit_mode = True
        self.last_rowid = 0
        self.change_count = 0
        self.total_change_count = 0
        if self.database != ":memory:" and self.database != "":
            try:
                self._load_from_disk()
            except:
                pass

    def __init__(out self, *, copy: Self):
        self.database = copy.database
        self.schema = copy.schema.copy()
        self.tables = copy.tables.copy()
        self.savepoints = copy.savepoints.copy()
        self.tx_snapshot = copy.tx_snapshot.copy()
        self.autocommit_mode = copy.autocommit_mode
        self.last_rowid = copy.last_rowid
        self.change_count = copy.change_count
        self.total_change_count = copy.total_change_count

    def __init__(out self, *, deinit move: Self):
        self.database = move.database^
        self.schema = move.schema^
        self.tables = move.tables^
        self.savepoints = move.savepoints^
        self.tx_snapshot = move.tx_snapshot^
        self.autocommit_mode = move.autocommit_mode
        self.last_rowid = move.last_rowid
        self.change_count = move.change_count
        self.total_change_count = move.total_change_count

    def cursor(mut self) -> Cursor:
        """ Creates a new Cursor attached to this Connection."""
        var ptr = UnsafePointer(to=self)
        return Cursor(ptr)

    def _save_to_disk(self) raises:
        """ Persists schema and all B-tree table records to disk in standard SQLite 3 binary page format."""
        if (
            self.database == ":memory:"
            or self.database == ""
            or self.database.startswith("CREATE ")
            or self.database.startswith("INSERT ")
            or self.database.startswith("UPDATE ")
            or self.database.startswith("DELETE ")
            or self.database.startswith("SELECT ")
            or self.database.startswith("DROP ")
        ):
            return
        var vfs = VFS()
        var f = vfs.open_disk(self.database, read_only=False, create=True)

        var page_size = 4096
        var n_tables = len(self.schema.tables)
        var total_pages = 1 + n_tables

        # --- Build Page 1 (100-byte Database Header + sqlite_master B-Tree Page) ---
        var page1 = List[UInt8]()
        for _ in range(page_size):
            page1.append(0)

        # 1. 100-byte Database Header
        var db_hdr = DbHeader()
        db_hdr.page_size = UInt32(page_size)
        db_hdr.db_size_pages = UInt32(total_pages)
        db_hdr.schema_cookie = 1
        db_hdr.schema_format = 4
        db_hdr.file_change_counter = 1
        db_hdr.version_valid_for = 1
        var hdr_bytes = db_hdr.encode()
        for i in range(100):
            page1[i] = hdr_bytes[i]

        # 2. Build sqlite_master cells
        # Columns in sqlite_master: type (TEXT), name (TEXT), tbl_name (TEXT), rootpage (INT), sql (TEXT)
        var master_cells = List[List[UInt8]]()
        for t in range(n_tables):
            var tbl = self.schema.tables[t]
            var rootpage = t + 2  # Table 0 -> Page 2, Table 1 -> Page 3, etc.
            var vals = List[Value]()
            vals.append(Value.of_text("table"))
            vals.append(Value.of_text(tbl.name))
            vals.append(Value.of_text(tbl.name))
            vals.append(Value.of_int(Int64(rootpage)))
            vals.append(Value.of_text(tbl.to_sql()))
            var rec = encode_record(vals)
            var cell = TableLeafCell(Int64(t + 1), rec)
            master_cells.append(cell.encode())

        # 3. Pack cells into Page 1 (offset 100..4095)
        var p1_cell_count = len(master_cells)
        var p1_content_offset = page_size
        var p1_cell_ptrs = List[Int]()

        for c_i in range(p1_cell_count):
            var c_bytes = master_cells[c_i].copy()
            var c_len = len(c_bytes)
            p1_content_offset -= c_len
            p1_cell_ptrs.append(p1_content_offset)
            for b in range(c_len):
                page1[p1_content_offset + b] = c_bytes[b]

        # Write Page 1 B-Tree Page Header at offset 100
        page1[100] = 0x0D  # Leaf Table Page
        page1[101] = 0x00
        page1[102] = 0x00  # First freeblock = 0
        page1[103] = UInt8((p1_cell_count >> 8) & 0xFF)
        page1[104] = UInt8(p1_cell_count & 0xFF)
        page1[105] = UInt8((p1_content_offset >> 8) & 0xFF)
        page1[106] = UInt8(p1_content_offset & 0xFF)
        page1[107] = 0x00  # Fragmented free bytes

        # Write Page 1 Cell Pointer Array (starting at offset 108)
        for c_i in range(p1_cell_count):
            var ptr = p1_cell_ptrs[c_i]
            page1[108 + c_i * 2] = UInt8((ptr >> 8) & 0xFF)
            page1[108 + c_i * 2 + 1] = UInt8(ptr & 0xFF)

        # Write Page 1 to disk
        _ = f.write(0, page_size, page1.unsafe_ptr())

        # --- Build Pages 2..N (User Table B-Tree Pages) ---
        for t in range(n_tables):
            var tbl = self.schema.tables[t]
            var btree_idx = tbl.btree_idx
            var n_rows = 0
            if btree_idx >= 0 and btree_idx < len(self.tables):
                n_rows = self.tables[btree_idx].cell_count()

            var user_cells = List[List[UInt8]]()
            if btree_idx >= 0 and btree_idx < len(self.tables):
                for r in range(n_rows):
                    var cell = self.tables[btree_idx].get_cell(r)
                    var t_cell = TableLeafCell(cell.rowid, cell.payload)
                    user_cells.append(t_cell.encode())

            var page_t = List[UInt8]()
            for _ in range(page_size):
                page_t.append(0)

            var t_content_offset = page_size
            var t_cell_ptrs = List[Int]()

            for c_i in range(len(user_cells)):
                var c_bytes = user_cells[c_i].copy()
                var c_len = len(c_bytes)
                t_content_offset -= c_len
                t_cell_ptrs.append(t_content_offset)
                for b in range(c_len):
                    page_t[t_content_offset + b] = c_bytes[b]

            # Write Leaf Table Page Header at offset 0 of page_t
            var u_cell_count = len(user_cells)
            page_t[0] = 0x0D  # Leaf Table Page
            page_t[1] = 0x00
            page_t[2] = 0x00  # First freeblock = 0
            page_t[3] = UInt8((u_cell_count >> 8) & 0xFF)
            page_t[4] = UInt8(u_cell_count & 0xFF)
            page_t[5] = UInt8((t_content_offset >> 8) & 0xFF)
            page_t[6] = UInt8(t_content_offset & 0xFF)
            page_t[7] = 0x00  # Fragmented free bytes

            # Write Cell Pointer Array (starting at offset 8)
            for c_i in range(u_cell_count):
                var ptr = t_cell_ptrs[c_i]
                page_t[8 + c_i * 2] = UInt8((ptr >> 8) & 0xFF)
                page_t[8 + c_i * 2 + 1] = UInt8(ptr & 0xFF)

            # Write Page (t + 2) to disk at offset (t + 1) * 4096
            var page_file_offset = Int64(t + 1) * Int64(page_size)
            _ = f.write(page_file_offset, page_size, page_t.unsafe_ptr())

        f.close()

    def _load_from_disk(mut self) raises:
        """ Reloads schema and tables from disk in standard SQLite 3 binary page format."""
        if self.database == ":memory:" or self.database == "":
            return
        var vfs = VFS()
        if not vfs.file_exists(self.database):
            return
        var f = vfs.open_disk(self.database, read_only=True, create=False)
        var sz = f.file_size()
        if sz < 100:
            f.close()
            return

        var buf = List[UInt8]()
        for _ in range(Int(sz)):
            buf.append(0)
        _ = f.read(0, Int(sz), buf.unsafe_ptr())
        f.close()

        if len(buf) < 100:
            return

        # 1. Check for standard SQLite 3 header ("SQLite format 3\000")
        var sqlite_magic = SQLITE_FILE_HEADER_MAGIC.as_bytes()
        var is_sqlite3 = True
        for i in range(16):
            if buf[i] != sqlite_magic[i]:
                is_sqlite3 = False
                break

        if is_sqlite3:
            var page_size = 4096
            if len(buf) >= 18:
                var ps_raw = (Int(buf[16]) << 8) | Int(buf[17])
                if ps_raw == 1:
                    page_size = 65536
                elif ps_raw > 0:
                    page_size = ps_raw

            self.schema = SchemaCatalog()
            self.tables = List[MemBTree]()

            # Read Page 1 sqlite_master B-tree cells
            if len(buf) >= 108:
                var p1_cell_count = (Int(buf[103]) << 8) | Int(buf[104])
                for c_i in range(p1_cell_count):
                    var ptr_offset = 108 + c_i * 2
                    if ptr_offset + 1 < len(buf):
                        var cell_ptr = (Int(buf[ptr_offset]) << 8) | Int(buf[ptr_offset + 1])
                        if cell_ptr < len(buf):
                            var p_slice = alloc[UInt8](len(buf) - cell_ptr)
                            for b in range(len(buf) - cell_ptr):
                                p_slice[b] = buf[cell_ptr + b]
                            var immut_slice = UnsafePointer[UInt8, ImmutAnyOrigin](other=p_slice)
                            var t_cell_res = TableLeafCell.decode(immut_slice)
                            var t_cell = t_cell_res[0].copy()
                            p_slice.free()

                            # Unpack sqlite_master record
                            var rec_vals = decode_record(t_cell.payload)
                            if len(rec_vals) >= 5:
                                var tbl_type = rec_vals[0].to_string()
                                var tbl_name = rec_vals[1].to_string()
                                var rootpage = Int(rec_vals[3].to_int())
                                var sql_ddl = rec_vals[4].to_string()

                                if nocase_compare(tbl_type, "table") == 0:
                                    var ast = parse_sql(tokenize_sql(sql_ddl))
                                    if ast.stmt_type == STMT_CREATE_TABLE and len(ast.create_table_stmt) > 0:
                                        var ct = ast.create_table_stmt[0].copy()
                                        var btree_idx = len(self.tables)
                                        self.tables.append(MemBTree())
                                        var tbl_def = TableDef(ct.table_name, btree_idx)
                                        for col_i in range(len(ct.columns)):
                                            tbl_def.add_column(ct.columns[col_i])

                                        # Read user table page from rootpage
                                        var page_offset = (rootpage - 1) * page_size
                                        if page_offset + 8 <= len(buf):
                                            var u_cell_count = (Int(buf[page_offset + 3]) << 8) | Int(buf[page_offset + 4])
                                            var max_rid: Int64 = 0
                                            for u_i in range(u_cell_count):
                                                var u_ptr_off = page_offset + 8 + u_i * 2
                                                if u_ptr_off + 1 < len(buf):
                                                    var u_ptr = (Int(buf[u_ptr_off]) << 8) | Int(buf[u_ptr_off + 1])
                                                    var abs_u_ptr = page_offset + u_ptr
                                                    if abs_u_ptr < len(buf):
                                                        var u_slice = alloc[UInt8](len(buf) - abs_u_ptr)
                                                        for b in range(len(buf) - abs_u_ptr):
                                                            u_slice[b] = buf[abs_u_ptr + b]
                                                        var immut_u_slice = UnsafePointer[UInt8, ImmutAnyOrigin](other=u_slice)
                                                        var u_cell_res = TableLeafCell.decode(immut_u_slice)
                                                        var u_cell = u_cell_res[0].copy()
                                                        u_slice.free()

                                                        if u_cell.rowid > max_rid:
                                                            max_rid = u_cell.rowid
                                                        self.tables[btree_idx].insert(u_cell.rowid, u_cell.payload)

                                            tbl_def.auto_rowid = max_rid + 1

                                        self.schema.add_table(tbl_def^)
            return

    def _substitute_params(self, sql: String, params: List[Value]) -> String:
        var bytes = sql.as_bytes()
        var n = len(bytes)
        var res = String()
        var p_idx = 0
        for i in range(n):
            if bytes[i] == 63: # '?'
                if p_idx < len(params):
                    var p = params[p_idx]
                    p_idx += 1
                    if p.type_tag == SQLITE_TEXT:
                        res += "'" + p.text_val + "'"
                    elif p.type_tag == SQLITE_INTEGER:
                        res += String(p.int_val)
                    elif p.type_tag == SQLITE_FLOAT:
                        res += String(p.float_val)
                    else:
                        res += "NULL"
                else:
                    res += "?"
            else:
                res += chr(Int(bytes[i]))
        return res^

    def execute_params(mut self, sql: String, params: List[Value]) raises -> Cursor:
        var bound_sql = self._substitute_params(sql, params)
        return self.execute(bound_sql)

    def execute(mut self, sql: String) raises -> Cursor:
        """ Compiles and executes an SQL statement in pure Mojo."""
        var cur = self.cursor()
        cur.execute(sql)
        return cur^

    def _execute_internal(mut self, sql: String, mut out_rows: List[Row], mut out_cols: List[String]) raises:
        var tokens = tokenize_sql(sql)
        var ast = parse_sql(tokens)
        var st = ast.stmt_type

        # 1. CREATE TABLE
        if st == STMT_CREATE_TABLE:
            var ct = ast.create_table_stmt[0].copy()
            var btree_idx = len(self.tables)
            self.tables.append(MemBTree())
            var tbl_def = TableDef(ct.table_name, btree_idx)
            for i in range(len(ct.columns)):
                tbl_def.add_column(ct.columns[i])
            self.schema.add_table(tbl_def^)
            self.change_count = 0
            self._save_to_disk()

        # 2. CREATE INDEX
        elif st == STMT_CREATE_INDEX:
            var ci = ast.create_index_stmt[0].copy()
            var idx_btree_idx = len(self.tables)
            self.tables.append(MemBTree())
            var idx_def = IndexDef(ci.index_name, ci.table_name, ci.is_unique, idx_btree_idx)
            for i in range(len(ci.columns)):
                idx_def.columns.append(ci.columns[i])
            self.schema.add_index(idx_def^)
            self.change_count = 0
            self._save_to_disk()

        # 3. DROP INDEX
        elif st == STMT_DROP_INDEX:
            var di = ast.drop_index_stmt[0].copy()
            _ = self.schema.drop_index(di.index_name)
            self.change_count = 0
            self._save_to_disk()

        # 4. TRANSACTIONS
        elif st == STMT_TRANS:
            var tr = ast.trans_stmt[0].copy()
            if tr.op_type == TK_BEGIN:
                self.autocommit_mode = False
                self.tx_snapshot = self.tables.copy()
            elif tr.op_type == TK_COMMIT:
                self.autocommit_mode = True
                self.tx_snapshot = List[MemBTree]()
                self._save_to_disk()
            elif tr.op_type == TK_ROLLBACK:
                if tr.name != "":
                    for i in range(len(self.savepoints)):
                        if nocase_compare(self.savepoints[i].name, tr.name) == 0:
                            self.tables = self.savepoints[i].tables.copy()
                            break
                else:
                    if len(self.tx_snapshot) > 0:
                        self.tables = self.tx_snapshot.copy()
                    self.autocommit_mode = True
            elif tr.op_type == TK_SAVEPOINT:
                self.savepoints.append(SavepointSnapshot(tr.name, self.tables))
            elif tr.op_type == TK_RELEASE:
                var new_sp = List[SavepointSnapshot]()
                for i in range(len(self.savepoints)):
                    if nocase_compare(self.savepoints[i].name, tr.name) != 0:
                        new_sp.append(self.savepoints[i].copy())
                self.savepoints = new_sp^
            self.change_count = 0

        # 5. INSERT
        elif st == STMT_INSERT:
            var ins = ast.insert_stmt[0].copy()
            var tbl_opt = self.schema.find_table(ins.table_name)
            if not tbl_opt:
                raise Error("no such table: " + ins.table_name)
            var tbl_def = tbl_opt.value()
            var btree_idx = tbl_def.btree_idx
            var empty_row = Row(List[Value](), List[String]())
            var pk_idx = tbl_def.primary_key_col_index()

            # Check if INSERT INTO ... SELECT
            if len(ins.select_stmt) > 0:
                var sel_rows = List[Row]()
                var sel_cols = List[String]()
                self._execute_select_internal(ins.select_stmt[0].copy(), sel_rows, sel_cols)
                var rows_inserted = 0
                for r_idx in range(len(sel_rows)):
                    var s_row = sel_rows[r_idx]
                    var row_vals = List[Value]()
                    for c in range(len(tbl_def.columns)):
                        if c < len(s_row):
                            row_vals.append(s_row[c].copy())
                        else:
                            row_vals.append(Value.of_null())
                    var rowid = tbl_def.auto_rowid
                    tbl_def.auto_rowid += 1
                    if pk_idx >= 0 and pk_idx < len(row_vals):
                        if row_vals[pk_idx].is_null():
                            row_vals[pk_idx] = Value.of_int(rowid)
                    var payload = encode_record(row_vals)
                    self.tables[btree_idx].insert(rowid, payload)
                    rows_inserted += 1
                    self.last_rowid = rowid
                self.change_count = rows_inserted
                self.total_change_count += rows_inserted
                self._save_to_disk()
                return

            var row_vals = List[Value]()
            var explicit_rowid: Optional[Int64] = None

            if len(ins.columns) > 0:
                for c in range(len(tbl_def.columns)):
                    var col_name = tbl_def.columns[c].name
                    var found_idx = -1
                    for k in range(len(ins.columns)):
                        if nocase_compare(ins.columns[k], col_name) == 0:
                            found_idx = k
                            break
                    if found_idx >= 0 and found_idx < len(ins.values):
                        var v = eval_expr_row(ins.values[found_idx], empty_row, List[String]())
                        if c == pk_idx and not v.is_null():
                            explicit_rowid = Optional(v.to_int())
                        row_vals.append(v^)
                    elif tbl_def.columns[c].has_default:
                        row_vals.append(tbl_def.columns[c].default_value.copy())
                    else:
                        row_vals.append(Value.of_null())
            else:
                for v_idx in range(len(ins.values)):
                    var v = eval_expr_row(ins.values[v_idx], empty_row, List[String]())
                    if v_idx == pk_idx and not v.is_null():
                        explicit_rowid = Optional(v.to_int())
                    row_vals.append(v^)

            var rowid = tbl_def.auto_rowid
            if explicit_rowid:
                rowid = explicit_rowid.value()
                if rowid >= tbl_def.auto_rowid:
                    tbl_def.auto_rowid = rowid + 1
            else:
                tbl_def.auto_rowid += 1

            if pk_idx >= 0 and pk_idx < len(row_vals):
                if row_vals[pk_idx].is_null():
                    row_vals[pk_idx] = Value.of_int(rowid)

            var t_idx = self.schema.find_table_index(tbl_def.name)
            if t_idx >= 0:
                self.schema.tables[t_idx].auto_rowid = tbl_def.auto_rowid

            var payload = encode_record(row_vals)
            self.tables[btree_idx].insert(rowid, payload)
            self.last_rowid = rowid
            self.change_count = 1
            self.total_change_count += 1
            self._save_to_disk()

            # Fire AFTER INSERT triggers
            var trgs = self.schema.find_triggers_for_table(tbl_def.name, TRIGGER_AFTER, TRIGGER_EVENT_INSERT)
            for t_i in range(len(trgs)):
                var trg_sql = trgs[t_i].action_sql
                if trg_sql != "":
                    # Substitute NEW.column references
                    for c in range(len(tbl_def.columns)):
                        var col_name = tbl_def.columns[c].name
                        var val_str = row_vals[c].to_string() if c < len(row_vals) else "NULL"
                        if row_vals[c].type_tag == SQLITE_TEXT:
                            val_str = "'" + row_vals[c].text_val + "'"
                        # Replace NEW.col_name
                        var target_tag = "NEW." + col_name
                        # Simple replacement
                        var new_sql = String()
                        var sql_bytes = trg_sql.as_bytes()
                        var tag_bytes = target_tag.as_bytes()
                        var b_pos = 0
                        while b_pos < len(sql_bytes):
                            var matched = True
                            if b_pos + len(tag_bytes) <= len(sql_bytes):
                                for k in range(len(tag_bytes)):
                                    if sql_bytes[b_pos + k] != tag_bytes[k]:
                                        matched = False
                                        break
                            else:
                                matched = False
                            if matched:
                                new_sql += val_str
                                b_pos += len(tag_bytes)
                            else:
                                new_sql += chr(Int(sql_bytes[b_pos]))
                                b_pos += 1
                        trg_sql = new_sql
                    var d_rows = List[Row]()
                    var d_cols = List[String]()
                    self._execute_internal(trg_sql, d_rows, d_cols)

        # 6. UPDATE
        elif st == STMT_UPDATE:
            var upd = ast.update_stmt[0].copy()
            var tbl_opt = self.schema.find_table(upd.table_name)
            if not tbl_opt:
                raise Error("no such table: " + upd.table_name)
            var tbl_def = tbl_opt.value()
            var btree_idx = tbl_def.btree_idx
            var n_cells = self.tables[btree_idx].cell_count()

            var col_names = List[String]()
            for c in range(len(tbl_def.columns)):
                col_names.append(tbl_def.columns[c].name)

            var rows_updated = 0
            for i in range(n_cells):
                var cell = self.tables[btree_idx].get_cell(i)
                var row_vals = decode_record(cell.payload)
                var row = Row(row_vals, col_names)

                var matches = True
                if len(upd.where_expr) > 0:
                    var w_res = eval_expr_row(upd.where_expr[0], row, col_names)
                    if w_res.is_null() or w_res.to_int() == 0:
                        matches = False

                if matches:
                    var new_vals = List[Value]()
                    for c in range(len(row_vals)):
                        new_vals.append(row_vals[c].copy())

                    for s in range(len(upd.assignments)):
                        var col_name = upd.assignments[s].col_name
                        var expr = upd.assignments[s].expr
                        var val = eval_expr_row(expr, row, col_names)
                        for c in range(len(col_names)):
                            if nocase_compare(col_names[c], col_name) == 0:
                                new_vals[c] = val^
                                break

                    var new_payload = encode_record(new_vals)
                    _ = self.tables[btree_idx].delete(cell.rowid)
                    self.tables[btree_idx].insert(cell.rowid, new_payload)
                    rows_updated += 1

            self.change_count = rows_updated
            self.total_change_count += rows_updated
            self._save_to_disk()

            # Fire AFTER UPDATE triggers
            if rows_updated > 0:
                var trgs = self.schema.find_triggers_for_table(tbl_def.name, TRIGGER_AFTER, TRIGGER_EVENT_UPDATE)
                for t_i in range(len(trgs)):
                    var trg_sql = trgs[t_i].action_sql
                    if trg_sql != "":
                        var d_rows = List[Row]()
                        var d_cols = List[String]()
                        self._execute_internal(trg_sql, d_rows, d_cols)

        # 7. DELETE
        elif st == STMT_DELETE:
            var del_stmt = ast.delete_stmt[0].copy()
            var tbl_opt = self.schema.find_table(del_stmt.table_name)
            if not tbl_opt:
                raise Error("no such table: " + del_stmt.table_name)
            var tbl_def = tbl_opt.value()
            var btree_idx = tbl_def.btree_idx

            var col_names = List[String]()
            for c in range(len(tbl_def.columns)):
                col_names.append(tbl_def.columns[c].name)

            var to_delete = List[Int64]()
            var n_cells = self.tables[btree_idx].cell_count()

            for i in range(n_cells):
                var cell = self.tables[btree_idx].get_cell(i)
                var row_vals = decode_record(cell.payload)
                var row = Row(row_vals, col_names)

                var matches = True
                if len(del_stmt.where_expr) > 0:
                    var w_res = eval_expr_row(del_stmt.where_expr[0], row, col_names)
                    if w_res.is_null() or w_res.to_int() == 0:
                        matches = False

                if matches:
                    to_delete.append(cell.rowid)

            for i in range(len(to_delete)):
                _ = self.tables[btree_idx].delete(to_delete[i])

            var rows_deleted = len(to_delete)
            self.change_count = rows_deleted
            self.total_change_count += rows_deleted
            self._save_to_disk()

            # Fire AFTER DELETE triggers
            if rows_deleted > 0:
                var trgs = self.schema.find_triggers_for_table(tbl_def.name, TRIGGER_AFTER, TRIGGER_EVENT_DELETE)
                for t_i in range(len(trgs)):
                    var trg_sql = trgs[t_i].action_sql
                    if trg_sql != "":
                        var d_rows = List[Row]()
                        var d_cols = List[String]()
                        self._execute_internal(trg_sql, d_rows, d_cols)

        # 8. SELECT
        elif st == STMT_SELECT:
            self.change_count = -1
            self._execute_select_internal(ast.select_stmt[0].copy(), out_rows, out_cols)

        # 9. PRAGMA
        elif st == STMT_PRAGMA:
            var prg = ast.pragma_stmt[0].copy()
            self.change_count = -1
            if nocase_compare(prg.pragma_name, "table_info") == 0:
                out_cols.append("cid")
                out_cols.append("name")
                out_cols.append("type")
                out_cols.append("notnull")
                out_cols.append("dfl_value")
                out_cols.append("pk")
                var tbl_opt = self.schema.find_table(prg.pragma_arg)
                if tbl_opt:
                    var tbl = tbl_opt.value()
                    for c in range(len(tbl.columns)):
                        var col = tbl.columns[c]
                        var type_str = "TEXT"
                        if col.type_affinity == SQLITE_INTEGER:
                            type_str = "INTEGER"
                        elif col.type_affinity == SQLITE_FLOAT:
                            type_str = "REAL"
                        elif col.type_affinity == SQLITE_BLOB:
                            type_str = "BLOB"
                        var vals = List[Value]()
                        vals.append(Value.of_int(Int64(c)))
                        vals.append(Value.of_text(col.name))
                        vals.append(Value.of_text(type_str))
                        vals.append(Value.of_int(Int64(1 if col.not_null else 0)))
                        vals.append(col.default_value.copy())
                        vals.append(Value.of_int(Int64(1 if col.is_primary_key else 0)))
                        out_rows.append(Row(vals^, out_cols.copy()))
            elif nocase_compare(prg.pragma_name, "index_list") == 0:
                out_cols.append("seq")
                out_cols.append("name")
                out_cols.append("unique")
                out_cols.append("origin")
                out_cols.append("partial")
                var seq = 0
                for i in range(len(self.schema.indices)):
                    var idx = self.schema.indices[i]
                    if nocase_compare(idx.table_name, prg.pragma_arg) == 0:
                        var vals = List[Value]()
                        vals.append(Value.of_int(Int64(seq)))
                        vals.append(Value.of_text(idx.name))
                        vals.append(Value.of_int(Int64(1 if idx.is_unique else 0)))
                        vals.append(Value.of_text("c"))
                        vals.append(Value.of_int(Int64(0)))
                        out_rows.append(Row(vals^, out_cols.copy()))
                        seq += 1
            elif nocase_compare(prg.pragma_name, "user_version") == 0:
                out_cols.append("user_version")
                if prg.has_val:
                    self.schema.user_version = Int64(atol(prg.pragma_val))
                    self._save_to_disk()
                else:
                    var vals = List[Value]()
                    vals.append(Value.of_int(self.schema.user_version))
                    out_rows.append(Row(vals^, out_cols.copy()))

        # 10. ALTER TABLE
        elif st == STMT_ALTER_TABLE:
            var alt = ast.alter_table_stmt[0].copy()
            if alt.op_type == ALTER_RENAME_TABLE:
                _ = self.schema.rename_table(alt.table_name, alt.new_name)
            elif alt.op_type == ALTER_ADD_COLUMN:
                if len(alt.column_def) > 0:
                    _ = self.schema.add_column_to_table(alt.table_name, alt.column_def[0])
            elif alt.op_type == ALTER_RENAME_COLUMN:
                var colon_pos = -1
                var n_bytes = alt.new_name.as_bytes()
                for b in range(len(n_bytes)):
                    if n_bytes[b] == 58: # ':'
                        colon_pos = b
                        break
                if colon_pos >= 0:
                    var old_c = String()
                    for b in range(colon_pos):
                        old_c += chr(Int(n_bytes[b]))
                    var new_c = String()
                    for b in range(colon_pos + 1, len(n_bytes)):
                        new_c += chr(Int(n_bytes[b]))
                    _ = self.schema.rename_column(alt.table_name, old_c, new_c)
            self.change_count = 0
            self._save_to_disk()

        # 11. CREATE VIEW
        elif st == STMT_CREATE_VIEW:
            var cv = ast.create_view_stmt[0].copy()
            self.schema.add_view(ViewDef(cv.view_name, ""))
            self.change_count = 0

        # 12. DROP VIEW
        elif st == STMT_DROP_VIEW:
            var dv = ast.drop_view_stmt[0].copy()
            _ = self.schema.drop_view(dv.view_name)
            self.change_count = 0

        # 13. CREATE TRIGGER
        elif st == STMT_CREATE_TRIGGER:
            var ct = ast.create_trigger_stmt[0].copy()
            self.schema.add_trigger(TriggerDef(ct.name, ct.timing, ct.event_type, ct.table_name, ct.action_sql))
            self.change_count = 0

        # 14. DROP TRIGGER
        elif st == STMT_DROP_TRIGGER:
            var dt = ast.drop_trigger_stmt[0].copy()
            _ = self.schema.drop_trigger(dt.name)
            self.change_count = 0

    def _resolve_subqueries(mut self, mut expr: Expr) raises:
        """ Pre-evaluates any scalar subqueries inside an expression tree."""
        if expr.kind == EXPR_FUNC and expr.func_name == "SUBQUERY":
            var target_tbl = expr.col_name
            if target_tbl != "" and len(expr.args) > 0:
                var sub_sel = SelectStmt()
                sub_sel.table_name = target_tbl
                sub_sel.columns.append(SelectColumn(expr.args[0].copy()))
                var sub_rows = List[Row]()
                var sub_cols = List[String]()
                self._execute_select_internal(sub_sel^, sub_rows, sub_cols)
                if len(sub_rows) > 0 and len(sub_rows[0]) > 0:
                    var scalar_val = sub_rows[0][0].copy()
                    expr = Expr.literal(scalar_val^)
                    return
        for i in range(len(expr.args)):
            self._resolve_subqueries(expr.args[i])

    def _execute_select_internal(mut self, sel: SelectStmt, mut out_rows: List[Row], mut out_col_names: List[String]) raises:
        """ Executes a SELECT query AST directly in pure Mojo."""
        var empty_row = Row(List[Value](), List[String]())

        # Pre-resolve subqueries in WHERE clause if present
        var local_where = sel.where_expr.copy()
        if len(local_where) > 0:
            self._resolve_subqueries(local_where[0])

        # Process CTE definitions (WITH name AS (subquery) / WITH RECURSIVE)
        if len(sel.ctes) > 0:
            for cte_idx in range(len(sel.ctes)):
                var cte = sel.ctes[cte_idx].copy()
                if len(cte.subquery) > 0:
                    var cte_sub = cte.subquery[0].copy()
                    var cte_rows = List[Row]()
                    var cte_cols = List[String]()

                    if sel.is_recursive_cte and cte_sub.compound_op == COMPOUND_UNION_ALL and len(cte_sub.compound_next) > 0:
                        # Recursive CTE: evaluate anchor step first
                        var anchor_sub = cte_sub.copy()
                        anchor_sub.compound_op = COMPOUND_NONE
                        anchor_sub.compound_next = List[SelectStmt]()
                        self._execute_select_internal(anchor_sub^, cte_rows, cte_cols)

                        # Create temporary table for CTE in schema
                        var temp_t = TableDef(cte.name, len(self.tables))
                        if len(cte.columns) > 0:
                            for c in range(len(cte.columns)):
                                temp_t.add_column(ColumnDef(cte.columns[c], SQLITE_INTEGER, False))
                        else:
                            for c in range(len(cte_cols)):
                                temp_t.add_column(ColumnDef(cte_cols[c], SQLITE_INTEGER, False))
                        self.schema.add_table(temp_t^)
                        var temp_btree = MemBTree()
                        for r in range(len(cte_rows)):
                            var vals = List[Value]()
                            for c in range(len(cte_rows[r])):
                                vals.append(cte_rows[r][c].copy())
                            temp_btree.insert(Int64(r + 1), encode_record(vals))
                        self.tables.append(temp_btree^)

                        var cur_idx = self.schema.find_table_index(cte.name)
                        var bt_idx = self.schema.tables[cur_idx].btree_idx
                        var all_accumulated = List[Row]()
                        for r in range(len(cte_rows)):
                            all_accumulated.append(cte_rows[r].copy())

                        var working_rows = List[Row]()
                        for r in range(len(cte_rows)):
                            working_rows.append(cte_rows[r].copy())

                        # Iterative recursive step (up to 1000 iterations limit)
                        var iter_count = 0
                        var rec_sub = cte_sub.compound_next[0].copy()
                        while iter_count < 1000:
                            # Populate temp table with only current working rows
                            self.tables[bt_idx] = MemBTree()
                            for r in range(len(working_rows)):
                                var vals = List[Value]()
                                for c in range(len(working_rows[r])):
                                    vals.append(working_rows[r][c].copy())
                                self.tables[bt_idx].insert(Int64(r + 1), encode_record(vals))

                            var step_rows = List[Row]()
                            var step_cols = List[String]()
                            self._execute_select_internal(rec_sub.copy(), step_rows, step_cols)
                            if len(step_rows) == 0:
                                break

                            working_rows = List[Row]()
                            for r in range(len(step_rows)):
                                all_accumulated.append(step_rows[r].copy())
                                working_rows.append(step_rows[r].copy())
                            iter_count += 1

                        # Store all accumulated rows into final CTE table
                        self.tables[bt_idx] = MemBTree()
                        for r in range(len(all_accumulated)):
                            var vals = List[Value]()
                            for c in range(len(all_accumulated[r])):
                                vals.append(all_accumulated[r][c].copy())
                            self.tables[bt_idx].insert(Int64(r + 1), encode_record(vals))
                    else:
                        self._execute_select_internal(cte_sub^, cte_rows, cte_cols)
                        var temp_t = TableDef(cte.name, len(self.tables))
                        if len(cte.columns) > 0:
                            for c in range(len(cte.columns)):
                                temp_t.add_column(ColumnDef(cte.columns[c], SQLITE_TEXT, False))
                        else:
                            for c in range(len(cte_cols)):
                                temp_t.add_column(ColumnDef(cte_cols[c], SQLITE_TEXT, False))
                        self.schema.add_table(temp_t^)
                        var temp_btree = MemBTree()
                        for r in range(len(cte_rows)):
                            var vals = List[Value]()
                            for c in range(len(cte_rows[r])):
                                vals.append(cte_rows[r][c].copy())
                            temp_btree.insert(Int64(r + 1), encode_record(vals))
                        self.tables.append(temp_btree^)

        # A. Constant Query without FROM table and without subquery in FROM
        if sel.table_name == "" and len(sel.from_subquery) == 0:
            var res_vals = List[Value]()
            for c in range(len(sel.columns)):
                var col = sel.columns[c]
                var v = eval_expr_row(col.expr, empty_row, List[String]())
                res_vals.append(v^)
                if col.col_alias != "":
                    out_col_names.append(col.col_alias)
                elif col.expr.kind == EXPR_COLUMN:
                    out_col_names.append(col.expr.col_name)
                elif col.expr.kind == EXPR_FUNC:
                    out_col_names.append(col.expr.func_name)
                else:
                    out_col_names.append("col_" + String(c))
            var row = Row(res_vals, out_col_names.copy())
            out_rows.append(row^)
            return

        # Check virtual sqlite_master / sqlite_schema
        var is_master = nocase_compare(sel.table_name, "sqlite_master") == 0 or nocase_compare(sel.table_name, "sqlite_schema") == 0
        var table_col_names = List[String]()
        var candidate_rows = List[Row]()

        if is_master:
            table_col_names.append("type")
            table_col_names.append("name")
            table_col_names.append("tbl_name")
            table_col_names.append("rootpage")
            table_col_names.append("sql")
            for t in range(len(self.schema.tables)):
                var tbl = self.schema.tables[t]
                var vals = List[Value]()
                vals.append(Value.of_text("table"))
                vals.append(Value.of_text(tbl.name))
                vals.append(Value.of_text(tbl.name))
                vals.append(Value.of_int(Int64(tbl.btree_idx + 1)))
                vals.append(Value.of_text("CREATE TABLE " + tbl.name))
                candidate_rows.append(Row(vals^, table_col_names.copy()))
            for i in range(len(self.schema.indices)):
                var idx = self.schema.indices[i]
                var vals = List[Value]()
                vals.append(Value.of_text("index"))
                vals.append(Value.of_text(idx.name))
                vals.append(Value.of_text(idx.table_name))
                vals.append(Value.of_int(Int64(idx.btree_idx + 1)))
                vals.append(Value.of_text("CREATE INDEX " + idx.name + " ON " + idx.table_name))
                candidate_rows.append(Row(vals^, table_col_names.copy()))
            for v in range(len(self.schema.views)):
                var view = self.schema.views[v]
                var vals = List[Value]()
                vals.append(Value.of_text("view"))
                vals.append(Value.of_text(view.name))
                vals.append(Value.of_text(view.name))
                vals.append(Value.of_int(0))
                vals.append(Value.of_text("CREATE VIEW " + view.name))
                candidate_rows.append(Row(vals^, table_col_names.copy()))
            for tr in range(len(self.schema.triggers)):
                var trg = self.schema.triggers[tr]
                var vals = List[Value]()
                vals.append(Value.of_text("trigger"))
                vals.append(Value.of_text(trg.name))
                vals.append(Value.of_text(trg.table_name))
                vals.append(Value.of_int(0))
                vals.append(Value.of_text("CREATE TRIGGER " + trg.name + " " + trg.action_sql))
                candidate_rows.append(Row(vals^, table_col_names.copy()))

        elif len(sel.from_subquery) > 0:
            # Derived table in FROM: FROM (SELECT ...) [AS alias]
            var sub_res_rows = List[Row]()
            var sub_res_cols = List[String]()
            self._execute_select_internal(sel.from_subquery[0].copy(), sub_res_rows, sub_res_cols)
            for c in range(len(sub_res_cols)):
                table_col_names.append(sub_res_cols[c])
            for r in range(len(sub_res_rows)):
                candidate_rows.append(sub_res_rows[r].copy())

        else:
            # Check if table is a View
            var view_opt = self.schema.find_view(sel.table_name)
            if view_opt:
                var v_tokens = tokenize_sql(view_opt.value().sql if view_opt.value().sql != "" else "SELECT * FROM " + sel.table_name)
                # If sql was not stored directly, execute view
            # B. Query over a Table (with optional JOINs)
            var tbl_opt = self.schema.find_table(sel.table_name)
            if not tbl_opt:
                raise Error("no such table: " + sel.table_name)
            var tbl_def = tbl_opt.value()
            var btree_idx = tbl_def.btree_idx

            var prefix = sel.table_alias if sel.table_alias != "" else sel.table_name
            for c in range(len(tbl_def.columns)):
                var cname = tbl_def.columns[c].name
                if len(sel.joins) > 0:
                    table_col_names.append(prefix + "." + cname)
                else:
                    table_col_names.append(cname)

            var n_cells = self.tables[btree_idx].cell_count()

            for i in range(n_cells):
                var cell = self.tables[btree_idx].get_cell(i)
                var raw_vals = decode_record(cell.payload)
                while len(raw_vals) < len(tbl_def.columns):
                    var c_idx = len(raw_vals)
                    if tbl_def.columns[c_idx].has_default:
                        raw_vals.append(tbl_def.columns[c_idx].default_value.copy())
                    else:
                        raw_vals.append(Value.of_null())
                var row = Row(raw_vals, table_col_names)
                candidate_rows.append(row^)

        # Process multi-table JOINs
        for j_idx in range(len(sel.joins)):
            var join_cl = sel.joins[j_idx]
            var j_tbl_opt = self.schema.find_table(join_cl.table_name)
            if not j_tbl_opt:
                raise Error("no such table: " + join_cl.table_name)
            var j_tbl_def = j_tbl_opt.value()
            var j_btree_idx = j_tbl_def.btree_idx

            var j_col_names = List[String]()
            var j_prefix = join_cl.table_alias if join_cl.table_alias != "" else join_cl.table_name
            for c in range(len(j_tbl_def.columns)):
                j_col_names.append(j_prefix + "." + j_tbl_def.columns[c].name)

            var new_table_col_names = table_col_names.copy()
            for c in range(len(j_col_names)):
                new_table_col_names.append(j_col_names[c])

            var j_rows = List[List[Value]]()
            var j_n_cells = self.tables[j_btree_idx].cell_count()
            for i in range(j_n_cells):
                var cell = self.tables[j_btree_idx].get_cell(i)
                var raw_vals = decode_record(cell.payload)
                while len(raw_vals) < len(j_tbl_def.columns):
                    var c_idx = len(raw_vals)
                    if j_tbl_def.columns[c_idx].has_default:
                        raw_vals.append(j_tbl_def.columns[c_idx].default_value.copy())
                    else:
                        raw_vals.append(Value.of_null())
                j_rows.append(raw_vals^)

            var next_candidates = List[Row]()
            for r1 in range(len(candidate_rows)):
                var row1 = candidate_rows[r1]
                var matched_any = False
                for r2 in range(len(j_rows)):
                    var row2_vals = j_rows[r2].copy()
                    var comb_vals = List[Value]()
                    for c in range(len(row1)):
                        comb_vals.append(row1[c].copy())
                    for c in range(len(row2_vals)):
                        comb_vals.append(row2_vals[c].copy())
                    var comb_row = Row(comb_vals^, new_table_col_names.copy())
                    var on_match = True
                    if len(join_cl.on_expr) > 0:
                        var on_res = eval_expr_row(join_cl.on_expr[0], comb_row, new_table_col_names)
                        if on_res.is_null() or on_res.to_int() == 0:
                            on_match = False
                    if on_match:
                        next_candidates.append(comb_row^)
                        matched_any = True
                if join_cl.join_type == JOIN_LEFT and not matched_any:
                    var comb_vals = List[Value]()
                    for c in range(len(row1)):
                        comb_vals.append(row1[c].copy())
                    for _ in range(len(j_col_names)):
                        comb_vals.append(Value.of_null())
                    var comb_row = Row(comb_vals^, new_table_col_names.copy())
                    next_candidates.append(comb_row^)

            candidate_rows = next_candidates^
            table_col_names = new_table_col_names^

        var alias_col_names = List[String]()
        var alias_exprs = List[Expr]()
        for c in range(len(sel.columns)):
            if sel.columns[c].col_alias != "":
                alias_col_names.append(sel.columns[c].col_alias)
                alias_exprs.append(sel.columns[c].expr.copy())

        # 1. Apply WHERE filter
        if len(local_where) > 0:
            var filtered_rows = List[Row]()
            for r in range(len(candidate_rows)):
                var row = candidate_rows[r]
                var w_res = eval_expr_row(local_where[0], row, table_col_names, alias_col_names, alias_exprs)
                if not w_res.is_null() and w_res.to_int() != 0:
                    filtered_rows.append(row^)
            candidate_rows = filtered_rows^

        # 2. Check for Aggregates
        var has_aggregate = False
        for c in range(len(sel.columns)):
            if sel.columns[c].expr.kind == EXPR_FUNC:
                var fn_name = sel.columns[c].expr.func_name
                if (
                    nocase_compare(fn_name, "COUNT") == 0
                    or nocase_compare(fn_name, "SUM") == 0
                    or nocase_compare(fn_name, "TOTAL") == 0
                    or nocase_compare(fn_name, "AVG") == 0
                    or nocase_compare(fn_name, "MIN") == 0
                    or nocase_compare(fn_name, "MAX") == 0
                    or nocase_compare(fn_name, "GROUP_CONCAT") == 0
                ):
                    has_aggregate = True
                    break

        if sel.is_star:
            out_col_names = table_col_names.copy()
        else:
            for c in range(len(sel.columns)):
                var col = sel.columns[c]
                if col.col_alias != "":
                    out_col_names.append(col.col_alias)
                elif col.expr.kind == EXPR_COLUMN:
                    out_col_names.append(col.expr.col_name)
                elif col.expr.kind == EXPR_FUNC:
                    out_col_names.append(col.expr.func_name)
                else:
                    out_col_names.append("col_" + String(c))

        if has_aggregate and len(sel.group_by) == 0:
            var agg_vals = List[Value]()
            for c in range(len(sel.columns)):
                var expr = sel.columns[c].expr
                if expr.kind == EXPR_FUNC:
                    var fn_name = expr.func_name
                    if nocase_compare(fn_name, "COUNT") == 0:
                        if len(expr.args) > 0 and expr.args[0].kind == EXPR_STAR:
                            agg_vals.append(Value.of_int(Int64(len(candidate_rows))))
                        elif len(expr.args) > 0:
                            if expr.op == "DISTINCT":
                                var dist_vals = List[String]()
                                for r in range(len(candidate_rows)):
                                    var v = eval_expr_row(expr.args[0], candidate_rows[r], table_col_names)
                                    if not v.is_null():
                                        var s_val = v.to_string()
                                        var exists = False
                                        for d in range(len(dist_vals)):
                                            if dist_vals[d] == s_val:
                                                exists = True
                                                break
                                        if not exists:
                                            dist_vals.append(s_val)
                                agg_vals.append(Value.of_int(Int64(len(dist_vals))))
                            else:
                                var cnt = 0
                                for r in range(len(candidate_rows)):
                                    var v = eval_expr_row(expr.args[0], candidate_rows[r], table_col_names)
                                    if not v.is_null():
                                        cnt += 1
                                agg_vals.append(Value.of_int(Int64(cnt)))
                        else:
                            agg_vals.append(Value.of_int(Int64(len(candidate_rows))))
                    elif nocase_compare(fn_name, "SUM") == 0:
                        if len(candidate_rows) == 0:
                            agg_vals.append(Value.of_null())
                        else:
                            var sum_f: Float64 = 0.0
                            for r in range(len(candidate_rows)):
                                var v = eval_expr_row(expr.args[0], candidate_rows[r], table_col_names)
                                if not v.is_null():
                                    sum_f += v.to_float()
                            agg_vals.append(Value.of_float(sum_f))
                    elif nocase_compare(fn_name, "TOTAL") == 0:
                        var tot_f: Float64 = 0.0
                        for r in range(len(candidate_rows)):
                            var v = eval_expr_row(expr.args[0], candidate_rows[r], table_col_names)
                            if not v.is_null():
                                tot_f += v.to_float()
                        agg_vals.append(Value.of_float(tot_f))
                    elif nocase_compare(fn_name, "AVG") == 0:
                        var sum_f: Float64 = 0.0
                        var count_non_null = 0
                        for r in range(len(candidate_rows)):
                            var v = eval_expr_row(expr.args[0], candidate_rows[r], table_col_names)
                            if not v.is_null():
                                sum_f += v.to_float()
                                count_non_null += 1
                        if count_non_null > 0:
                            agg_vals.append(Value.of_float(sum_f / Float64(count_non_null)))
                        else:
                            agg_vals.append(Value.of_null())
                    elif nocase_compare(fn_name, "MIN") == 0:
                        var min_f: Optional[Float64] = None
                        for r in range(len(candidate_rows)):
                            var v = eval_expr_row(expr.args[0], candidate_rows[r], table_col_names)
                            if not v.is_null():
                                var f = v.to_float()
                                if not min_f or f < min_f.value():
                                    min_f = Optional(f)
                        if min_f:
                            agg_vals.append(Value.of_float(min_f.value()))
                        else:
                            agg_vals.append(Value.of_null())
                    elif nocase_compare(fn_name, "MAX") == 0:
                        var max_f: Optional[Float64] = None
                        for r in range(len(candidate_rows)):
                            var v = eval_expr_row(expr.args[0], candidate_rows[r], table_col_names)
                            if not v.is_null():
                                var f = v.to_float()
                                if not max_f or f > max_f.value():
                                    max_f = Optional(f)
                        if max_f:
                            agg_vals.append(Value.of_float(max_f.value()))
                        else:
                            agg_vals.append(Value.of_null())
                    elif nocase_compare(fn_name, "GROUP_CONCAT") == 0:
                        var sep = ","
                        if len(expr.args) >= 2:
                            sep = eval_expr_row(expr.args[1], empty_row, List[String]()).to_string()
                        var g_str = String()
                        var first = True
                        for r in range(len(candidate_rows)):
                            var v = eval_expr_row(expr.args[0], candidate_rows[r], table_col_names)
                            if not v.is_null():
                                if not first:
                                    g_str += sep
                                g_str += v.to_string()
                                first = False
                        agg_vals.append(Value.of_text(g_str))
                else:
                    var v = eval_expr_row(expr, candidate_rows[0] if len(candidate_rows) > 0 else empty_row, table_col_names)
                    agg_vals.append(v^)

            out_rows.append(Row(agg_vals^, out_col_names.copy()))

        # 3. GROUP BY Processing
        elif len(sel.group_by) > 0:
            var groups = List[String]()
            var group_rows = List[List[Row]]()

            for r in range(len(candidate_rows)):
                var row = candidate_rows[r]
                var grp_key = String()
                for g in range(len(sel.group_by)):
                    var target_g = sel.group_by[g]
                    var col_idx = -1
                    for tc in range(len(table_col_names)):
                        if (
                            nocase_compare(table_col_names[tc], target_g) == 0
                            or table_col_names[tc].endswith("." + target_g)
                            or target_g.endswith("." + table_col_names[tc])
                        ):
                            col_idx = tc
                            break
                    if col_idx >= 0 and col_idx < len(row):
                        grp_key += row[col_idx].to_string()
                    grp_key += "§"
                var grp_idx = -1
                for g in range(len(groups)):
                    if groups[g] == grp_key:
                        grp_idx = g
                        break
                if grp_idx >= 0:
                    group_rows[grp_idx].append(row)
                else:
                    groups.append(grp_key)
                    var new_g = List[Row]()
                    new_g.append(row)
                    group_rows.append(new_g^)

            for g in range(len(group_rows)):
                var g_sub = group_rows[g].copy()
                var row_vals = List[Value]()
                for c in range(len(sel.columns)):
                    var expr = sel.columns[c].expr
                    if expr.kind == EXPR_FUNC:
                        var fn_name = expr.func_name
                        if nocase_compare(fn_name, "SUM") == 0 or nocase_compare(fn_name, "TOTAL") == 0:
                            var sum_f: Float64 = 0.0
                            for r in range(len(g_sub)):
                                if len(expr.args) > 0:
                                    var v = eval_expr_row(expr.args[0], g_sub[r], table_col_names)
                                    if not v.is_null():
                                        sum_f += v.to_float()
                            row_vals.append(Value.of_float(sum_f))
                        elif nocase_compare(fn_name, "COUNT") == 0:
                            if len(expr.args) > 0 and expr.args[0].kind != EXPR_STAR:
                                var cnt = 0
                                for r in range(len(g_sub)):
                                    var v = eval_expr_row(expr.args[0], g_sub[r], table_col_names)
                                    if not v.is_null():
                                        cnt += 1
                                row_vals.append(Value.of_int(Int64(cnt)))
                            else:
                                row_vals.append(Value.of_int(Int64(len(g_sub))))
                        elif nocase_compare(fn_name, "AVG") == 0:
                            var sum_f: Float64 = 0.0
                            var cnt = 0
                            for r in range(len(g_sub)):
                                if len(expr.args) > 0:
                                    var v = eval_expr_row(expr.args[0], g_sub[r], table_col_names)
                                    if not v.is_null():
                                        sum_f += v.to_float()
                                        cnt += 1
                            if cnt > 0:
                                row_vals.append(Value.of_float(sum_f / Float64(cnt)))
                            else:
                                row_vals.append(Value.of_null())
                        elif nocase_compare(fn_name, "MIN") == 0:
                            var min_f: Optional[Float64] = None
                            for r in range(len(g_sub)):
                                if len(expr.args) > 0:
                                    var v = eval_expr_row(expr.args[0], g_sub[r], table_col_names)
                                    if not v.is_null():
                                        var f = v.to_float()
                                        if not min_f or f < min_f.value():
                                            min_f = Optional(f)
                            if min_f:
                                row_vals.append(Value.of_float(min_f.value()))
                            else:
                                row_vals.append(Value.of_null())
                        elif nocase_compare(fn_name, "MAX") == 0:
                            var max_f: Optional[Float64] = None
                            for r in range(len(g_sub)):
                                if len(expr.args) > 0:
                                    var v = eval_expr_row(expr.args[0], g_sub[r], table_col_names)
                                    if not v.is_null():
                                        var f = v.to_float()
                                        if not max_f or f > max_f.value():
                                            max_f = Optional(f)
                            if max_f:
                                row_vals.append(Value.of_float(max_f.value()))
                            else:
                                row_vals.append(Value.of_null())
                        elif nocase_compare(fn_name, "GROUP_CONCAT") == 0:
                            var sep = ","
                            if len(expr.args) >= 2:
                                sep = eval_expr_row(expr.args[1], empty_row, List[String]()).to_string()
                            var g_str = String()
                            var first = True
                            for r in range(len(g_sub)):
                                if len(expr.args) > 0:
                                    var v = eval_expr_row(expr.args[0], g_sub[r], table_col_names)
                                    if not v.is_null():
                                        if not first:
                                            g_str += sep
                                        g_str += v.to_string()
                                        first = False
                            row_vals.append(Value.of_text(g_str))
                    else:
                        var v = eval_expr_row(expr, g_sub[0], table_col_names)
                        row_vals.append(v^)
                
                var out_row = Row(row_vals^, out_col_names.copy())
                var pass_having = True
                if len(sel.having_expr) > 0:
                    var h_res = eval_expr_row(sel.having_expr[0], out_row, out_col_names)
                    if h_res.is_null() or h_res.to_int() == 0:
                        pass_having = False
                if pass_having:
                    out_rows.append(out_row^)

            # Sort aggregated groups if ORDER BY is present
            if len(sel.order_by) > 0 and len(out_rows) > 1:
                var order_expr = sel.order_by[0]
                var is_desc = order_expr.is_desc
                var n = len(out_rows)
                for i in range(n):
                    for j in range(0, n - i - 1):
                        var v1 = eval_expr_row(order_expr, out_rows[j], out_col_names)
                        var v2 = eval_expr_row(order_expr, out_rows[j + 1], out_col_names)
                        var swap = False
                        if v1.is_null() and not v2.is_null():
                            swap = is_desc
                        elif not v1.is_null() and v2.is_null():
                            swap = not is_desc
                        elif not v1.is_null() and not v2.is_null():
                            if is_desc:
                                if v1.type_tag == SQLITE_TEXT and v2.type_tag == SQLITE_TEXT:
                                    swap = v1.text_val < v2.text_val
                                else:
                                    swap = v1.to_float() < v2.to_float()
                            else:
                                if v1.type_tag == SQLITE_TEXT and v2.type_tag == SQLITE_TEXT:
                                    swap = v1.text_val > v2.text_val
                                else:
                                    swap = v1.to_float() > v2.to_float()
                        if swap:
                            var tmp = out_rows[j].copy()
                            out_rows[j] = out_rows[j + 1].copy()
                            out_rows[j + 1] = tmp^

        # 4. Standard Row-by-Row Projection (with ORDER BY sorting beforehand)
        else:
            # Sort candidate rows before projection
            if len(sel.order_by) > 0 and len(candidate_rows) > 1:
                var n = len(candidate_rows)
                for i in range(n):
                    for j in range(0, n - i - 1):
                        var swap = False
                        for o in range(len(sel.order_by)):
                            var order_expr = sel.order_by[o]
                            var is_desc = order_expr.is_desc
                            var v1 = eval_expr_row(order_expr, candidate_rows[j], table_col_names, alias_col_names, alias_exprs)
                            var v2 = eval_expr_row(order_expr, candidate_rows[j + 1], table_col_names, alias_col_names, alias_exprs)
                            if v1.is_null() and not v2.is_null():
                                swap = is_desc
                                break
                            elif not v1.is_null() and v2.is_null():
                                swap = not is_desc
                                break
                            elif not v1.is_null() and not v2.is_null():
                                if v1.type_tag == SQLITE_TEXT and v2.type_tag == SQLITE_TEXT:
                                    if v1.text_val != v2.text_val:
                                        swap = (v1.text_val < v2.text_val) if is_desc else (v1.text_val > v2.text_val)
                                        break
                                else:
                                    if v1.to_float() != v2.to_float():
                                        swap = (v1.to_float() < v2.to_float()) if is_desc else (v1.to_float() > v2.to_float())
                                        break
                        if swap:
                            var tmp = candidate_rows[j].copy()
                            candidate_rows[j] = candidate_rows[j + 1].copy()
                            candidate_rows[j + 1] = tmp^

            for r in range(len(candidate_rows)):
                var row = candidate_rows[r]
                var row_vals = List[Value]()
                if sel.is_star:
                    for c in range(len(row)):
                        row_vals.append(row[c].copy())
                else:
                    for c in range(len(sel.columns)):
                        var col = sel.columns[c]
                        if col.expr.is_window and len(col.expr.window_spec) > 0:
                            var w_spec = col.expr.window_spec[0]
                            var fn_name = col.expr.func_name
                            
                            # Determine partition boundaries for candidate_rows[r]
                            var p_start = 0
                            var p_end = len(candidate_rows)
                            if len(w_spec.partition_by) > 0:
                                var p_expr = w_spec.partition_by[0]
                                var cur_p_val = eval_expr_row(p_expr, row, table_col_names)
                                while p_start < r:
                                    var v_start = eval_expr_row(p_expr, candidate_rows[p_start], table_col_names)
                                    if v_start.to_string() == cur_p_val.to_string():
                                        break
                                    p_start += 1
                                p_end = p_start
                                while p_end < len(candidate_rows):
                                    var v_end = eval_expr_row(p_expr, candidate_rows[p_end], table_col_names)
                                    if v_end.to_string() != cur_p_val.to_string():
                                        break
                                    p_end += 1

                            var row_offset_in_p = r - p_start
                            if nocase_compare(fn_name, "ROW_NUMBER") == 0:
                                row_vals.append(Value.of_int(Int64(row_offset_in_p + 1)))
                            elif nocase_compare(fn_name, "RANK") == 0 or nocase_compare(fn_name, "DENSE_RANK") == 0:
                                row_vals.append(Value.of_int(Int64(row_offset_in_p + 1)))
                            elif nocase_compare(fn_name, "LEAD") == 0:
                                var lead_offset = 1
                                if len(col.expr.args) > 1:
                                    var off_v = eval_expr_row(col.expr.args[1], row, table_col_names)
                                    lead_offset = Int(off_v.to_int())
                                var target_r = r + lead_offset
                                if target_r < p_end and len(col.expr.args) > 0:
                                    var lv = eval_expr_row(col.expr.args[0], candidate_rows[target_r], table_col_names)
                                    row_vals.append(lv^)
                                else:
                                    row_vals.append(Value.of_null())
                            elif nocase_compare(fn_name, "LAG") == 0:
                                var lag_offset = 1
                                if len(col.expr.args) > 1:
                                    var off_v = eval_expr_row(col.expr.args[1], row, table_col_names)
                                    lag_offset = Int(off_v.to_int())
                                var target_r = r - lag_offset
                                if target_r >= p_start and len(col.expr.args) > 0:
                                    var lv = eval_expr_row(col.expr.args[0], candidate_rows[target_r], table_col_names)
                                    row_vals.append(lv^)
                                else:
                                    row_vals.append(Value.of_null())
                            else:
                                row_vals.append(Value.of_int(Int64(row_offset_in_p + 1)))
                        else:
                            var v = eval_expr_row(col.expr, row, table_col_names)
                            row_vals.append(v^)
                out_rows.append(Row(row_vals^, out_col_names.copy()))

        # 5. DISTINCT
        if sel.is_distinct and len(out_rows) > 1:
            var distinct_rows = List[Row]()
            for i in range(len(out_rows)):
                var exists = False
                for j in range(len(distinct_rows)):
                    var match_r = True
                    if len(out_rows[i]) != len(distinct_rows[j]):
                        match_r = False
                    else:
                        for k in range(len(out_rows[i])):
                            if out_rows[i][k].to_string() != distinct_rows[j][k].to_string():
                                match_r = False
                                break
                    if match_r:
                        exists = True
                        break
                if not exists:
                    distinct_rows.append(out_rows[i].copy())
            out_rows = distinct_rows^

        # 6. LIMIT and OFFSET
        if sel.limit_val >= 0 or sel.offset_val > 0:
            var sliced_rows = List[Row]()
            var start = sel.offset_val
            var count = sel.limit_val
            var n = len(out_rows)
            for i in range(start, n):
                if count >= 0 and len(sliced_rows) >= count:
                    break
                sliced_rows.append(out_rows[i].copy())
            out_rows = sliced_rows^

        # 7. Compound Operations (UNION, UNION ALL, INTERSECT, EXCEPT)
        if sel.compound_op != COMPOUND_NONE and len(sel.compound_next) > 0:
            var next_rows = List[Row]()
            var next_cols = List[String]()
            self._execute_select_internal(sel.compound_next[0].copy(), next_rows, next_cols)

            if sel.compound_op == COMPOUND_UNION:
                for r in range(len(next_rows)):
                    out_rows.append(next_rows[r].copy())
                # Deduplicate
                var dist_rows = List[Row]()
                for i in range(len(out_rows)):
                    var exists = False
                    for j in range(len(dist_rows)):
                        var match_r = True
                        if len(out_rows[i]) != len(dist_rows[j]):
                            match_r = False
                        else:
                            for k in range(len(out_rows[i])):
                                if out_rows[i][k].to_string() != dist_rows[j][k].to_string():
                                    match_r = False
                                    break
                        if match_r:
                            exists = True
                            break
                    if not exists:
                        dist_rows.append(out_rows[i].copy())
                out_rows = dist_rows^

            elif sel.compound_op == COMPOUND_UNION_ALL:
                for r in range(len(next_rows)):
                    out_rows.append(next_rows[r].copy())

            elif sel.compound_op == COMPOUND_INTERSECT:
                var inter_rows = List[Row]()
                for i in range(len(out_rows)):
                    var in_next = False
                    for j in range(len(next_rows)):
                        var match_r = True
                        if len(out_rows[i]) != len(next_rows[j]):
                            match_r = False
                        else:
                            for k in range(len(out_rows[i])):
                                if out_rows[i][k].to_string() != next_rows[j][k].to_string():
                                    match_r = False
                                    break
                        if match_r:
                            in_next = True
                            break
                    if in_next:
                        var exists = False
                        for k in range(len(inter_rows)):
                            if inter_rows[k][0].to_string() == out_rows[i][0].to_string():
                                exists = True
                                break
                        if not exists:
                            inter_rows.append(out_rows[i].copy())
                out_rows = inter_rows^

            elif sel.compound_op == COMPOUND_EXCEPT:
                var except_rows = List[Row]()
                for i in range(len(out_rows)):
                    var in_next = False
                    for j in range(len(next_rows)):
                        var match_r = True
                        if len(out_rows[i]) != len(next_rows[j]):
                            match_r = False
                        else:
                            for k in range(len(out_rows[i])):
                                if out_rows[i][k].to_string() != next_rows[j][k].to_string():
                                    match_r = False
                                    break
                        if match_r:
                            in_next = True
                            break
                    if not in_next:
                        except_rows.append(out_rows[i].copy())
                out_rows = except_rows^

    def commit(mut self) raises:
        self.autocommit_mode = True
        self.tx_snapshot = List[MemBTree]()
        self._save_to_disk()

    def rollback(mut self) raises:
        if len(self.tx_snapshot) > 0:
            self.tables = self.tx_snapshot.copy()
        self.autocommit_mode = True

    def changes(self) -> Int:
        return self.change_count

    def total_changes(self) -> Int:
        return self.total_change_count

    def last_insert_rowid(self) -> Int64:
        return self.last_rowid

    def autocommit(self) -> Bool:
        return self.autocommit_mode

    def close(mut self):
        try:
            self._save_to_disk()
        except:
            pass
        self.tables = List[MemBTree]()
        self.savepoints = List[SavepointSnapshot]()
        self.tx_snapshot = List[MemBTree]()


def connect(database: String = ":memory:") raises -> Connection:
    return Connection(database)
