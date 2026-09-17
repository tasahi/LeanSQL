---
type: index
title: "LeanSQL Technical Documentation Hub & Architecture Reference"
description: "Master documentation index and comprehensive technical guide for LeanSQL: a 100% pure-Mojo relational database engine, SQLite 3 compatible storage engine, and AI vector/composite extension ecosystem."
tags:
  - mojo
  - sqlite
  - documentation
  - index
  - architecture
  - database-engine
  - pure-mojo
version: "1.0"
last_updated: "2026-09-16"
status: active
---

# LeanSQL: Technical Documentation Hub & System Architecture

**LeanSQL** is a zero-dependency, full-featured relational database engine and extension ecosystem implemented **100% in pure Mojo 1.0**. It provides native SQLite 3 wire-format compatibility, ACID transactions, B-Tree storage, query planning, and modern extensions including SIMD vector search, BM25 full-text search, and composite binary formats.

---

## 1. Core Technical Documentation

| Document | Description | Key Focus Areas |
| :--- | :--- | :--- |
| **[User's Reference Manual](reference_users.md)** | User-facing guide and operational manual. | CLI shell dot-commands (`.mode`, `.schema`, `.dump`), SQL syntax, transactions, and built-in function catalogs. |
| **[Programmer's Reference Manual](reference_programmers.md)** | Subsystem decomposition and internal architecture. | Storage engine (`B-Tree`, `Pager`, `VFS`), Compiler (`Lexer`, `Parser`, `Optimizer`), and VDBE execution engine. |
| **[Virtual Tables & Dynamic Extensions](virtual_tables_and_extensions.md)** | Virtual table subsystem, dynamic linking, and UDFs. | `CREATE VIRTUAL TABLE ... USING`, module registration (`VirtualTableModule`), dynamic library loader (`dlopen`/`dlsym`), and thin-pointer custom scalar functions. |
| **[Composite & Binary Extensions](composite_binary_extensions.md)** | Structured composite types within SQLite BLOBs. | SQLite JSONB binary tree packing, MessagePack (`sqlite-msgpack`), Protobuf wire extraction (`sqlite_protobuf`), and OGC WKB 2D Point geometries (SpatiaLite). |
| **[Gap Analysis & Future Roadmap](gap_analysis_and_future_roadmap.md)** | Architectural comparison against canonical C SQLite. | Parity matrix with `sqlite3.c`, test pass metrics, pure-Mojo advantages, and future development phases. |
| **[Python C-Extension Export](python_c_extension_export.md)** | Native Python module compilation guide. | Building `leansql.so` via Mojo's `PythonModuleBuilder` and drop-in `leansql_driver.py` DB-API 2.0 interface. |
| **[Unimo UAST Integration](unimo_uast_integration.md)** | Multi-language AST alignment specification. | Mapping LeanSQL SQL AST and token structures to the Unimo Universal Abstract Syntax Tree specification. |
| **[Transcription Roadmap & Strategy](transcription_roadmap.md)** | Incremental translation methodology. | Bottom-up transcription strategy from C SQLite to pure Mojo, differential verification, and API design. |
| **[Mojo Transcription Feasibility Analysis](mojo_transcription.md)** | Systems programming feasibility study. | Technical hurdles of C SQLite translation: memory models, pointer arithmetic, VDBE registers, and ownership semantics. |

---

## 2. Evolutionary Development Stages Walkthroughs

The complete evolutionary history of LeanSQL is documented across 14 developmental milestones in the [docs/stages](stages/index.md) subdirectory.

---

## 3. High-Level Engine Architecture

```
+---------------------------------------------------------------------------------------------------+
|                                LeanSQL: Pure-Mojo Engine Architecture                             |
+---------------------------------------------------------------------------------------------------+
|  Python DB-API (leansql_driver.py) |  Interactive CLI (leansql.mojo) |  C-ABI (include/leansql.h) |
+---------------------------------------------------------------------------------------------------+
|  SQL Parser & Lexer (parser.mojo)  |  Query Optimizer (optimizer)    |  VDBE VM (vdbe.mojo)       |
+---------------------------------------------------------------------------------------------------+
|  B-Tree & Cursors (btree.mojo)     |  ACID Pager & Journal (pager)   |  VFS Disk & Memory (vfs)   |
+---------------------------------------------------------------------------------------------------+
|  LeanSQL Extensions:                                                                              |
|  - SIMD Vector Search & Cosine/L2 (vector.mojo)                                                   |
|  - Full-Text Search (FTS) & BM25 Scoring (fts.mojo)                                               |
|  - Extended Math & Cryptography (crypto.mojo)                                                     |
|  - Composite Types: JSONB, MessagePack, Protobuf & SpatiaLite WKB (jsonb, msgpack, pb, spatial)   |
+---------------------------------------------------------------------------------------------------+
```

