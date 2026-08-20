""" Python C Extension Module for SQLean.

Allows SQLean to be compiled into a native `.so` Python extension module
exporting `PyInit_sqlean` and callable from standard Python scripts via `import sqlean`.
"""

from std.ffi import external_call
from std.memory import Pointer
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from src.types import MutAnyOrigin
from src.connection import connect, Connection
from src.row import Value, Row


def parse_handle_address(obj: PythonObject) -> Int:
    """Parses a pointer address from integer or string PythonObject."""
    var s = String(obj)
    var b = s.as_bytes()
    if len(b) == 0:
        return 0
    for i in range(len(b)):
        if b[i] < 48 or b[i] > 57:
            return 0
    var num = 0
    for i in range(len(b)):
        num = num * 10 + Int(b[i] - 48)
    return num


def sqlean_version() raises -> PythonObject:
    """ Returns the version of SQLean."""
    return PythonObject("SQLean 0.1.0 (Mojo + SQLite Engine)")


def sqlean_open(path_obj: PythonObject) raises -> PythonObject:
    """ Opens a persistent database connection and returns an address handle."""
    var path_str = String(path_obj)
    var p = external_call["malloc", Pointer[Connection, MutAnyOrigin], Int](4096)
    var c = connect(path_str)
    p.unsafe_write(c^)
    var addr = Int(p)
    return PythonObject(addr)


def sqlean_execute(target_obj: PythonObject, sql_obj: PythonObject) raises -> PythonObject:
    """ Executes DDL/DML statement on handle or path."""
    var sql_str = String(sql_obj)
    var addr = parse_handle_address(target_obj)

    if addr != 0:
        var p = Pointer[Connection, MutAnyOrigin](unsafe_from_address=addr)
        var cur = p[].cursor()
        cur.execute(sql_str)
        p[].commit()
        return PythonObject(True)
    else:
        var path_str = String(target_obj)
        var con = connect(path_str)
        var cur = con.cursor()
        cur.execute(sql_str)
        con.commit()
        con.close()
        return PythonObject(True)


def sqlean_fetch_all(target_obj: PythonObject, sql_obj: PythonObject) raises -> PythonObject:
    """ Executes query and returns Python list of tuples."""
    var sql_str = String(sql_obj)
    var addr = parse_handle_address(target_obj)

    var rows = List[Row]()
    if addr != 0:
        var p = Pointer[Connection, MutAnyOrigin](unsafe_from_address=addr)
        var cur = p[].cursor()
        cur.execute(sql_str)
        rows = cur.fetchall()
    else:
        var path_str = String(target_obj)
        var con = connect(path_str)
        var cur = con.cursor()
        cur.execute(sql_str)
        rows = cur.fetchall()
        con.close()

    var py_list = Python.evaluate("[]")
    for r_idx in range(len(rows)):
        var row = rows[r_idx]
        var py_row = Python.evaluate("[]")
        for c_idx in range(len(row)):
            if row.is_null(c_idx):
                py_row.append(Python.evaluate("None"))
            elif row.values[c_idx].type_tag == 1: # SQLITE_INTEGER
                py_row.append(PythonObject(row.values[c_idx].to_int()))
            elif row.values[c_idx].type_tag == 2: # SQLITE_FLOAT
                py_row.append(PythonObject(row.values[c_idx].to_float()))
            else:
                py_row.append(PythonObject(row.values[c_idx].to_string()))
        py_list.append(Python.evaluate("tuple")(py_row))

    return py_list


def sqlean_commit(target_obj: PythonObject) raises -> PythonObject:
    """ Commits active transaction."""
    var addr = parse_handle_address(target_obj)
    if addr != 0:
        var p = Pointer[Connection, MutAnyOrigin](unsafe_from_address=addr)
        p[].commit()
    return PythonObject(True)


def sqlean_close(target_obj: PythonObject) raises -> PythonObject:
    """ Closes connection handle."""
    var addr = parse_handle_address(target_obj)
    if addr != 0:
        var p = Pointer[Connection, MutAnyOrigin](unsafe_from_address=addr)
        p[].close()
        p.unsafe_deinit_pointee()
        _ = external_call["free", NoneType, Pointer[Connection, MutAnyOrigin]](p)
    return PythonObject(True)


@export
def PyInit_sqlean() abi("C") -> PythonObject:
    """ Initializes the native Python C-extension module 'sqlean'."""
    try:
        var mb = PythonModuleBuilder("sqlean")
        mb.def_function[sqlean_version]("version", "Returns SQLean version string")
        mb.def_function[sqlean_open]("open", "Opens a connection and returns handle")
        mb.def_function[sqlean_execute]("execute", "Executes SQL DDL/DML statement")
        mb.def_function[sqlean_fetch_all]("fetch_all", "Executes SQL query and returns Python list of tuples")
        mb.def_function[sqlean_commit]("commit", "Commits active transaction")
        mb.def_function[sqlean_close]("close", "Closes connection handle")
        return mb.finalize()
    except:
        return PythonObject()
