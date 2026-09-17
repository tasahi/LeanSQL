# LeanSQL: 100% Pure-Mojo SQLite compatible Engine & Extensions

What if there is an implementation of SQLite in mojo?  

**LeanSQL** is a full-featured, zero-dependency relational database engine and extension ecosystem implemented **100% in pure Mojo**.

It provides complete compatibility with standard SQLite 3 semantics while integrating modern AI capabilities: native **SIMD-accelerated Vector Similarity Search**, **Full-Text Search with BM25 ranking**, **Extended Mathematical & Cryptographic Built-Ins**, an **Interactive CLI Shell**, **C-ABI Export**, and a **Python DB-API 2.0 driver**.

---

## Key Highlights

- **100% Pure Mojo**: Zero C-compiler dependencies, zero external C library fallbacks.
- **Native AI Vector Embeddings**: In-engine SIMD vector operations (`vec_distance_cosine`, `vec_distance_l2`, `vec_dot_product`, `vec_dims`) for high-performance vector search and KNN queries.
- **Full-Text Search (FTS) & BM25**: Tokenization, multi-term queries, BM25 relevance scoring, keyword highlighting, and snippet excerpt extraction.
- **Standard SQL Compatibility**: DDL (`CREATE/DROP TABLE, INDEX, VIEW, TRIGGER, ALTER`), DML (`INSERT, UPDATE, DELETE`), multi-table JOINs, Recursive CTEs (`WITH RECURSIVE`), and Window Functions (`ROW_NUMBER, RANK, LEAD, LAG`).
- **Python DB-API 2.0 Drop-In**: Connect and query directly from Python using `import leansql_driver as sqlite3`.
- **Composite & Binary Data Extensions**: Built-in pure Mojo implementations of **SQLite JSONB**, **MessagePack** (`sqlite-msgpack`), **Protocol Buffers** (`sqlite_protobuf`), and **SpatiaLite / OGC Geometry** (WKB 2D Points).
- **Virtual Tables & Extension Interface**: Full support for `CREATE VIRTUAL TABLE ... USING`, user-defined custom scalar function registration (`conn.register_function`), and dynamic library loading (`conn.load_extension`).
- **Exhaustive Test Coverage**: **27 Test Suites** with **391 / 391 passing assertions (100% Pass Rate)**.

---

## 1. Quick Start: Python Installation & Usage

### A. Build the Native Python Extension

Compile `leansql.so` using the Mojo compiler:

```bash
# 1. Activate Mojo environment
source /home/tasahi/miniconda/bin/activate moj

# 2. Build the shared library extension
mojo build --emit shared-lib -I . src/interop/py_export.mojo -o leansql.so
```

### B. Python Fast Usage Example

Use `leansql_driver.py` as a drop-in replacement for standard `sqlite3`:

```python
import leansql_driver as sqlite3

# 1. Connect to an in-memory or file database
con = sqlite3.connect(":memory:")
cur = con.cursor()

# 2. Create table & insert data
cur.execute("CREATE TABLE articles (id INT PRIMARY KEY, title TEXT, embedding TEXT)")
cur.execute("INSERT INTO articles VALUES (1, 'Mojo AI Systems', '[0.90, 0.10, 0.00]')")
cur.execute("INSERT INTO articles VALUES (2, 'Relational Databases', '[0.85, 0.15, 0.05]')")
cur.execute("INSERT INTO articles VALUES (3, 'Deep Learning Kernels', '[0.05, 0.95, 0.80]')")
con.commit()

# 3. Query using SIMD Vector Similarity, Math, and Crypto functions
cur.execute("""
    SELECT id, title,
           vec_distance_cosine(embedding, '[0.95, 0.05, 0.0]') AS dist,
           sha256(title) AS digest,
           sqrt(16.0) AS root
    FROM articles
    ORDER BY dist ASC
""")

for row in cur.fetchall():
    print(row)

con.close()
```

---

## 2. Interactive CLI Shell

Launch the interactive REPL shell:

```bash
mojo run leansql.mojo [database_file.db]
```

```text
LeanSQL version 3.45.0 (100% Pure Mojo)
Enter ".help" for usage hints.
Connected to :memory:

leansql> CREATE TABLE demo (id INT, val TEXT);
leansql> INSERT INTO demo VALUES (1, 'Hello from Mojo LeanSQL!');
leansql> .mode column
leansql> .headers on
leansql> SELECT id, val, hex(val) AS hex_val FROM demo;
id  val                      hex_val
--  -----------------------  ----------------------------------------------
1   Hello from Mojo LeanSQL!  48656C6C6F2066726F6D204D6F6A6F2053514C65616E21
leansql> .quit
```

---

## 3. Running the Test Suite
 
Execute all 27 test suites covering fundamental SQLite semantics, virtual tables, and LeanSQL extensions:

```bash
bash tests/run_tests.sh
```

Or run the Mojo test runner directly:

```bash
mojo run -I . tests/run_all_test_suites.mojo
```

---

## 4. Documentation
 
Comprehensive technical documentation, user guides, internal engine specifications, and evolutionary walkthroughs are organized in the [Documentation Index](docs/index.md):
 
- **[LeanSQL Documentation Hub](docs/index.md)**: Master index, technical summary, architecture guides, extension catalogs, and stages walkthroughs.


## Notes

This code was generated with the support of AI Agents. Please leave suggestions for further improvements.