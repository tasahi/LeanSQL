# LeanSQL: User's Reference Manual

The **LeanSQL** user manual provides full syntax specifications, built-in functions, dot commands, and usage guides for the 100% pure-Mojo database engine.

---

## 1. Interactive CLI Shell & Dot Commands

Launch the interactive shell:
```bash
mojo run leansql.mojo [database_file.db]
```

### Supported Dot Commands

| Dot Command | Description | Example |
| :--- | :--- | :--- |
| `.help` | Shows the available commands and help menu. | `.help` |
| `.tables` | Lists all tables in the active database. | `.tables` |
| `.schema [table]` | Displays the `CREATE TABLE` DDL for tables. | `.schema users` |
| `.mode <mode>` | Changes output format: `list`, `column`, `csv`, `line`. | `.mode column` |
| `.headers on\|off` | Toggles column headers in query output. | `.headers on` |
| `.timer on\|off` | Toggles CPU execution time measurement. | `.timer on` |
| `.separator <sep>` | Changes delimiter string for `list` mode. | `.separator " \| "` |
| `.nullvalue <str>` | Sets string representation for `NULL` values. | `.nullvalue "NULL"` |
| `.read <file.sql>` | Executes an external SQL script file. | `.read schema.sql` |
| `.dump` | Generates a full SQL transaction dump of the database. | `.dump` |
| `.quit` / `.exit` | Exits the interactive CLI session. | `.quit` |

---

## 2. SQL Syntax Reference

### A. Data Definition Language (DDL)
```sql
-- Tables
CREATE TABLE users (
    id INT PRIMARY KEY,
    name TEXT NOT NULL,
    score REAL,
    embedding TEXT
);
DROP TABLE users;

-- Indexes
CREATE INDEX idx_users_name ON users(name);
CREATE UNIQUE INDEX idx_users_score ON users(score);
DROP INDEX idx_users_name;

-- Views
CREATE VIEW v_top_users AS SELECT name, score FROM users WHERE score > 80.0;
DROP VIEW v_top_users;

-- ALTER TABLE
ALTER TABLE users RENAME TO members;
ALTER TABLE members ADD COLUMN role TEXT DEFAULT 'Member';
ALTER TABLE members RENAME COLUMN role TO title;
```

### B. Data Manipulation Language (DML)
```sql
-- INSERT
INSERT INTO users VALUES (1, 'Alice', 95.5, '[0.9, 0.1, 0.0]');
INSERT INTO users (id, name) VALUES (2, 'Bob');
INSERT INTO users_archive SELECT * FROM users WHERE score < 50.0;

-- UPDATE
UPDATE users SET score = score + 5.0 WHERE name = 'Alice';

-- DELETE
DELETE FROM users WHERE score < 60.0;
```

### C. Advanced Queries, Joins, CTEs & Windows
```sql
-- Multi-Table JOINs
SELECT u.name, d.dept_name 
FROM users u 
INNER JOIN departments d ON u.dept_id = d.id;

-- Recursive Common Table Expressions (CTE)
WITH RECURSIVE cnt(x) AS (
    SELECT 1
    UNION ALL
    SELECT x + 1 FROM cnt WHERE x < 10
)
SELECT x FROM cnt;

-- Window Functions
SELECT name, score,
       ROW_NUMBER() OVER (PARTITION BY team ORDER BY score DESC) as rank,
       LEAD(score, 1) OVER (ORDER BY score ASC) as next_score
FROM leaderboard;
```

### D. Database Triggers
```sql
CREATE TRIGGER trg_audit AFTER INSERT ON users FOR EACH ROW
BEGIN
    INSERT INTO audit_log VALUES (NEW.id, 'User created', NEW.score);
END;

DROP TRIGGER trg_audit;
```

---

## 3. LeanSQL Extension Functions

### A. Full-Text Search (FTS) & BM25
- `fts_match(text, query)`: Returns `1` if all terms in `query` match `text`, else `0`.
- `highlight(text, query, open_tag, close_tag)`: Wraps matched keywords with custom tags (default `<b>` and `</b>`).
- `snippet(text, query, max_words)`: Extracts an excerpt centered around the query keywords.

**Example**:
```sql
SELECT title, highlight(body, 'mojo', '<mark>', '</mark>')
FROM articles
WHERE fts_match(body, 'mojo database') = 1;
```

### B. AI Vector Similarity Search
- `vec_distance_cosine(v1, v2)`: Computes cosine distance ($1.0 - \text{cosine\_similarity}$).
- `vec_distance_l2(v1, v2)`: Computes Euclidean ($L_2$) distance.
- `vec_dot_product(v1, v2)`: Computes vector dot product.
- `vec_dims(v)`: Returns vector dimension count.

**Example KNN Query**:
```sql
SELECT id, label, vec_distance_cosine(embedding, '[0.95, 0.05, 0.0]') AS dist
FROM embeddings
ORDER BY dist ASC
LIMIT 5;
```

### C. Extended Mathematical Built-Ins
- **Powers & Roots**: `sqrt(x)`, `pow(x, y)` / `power(x, y)`.
- **Logarithms**: `log(x)` / `ln(x)`, `log10(x)`.
- **Trigonometry**: `sin(x)`, `cos(x)`, `tan(x)`, `asin(x)`, `acos(x)`, `atan(x)`, `atan2(y, x)`.
- **Angle Conversion**: `degrees(radians)`, `radians(degrees)`.
- **Rounding & Sign**: `ceil(x)`, `floor(x)`, `trunc(x)`, `sign(x)`.
- **Constants**: `pi()`.

### D. Cryptography & Encodings
- `md5(text)`: Returns 32-character hexadecimal MD5 checksum.
- `sha256(text)`: Returns 64-character hexadecimal SHA-256 checksum.
- `hex(text)`: Encodes string to hexadecimal uppercase string.
- `unhex(hex_str)`: Decodes hexadecimal string to text.
