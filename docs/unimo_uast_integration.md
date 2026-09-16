---
type: specification
title: "Universal Abstract Syntax Tree (UAST) Integration & Specification"
description: "Specification defining the mapping between LeanSQL's AST tokens and the Unimo unified multi-language abstract syntax tree representations."
tags:
  - mojo
  - sqlite
  - uast
  - unimo
  - parser
  - ast
version: "1.0"
last_updated: "2026-09-16"
status: active
---

# Universal Abstract Syntax Tree (UAST) Integration & Specification

This document describes the alignment between **LeanSQL** and the **Unimo** (`unimo`) unified multi-language abstract syntax tree project.

---

## 1. Tag & Token Mapping to Unimo

LeanSQL adopts Unimo's Universal AST node representation (`UASTNode`, `UASTPool`) without altering Unimo's existing source code. Where applicable, standard programming language concepts reuse Unimo's core AST tags, while database/SQL-domain constructs are mapped into reserved extension tags ($100..112$):

| Construct | LeanSQL Token Symbol | Unimo AST Equivalent Tag | Numeric Value | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Identifier / Column Name** | `TK_ID` | `UAST_NAME` | `11` | Variable / column / table name identifier |
| **Integer Literal** | `TK_INTEGER` | `UAST_LITERAL_NUM` | `15` | Numeric constant |
| **String Literal** | `TK_STRING` | `UAST_LITERAL_STR` | `13` | String constant |
| **SELECT Query** | `TK_SELECT` | `UAST_SQL_SELECT` | `100` | Extended SQL root SELECT statement |
| **INSERT Query** | `TK_INSERT` | `UAST_SQL_INSERT` | `101` | Extended SQL INSERT statement |
| **UPDATE Query** | `TK_UPDATE` | `UAST_SQL_UPDATE` | `102` | Extended SQL UPDATE statement |
| **DELETE Query** | `TK_DELETE` | `UAST_SQL_DELETE` | `103` | Extended SQL DELETE statement |
| **CREATE TABLE** | `TK_CREATE` | `UAST_SQL_CREATE_TABLE` | `104` | Extended SQL DDL table definition |
| **Column Projection** | `TK_COLUMN` | `UAST_SQL_COLUMN_LIST` | `105` | Projection expressions |
| **FROM Target** | `TK_FROM` | `UAST_SQL_FROM` | `107` | Target table name / subquery |
| **WHERE Clause** | `TK_WHERE` | `UAST_SQL_WHERE` | `108` | Filter predicate tree |
| **Wildcard Projection** | `TK_STAR` | `UAST_SQL_STAR` | `110` | Asterisk (`*`) all-columns projection |

---

## 2. UAST Structure & Pool Memory Management

In LeanSQL, AST trees can be serialized into a flat `UASTPool` allocator:

```mojo
from src.sql.uast import UASTPool, UASTNode, UAST_SQL_SELECT, UAST_SQL_FROM, UAST_SQL_WHERE, UAST_NAME, UAST_LITERAL_NUM
from src.sql.parser import parse_select
from src.sql.tokenizer import tokenize_sql

# Parse SQL into AST and serialize to Unimo UAST
var tokens = tokenize_sql("SELECT id, name FROM users WHERE id = 42")
var ast = parse_select(tokens)

var pool = UASTPool()
var root_idx = ast.to_uast(pool)
var root_node = pool.get(root_idx)
```

---

## 3. Verification & Test Results

The test suite [`tests/test_uast.mojo`](../tests/test_uast.mojo) validates the UAST translation:

```
=== Testing Unimo Universal AST Compatibility for LeanSQL ===
  Root node kind: UAST_SQL_SELECT (100)
  Columns: id (11), name (11)
  From: users (107)
  Where: id = 42
Unimo Universal AST compatibility test passed successfully!
```
