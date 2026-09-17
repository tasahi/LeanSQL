""" SQLite Database Schema Catalog and Metadata.

Corresponds to `sqlite/src/schema.c` and `sqlite/src/build.c`.

Maintains schema definitions for tables, columns, indexes, and primary keys.
"""

from src.core.types import *
from src.engine.row import Value
from src.core.utf import nocase_compare


struct ColumnDef(ImplicitlyCopyable, Copyable, Movable):
    """ Represents a column definition within a database table."""
    var name: String
    var type_affinity: Int
    var is_primary_key: Bool
    var has_default: Bool
    var default_value: Value
    var not_null: Bool

    def __init__( out self, name: String, type_affinity: Int = SQLITE_TEXT,
            is_primary_key: Bool = False, has_default: Bool = False,
            default_value: Value = Value.of_null(), not_null: Bool = False ):
        self.name = name
        self.type_affinity = type_affinity
        self.is_primary_key = is_primary_key
        self.has_default = has_default
        self.default_value = default_value.copy()
        self.not_null = not_null

    def __init__(out self, *, copy: Self):
        self.name = copy.name
        self.type_affinity = copy.type_affinity
        self.is_primary_key = copy.is_primary_key
        self.has_default = copy.has_default
        self.default_value = copy.default_value.copy()
        self.not_null = copy.not_null

    def __init__(out self, *, deinit move: Self):
        self.name = move.name^
        self.type_affinity = move.type_affinity
        self.is_primary_key = move.is_primary_key
        self.has_default = move.has_default
        self.default_value = move.default_value^
        self.not_null = move.not_null


struct TableDef(ImplicitlyCopyable, Copyable, Movable):
    """ Represents a database table structure."""
    var name: String
    var columns: List[ColumnDef]
    var btree_idx: Int
    var auto_rowid: Int64
    var is_virtual: Bool
    var virtual_module: String
    var virtual_args: String

    def __init__(out self, name: String, btree_idx: Int, is_virtual: Bool = False,
            virtual_module: String = "", virtual_args: String = ""):
        self.name = name
        self.columns = List[ColumnDef]()
        self.btree_idx = btree_idx
        self.auto_rowid = 1
        self.is_virtual = is_virtual
        self.virtual_module = virtual_module
        self.virtual_args = virtual_args

    def __init__(out self, *, copy: Self):
        self.name = copy.name
        self.columns = copy.columns.copy()
        self.btree_idx = copy.btree_idx
        self.auto_rowid = copy.auto_rowid
        self.is_virtual = copy.is_virtual
        self.virtual_module = copy.virtual_module
        self.virtual_args = copy.virtual_args

    def __init__(out self, *, deinit move: Self):
        self.name = move.name^
        self.columns = move.columns^
        self.btree_idx = move.btree_idx
        self.auto_rowid = move.auto_rowid
        self.is_virtual = move.is_virtual
        self.virtual_module = move.virtual_module^
        self.virtual_args = move.virtual_args^

    def add_column(mut self, col: ColumnDef):
        self.columns.append(col)

    def find_column_index(self, col_name: String) -> Int:
        """ Returns the 0-indexed position of column `col_name`, or -1 if not found."""
        for i in range(len(self.columns)):
            if nocase_compare(self.columns[i].name, col_name) == 0:
                return i
        return -1

    def primary_key_col_index(self) -> Int:
        """ Returns the 0-indexed position of the PRIMARY KEY column, or -1."""
        for i in range(len(self.columns)):
            if self.columns[i].is_primary_key:
                return i
        return -1

    def to_sql(self) -> String:
        """ Reconstructs the canonical CREATE TABLE DDL string."""
        var s = "CREATE TABLE " + self.name + " ("
        for i in range(len(self.columns)):
            if i > 0:
                s += ", "
            s += self.columns[i].name
            var aff = self.columns[i].type_affinity
            if aff == SQLITE_INTEGER:
                s += " INT"
            elif aff == SQLITE_FLOAT:
                s += " REAL"
            elif aff == SQLITE_BLOB:
                s += " BLOB"
            else:
                s += " TEXT"
            if self.columns[i].is_primary_key:
                s += " PRIMARY KEY"
        s += ")"
        return s


struct IndexDef(ImplicitlyCopyable, Copyable, Movable):
    """ Represents a secondary index defined on a table."""
    var name: String
    var table_name: String
    var columns: List[String]
    var is_unique: Bool
    var btree_idx: Int

    def __init__(out self, name: String, table_name: String, is_unique: Bool, btree_idx: Int):
        self.name = name
        self.table_name = table_name
        self.columns = List[String]()
        self.is_unique = is_unique
        self.btree_idx = btree_idx

    def __init__(out self, *, copy: Self):
        self.name = copy.name
        self.table_name = copy.table_name
        self.columns = copy.columns.copy()
        self.is_unique = copy.is_unique
        self.btree_idx = copy.btree_idx

    def __init__(out self, *, deinit move: Self):
        self.name = move.name^
        self.table_name = move.table_name^
        self.columns = move.columns^
        self.is_unique = move.is_unique
        self.btree_idx = move.btree_idx


struct ViewDef(ImplicitlyCopyable, Copyable, Movable):
    var name: String
    var sql: String

    def __init__(out self, name: String, sql: String):
        self.name = name
        self.sql = sql

    def __init__(out self, *, copy: Self):
        self.name = copy.name
        self.sql = copy.sql

    def __init__(out self, *, deinit move: Self):
        self.name = move.name^
        self.sql = move.sql^


