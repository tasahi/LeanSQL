""" LeanSQL: SQLite Engine & Pythonic Database Interface in Mojo.

Provides:
- High-level Pythonic client API (`connect`, `Connection`, `Cursor`, `Row`, `Value`)
- Low-level pure Mojo primitives (`varint`, `utf`, `hash`, `bitvec`)
- Storage Serialization (`serial`, `record`, `page_header`)
- OS VFS & Pager Subsystems (`vfs`, `journal`, `pager`)
- B-Tree Engine & Cursors (`btree_cell`, `btree`)
- VDBE Virtual Machine & Instruction Dispatch (`opcode`, `vdbe`)
- Universal AST Integration & SQL Lexer/Parser (`uast`, `tokenizer`, `parser`)
- Query Optimizer & WhereScan Planner (`optimizer`)
- Direct zero-overhead C-FFI bindings (`c_api`, `types`, `error`)
"""

# Core
from src.core.types import *
from src.core.error import check_rc, check_rc_stmt
from src.core.varint import put_varint, get_varint, get_varint32, put_varint32, get_varint_value, encode_varint, decode_varint
from src.core.utf import read_utf8, write_utf8, utf8_char_length, nocase_compare
from src.core.hash import str_hash
from src.core.bitvec import BitVec

# Storage
from src.storage.serial import serial_type_len, get_serial_type, encode_value, decode_value
from src.storage.record import encode_record, decode_record
from src.storage.page_header import DbHeader, PageHeader, PAGE_TYPE_INTERIOR_INDEX, PAGE_TYPE_INTERIOR_TABLE, PAGE_TYPE_LEAF_INDEX, PAGE_TYPE_LEAF_TABLE, read_cell_pointer, write_cell_pointer
from src.storage.btree_cell import TableLeafCell, TableInteriorCell
from src.storage.btree import MemBTree, BTreeCursor

# VFS
from src.vfs.vfs_os import VFS, MemFile, DiskFile, NO_LOCK, SHARED_LOCK, RESERVED_LOCK, PENDING_LOCK, EXCLUSIVE_LOCK
from src.vfs.journal import Journal, JournalRecord, JOURNAL_MODE_DELETE, JOURNAL_MODE_PERSIST, JOURNAL_MODE_OFF, JOURNAL_MODE_TRUNCATE, JOURNAL_MODE_MEMORY
from src.vfs.pager import Pager, DbPage, PCache, PAGER_OPEN, PAGER_READER, PAGER_WRITER_LOCKED, PAGER_WRITER_CACHED, PAGER_WRITER_DBMOD

# VDBE
from src.vdbe.opcode import *
from src.vdbe.vm import Vdbe, VDBE_RESULT_ROW, VDBE_RESULT_DONE, VDBE_RESULT_ERROR

# SQL
from src.sql.uast import UASTNode, UASTPool, UAST_PROGRAM, UAST_NAME, UAST_LITERAL_NUM, UAST_LITERAL_STR, UAST_SQL_SELECT, UAST_SQL_INSERT, UAST_SQL_WHERE, UAST_SQL_FROM
from src.sql.tokenizer import Token, tokenize_sql
from src.sql.parser import SelectStmt, parse_select
from src.sql.optimizer import QueryPlan, PLAN_FULL_SCAN, PLAN_ROWID_SEEK, optimize_where_clause, compile_optimized_select

# Engine
from src.engine.row import Value, Row
from src.engine.cursor import Cursor
from src.engine.connection import Connection, connect

# Ext
from src.ext.json import JsonValue, parse_json, sql_json_extract, sql_json_array_length, sql_json_type, sql_json_valid

# Interop
from src.interop.c_api import *
