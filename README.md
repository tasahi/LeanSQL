# SQLean: 100% Pure-Mojo SQLite Engine & Extensions

**SQLean** is a full-featured, zero-dependency relational database engine and extension ecosystem implemented **100% in pure Mojo**.

It provides complete compatibility with standard SQLite 3 semantics while integrating modern AI capabilities: native **SIMD-accelerated Vector Similarity Search**, **Full-Text Search with BM25 ranking**, **Extended Mathematical & Cryptographic Built-Ins**, an **Interactive CLI Shell**, **C-ABI Export**, and a **Python DB-API 2.0 driver**.

---

## Key Highlights

- **100% Pure Mojo**: Zero C-compiler dependencies, zero external C library fallbacks.
- **Native AI Vector Embeddings**: In-engine SIMD vector operations (`vec_distance_cosine`, `vec_distance_l2`, `vec_dot_product`, `vec_dims`) for high-performance vector search and KNN queries.
- **Full-Text Search (FTS) & BM25**: Tokenization, multi-term queries, BM25 relevance scoring, keyword highlighting, and snippet excerpt extraction.
- **Standard SQL Compatibility**: DDL (`CREATE/DROP TABLE, INDEX, VIEW, TRIGGER, ALTER`), DML (`INSERT, UPDATE, DELETE`), multi-table JOINs, Recursive CTEs (`WITH RECURSIVE`), and Window Functions (`ROW_NUMBER, RANK, LEAD, LAG`).
- **Python DB-API 2.0 Drop-In**: Connect and query directly from Python using `import sqlean_driver as sqlite3`.
- **Exhaustive Test Coverage**: **24 Test Suites** with **340 / 340 passing assertions (100% Pass Rate)**.

---

## 1. Quick Start: Python Installation & Usage

### A. Build the Native Python Extension

Compile `sqlean.so` using the Mojo compiler:

```bash
# 1. Activate Mojo environment
source /home/tasahi/miniconda/bin/activate moj

# 2. Build the shared library extension
mojo build --emit shared-lib -I . src/py_export.mojo -o sqlean.so
```

### B. Python Fast Usage Example

Use `sqlean_driver.py` as a drop-in replacement for standard `sqlite3`:

```python
import sqlean_driver as sqlite3

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
mojo run sqlean.mojo [database_file.db]
```

```text
SQLean version 3.45.0 (100% Pure Mojo)
Enter ".help" for usage hints.
Connected to :memory:

sqlean> CREATE TABLE demo (id INT, val TEXT);
sqlean> INSERT INTO demo VALUES (1, 'Hello from Mojo SQLean!');
sqlean> .mode column
sqlean> .headers on
sqlean> SELECT id, val, hex(val) AS hex_val FROM demo;
id  val                      hex_val
--  -----------------------  ----------------------------------------------
1   Hello from Mojo SQLean!  48656C6C6F2066726F6D204D6F6A6F2053514C65616E21
sqlean> .quit
```

---

## 3. Running the Test Suite

Execute all 24 test suites covering fundamental SQLite semantics and SQLean extensions:

```bash
bash tests/run_tests.sh
```

Or run the Mojo test runner directly:

```bash
mojo run -I . tests/run_all_test_suites.mojo
```

---

## 4. Documentation Index

- **[User's Reference Manual](docs/users_reference.md)**: Full SQL syntax guide, dot commands, FTS, Vector search, and Math/Crypto function catalogs.
- **[Programmer's Reference Manual](docs/programmers_reference.md)**: Internal engine architecture, subsystem breakdown, C-ABI specifications, and extension guidelines.
- **[Gap Analysis & Future Roadmap](docs/gap_analysis_and_future_roadmap.md)**: Architectural comparison with C SQLite (`sqlite3.c`) and future enhancement roadmap.
- **[Development Stages Walkthroughs](docs/stages/)**: Detailed chronological walkthroughs for Stages 0 through 13.
