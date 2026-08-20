""" SQLean: SQLite Engine & Pythonic Database Interface in Mojo.

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

from src.types import *
from src.c_api import *
from src.error import check_rc, check_rc_stmt
from src.row import Value, Row
from src.cursor import Cursor
from src.connection import Connection, connect
from src.varint import put_varint, get_varint, get_varint32, put_varint32, get_varint_value, encode_varint, decode_varint
from src.utf import read_utf8, write_utf8, utf8_char_length, nocase_compare
from src.hash import str_hash
from src.bitvec import BitVec
from src.serial import serial_type_len, get_serial_type, encode_value, decode_value
from src.record import encode_record, decode_record
from src.page_header import DbHeader, PageHeader, PAGE_TYPE_INTERIOR_INDEX, PAGE_TYPE_INTERIOR_TABLE, PAGE_TYPE_LEAF_INDEX, PAGE_TYPE_LEAF_TABLE, read_cell_pointer, write_cell_pointer
from src.vfs import VFS, MemFile, DiskFile, NO_LOCK, SHARED_LOCK, RESERVED_LOCK, PENDING_LOCK, EXCLUSIVE_LOCK
from src.journal import Journal, JournalRecord, JOURNAL_MODE_DELETE, JOURNAL_MODE_PERSIST, JOURNAL_MODE_OFF, JOURNAL_MODE_TRUNCATE, JOURNAL_MODE_MEMORY
from src.pager import Pager, DbPage, PCache, PAGER_OPEN, PAGER_READER, PAGER_WRITER_LOCKED, PAGER_WRITER_CACHED, PAGER_WRITER_DBMOD
from src.btree_cell import TableLeafCell, TableInteriorCell
from src.btree import MemBTree, BTreeCursor
from src.opcode import *
from src.vdbe import Vdbe, VDBE_RESULT_ROW, VDBE_RESULT_DONE, VDBE_RESULT_ERROR
from src.uast import UASTNode, UASTPool, UAST_PROGRAM, UAST_NAME, UAST_LITERAL_NUM, UAST_LITERAL_STR, UAST_SQL_SELECT, UAST_SQL_INSERT, UAST_SQL_WHERE, UAST_SQL_FROM
from src.tokenizer import Token, tokenize_sql
from src.parser import SelectStmt, parse_select, compile_select_to_vdbe
from src.optimizer import QueryPlan, PLAN_FULL_SCAN, PLAN_ROWID_SEEK, optimize_where_clause, compile_optimized_select