struct SchemaCatalog(ImplicitlyCopyable, Copyable, Movable):
    """ Central metadata catalog for all tables, indexes, and views in a database."""
    var tables: List[TableDef]
    var indices: List[IndexDef]
    var views: List[ViewDef]
    var triggers: List[TriggerDef]
    var user_version: Int64

    def __init__(out self):
        self.tables = List[TableDef]()
        self.indices = List[IndexDef]()
        self.views = List[ViewDef]()
        self.triggers = List[TriggerDef]()
        self.user_version = 0

    def __init__(out self, *, copy: Self):
        self.tables = copy.tables.copy()
        self.indices = copy.indices.copy()
        self.views = copy.views.copy()
        self.triggers = copy.triggers.copy()
        self.user_version = copy.user_version

    def __init__(out self, *, deinit move: Self):
        self.tables = move.tables^
        self.indices = move.indices^
        self.views = move.views^
        self.triggers = move.triggers^
        self.user_version = move.user_version

    def add_table(mut self, table: TableDef):
        self.tables.append(table)

    def find_table(self, name: String) -> Optional[TableDef]:
        for i in range(len(self.tables)):
            if nocase_compare(self.tables[i].name, name) == 0:
                return Optional(self.tables[i].copy())
        return None

    def find_table_index(self, name: String) -> Int:
        for i in range(len(self.tables)):
            if nocase_compare(self.tables[i].name, name) == 0:
                return i
        return -1

    def drop_table(mut self, name: String) -> Bool:
        var idx = self.find_table_index(name)
        if idx >= 0:
            var new_tables = List[TableDef]()
            for i in range(len(self.tables)):
                if i != idx:
                    new_tables.append(self.tables[i].copy())
            self.tables = new_tables^
            return True
        return False

    def rename_table(mut self, old_name: String, new_name: String) -> Bool:
        var idx = self.find_table_index(old_name)
        if idx >= 0:
            self.tables[idx].name = new_name
            for i in range(len(self.indices)):
                if nocase_compare(self.indices[i].table_name, old_name) == 0:
                    self.indices[i].table_name = new_name
            return True
        return False

    def add_column_to_table(mut self, table_name: String, column: ColumnDef) -> Bool:
        var idx = self.find_table_index(table_name)
        if idx >= 0:
            self.tables[idx].add_column(column)
            return True
        return False

    def rename_column(mut self, table_name: String, old_name: String, new_name: String) -> Bool:
        var idx = self.find_table_index(table_name)
        if idx >= 0:
            for c in range(len(self.tables[idx].columns)):
                if nocase_compare(self.tables[idx].columns[c].name, old_name) == 0:
                    self.tables[idx].columns[c].name = new_name
                    return True
        return False

    def add_index(mut self, idx_def: IndexDef):
        self.indices.append(idx_def)

    def find_index(self, name: String) -> Optional[IndexDef]:
        for i in range(len(self.indices)):
            if nocase_compare(self.indices[i].name, name) == 0:
                return Optional(self.indices[i].copy())
        return None

    def drop_index(mut self, name: String) -> Bool:
        var idx = -1
        for i in range(len(self.indices)):
            if nocase_compare(self.indices[i].name, name) == 0:
                idx = i
                break
        if idx >= 0:
            var new_indices = List[IndexDef]()
            for i in range(len(self.indices)):
                if i != idx:
                    new_indices.append(self.indices[i].copy())
            self.indices = new_indices^
            return True
        return False

    def add_view(mut self, view: ViewDef):
        self.views.append(view)

    def find_view(self, name: String) -> Optional[ViewDef]:
        for i in range(len(self.views)):
            if nocase_compare(self.views[i].name, name) == 0:
                return Optional(self.views[i].copy())
        return None

    def drop_view(mut self, name: String) -> Bool:
        var idx = -1
        for i in range(len(self.views)):
            if nocase_compare(self.views[i].name, name) == 0:
                idx = i
                break
        if idx >= 0:
            var new_views = List[ViewDef]()
            for i in range(len(self.views)):
                if i != idx:
                    new_views.append(self.views[i].copy())
            self.views = new_views^
            return True
        return False

    def add_trigger(mut self, trg: TriggerDef):
        self.triggers.append(trg)

    def find_trigger(self, name: String) -> Optional[TriggerDef]:
        for i in range(len(self.triggers)):
            if nocase_compare(self.triggers[i].name, name) == 0:
                return Optional(self.triggers[i].copy())
        return None

    def drop_trigger(mut self, name: String) -> Bool:
        var idx = -1
        for i in range(len(self.triggers)):
            if nocase_compare(self.triggers[i].name, name) == 0:
                idx = i
                break
        if idx >= 0:
            var new_trgs = List[TriggerDef]()
            for i in range(len(self.triggers)):
                if i != idx:
                    new_trgs.append(self.triggers[i].copy())
            self.triggers = new_trgs^
            return True
        return False

    def find_triggers_for_table(self, table_name: String, timing: Int, event_type: Int) -> List[TriggerDef]:
        var res = List[TriggerDef]()
        for i in range(len(self.triggers)):
            var trg = self.triggers[i]
            if nocase_compare(trg.table_name, table_name) == 0 and trg.timing == timing and trg.event_type == event_type:
                res.append(trg.copy())
        return res^


comptime TRIGGER_BEFORE = 1
comptime TRIGGER_AFTER = 2
comptime TRIGGER_EVENT_INSERT = 1
comptime TRIGGER_EVENT_UPDATE = 2
comptime TRIGGER_EVENT_DELETE = 3


struct TriggerDef(ImplicitlyCopyable, Copyable, Movable):
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
