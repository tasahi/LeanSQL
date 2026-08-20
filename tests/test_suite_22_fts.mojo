from tests.harness import TestHarness
from src.connection import connect
from src.fts import tokenize_text, compute_bm25_score, fts_match, fts_highlight, fts_snippet


def run_fts_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 22: Full-Text Search & BM25 Scoring (fts) ===")
    print("=======================================================")

    # 1. Low-level Tokenizer
    var tokens = tokenize_text("Mojo & SQLite: High-Performance Database Engine!")
    h.assert_equal_int("fts-1.1a", len(tokens), 6, "Tokenizer splits into 6 alphanumeric tokens")
    h.assert_equal("fts-1.1b", tokens[0], "mojo", "First token is lowercase 'mojo'")
    h.assert_equal("fts-1.1c", tokens[1], "sqlite", "Second token is lowercase 'sqlite'")
    h.assert_equal("fts-1.1d", tokens[5], "engine", "Sixth token is lowercase 'engine'")

    # 2. MATCH logic
    var match_yes = fts_match("The quick brown fox jumps over the lazy dog", "brown fox")
    h.assert_true("fts-1.2a", match_yes, "fts_match matches multi-word query")
    var match_no = fts_match("The quick brown fox jumps over the lazy dog", "white rabbit")
    h.assert_false("fts-1.2b", match_no, "fts_match rejects missing terms")

    # 3. Highlighting
    var highlighted = fts_highlight("Fast AI inference with Mojo compiler", "mojo")
    h.assert_equal("fts-1.3", highlighted, "Fast AI inference with <b>Mojo</b> compiler", "fts_highlight surrounds match in tags")

    # 4. Snippet generation
    var snippet_text = fts_snippet("SQLite is an in-process library that implements a self-contained serverless zero-configuration transactional SQL database engine.", "transactional", 6)
    h.assert_true("fts-1.4", "transactional" in snippet_text, "fts_snippet contains query term")

    # 5. BM25 scoring algorithm
    var q_toks = List[String]()
    q_toks.append(String("compiler"))
    var d1_toks = List[String]()
    d1_toks.append(String("mojo"))
    d1_toks.append(String("compiler"))
    d1_toks.append(String("compiler")) # tf = 2
    var d2_toks = List[String]()
    d2_toks.append(String("general"))
    d2_toks.append(String("compiler")) # tf = 1
    var df_list = List[Int]()
    df_list.append(2)

    var score1 = compute_bm25_score(q_toks, d1_toks, 10, df_list, 3.0)
    var score2 = compute_bm25_score(q_toks, d2_toks, 10, df_list, 3.0)
    h.assert_true("fts-1.5", score1 > score2, "Document with higher term frequency receives higher BM25 score")

    # 6. SQL Query Integration with FTS Functions
    var con = connect(":memory:")
    var cur = con.cursor()
    cur.execute("CREATE TABLE articles (id INT, title TEXT, body TEXT)")
    cur.execute("INSERT INTO articles VALUES (1, 'Mojo Release', 'Modular announces Mojo language for high-performance systems.')")
    cur.execute("INSERT INTO articles VALUES (2, 'SQLite Architecture', 'SQLite provides serverless zero-configuration relational storage.')")
    cur.execute("INSERT INTO articles VALUES (3, 'AI Vector Search', 'Embeddings and similarity search using Mojo SIMD vector kernels.')")

    cur.execute("SELECT id, title FROM articles WHERE fts_match(body, 'mojo') = 1 ORDER BY id")
    var rows_mojo = cur.fetchall()
    h.assert_equal_int("fts-1.6a", len(rows_mojo), 2, "fts_match in SQL WHERE returns 2 matching articles")
    h.assert_equal_int("fts-1.6b", rows_mojo[0].get_int(0), 1, "First match is article 1")
    h.assert_equal_int("fts-1.6c", rows_mojo[1].get_int(0), 3, "Second match is article 3")

    cur.execute("SELECT highlight(title, 'Release', '<mark>', '</mark>') FROM articles WHERE id = 1")
    var row_hl = cur.fetchone()
    if row_hl:
        h.assert_equal("fts-1.7", row_hl.value().get_string(0), "Mojo <mark>Release</mark>", "highlight() executes in SQL SELECT")


def main() raises:
    var h = TestHarness("Suite 22: Full-Text Search")
    run_fts_tests(h)
    h.summary()
