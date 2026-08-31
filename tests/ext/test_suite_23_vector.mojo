from tests.harness import TestHarness
from src.engine.connection import connect
from src.ext.vector import (
    Vector,
    parse_vector,
    vec_distance_cosine,
    vec_distance_l2,
    vec_dot_product,
)


def run_vector_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 23: SIMD Vector Search & Similarity (vec) ===")
    print("=======================================================")

    # 1. Parsing & Dimensions
    var v1 = parse_vector("[1.0, 2.0, 3.0]")
    h.assert_equal_int("vec-1.1a", v1.dim(), 3, "parse_vector parses 3 dimensions")
    h.assert_equal_float("vec-1.1b", v1.data[0], 1.0, 0.001, "Dimension 0 is 1.0")
    h.assert_equal_float("vec-1.1c", v1.data[2], 3.0, 0.001, "Dimension 2 is 3.0")

    var v2 = parse_vector("[4.0, 5.0, 6.0]")

    # 2. Dot Product: 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
    var dot = vec_dot_product(v1, v2)
    h.assert_equal_float("vec-1.2", dot, 32.0, 0.001, "Dot product of [1,2,3] and [4,5,6] is 32.0")

    # 3. L2 (Euclidean) Distance: sqrt( (1-4)^2 + (2-5)^2 + (3-6)^2 ) = sqrt(9 + 9 + 9) = sqrt(27) = 5.196
    var dist_l2 = vec_distance_l2(v1, v2)
    h.assert_equal_float("vec-1.3", dist_l2, 5.19615, 0.001, "L2 distance is sqrt(27) ≈ 5.196")

    # 4. Cosine Distance
    # Identical vectors: distance should be 0.0
    var dist_cos_self = vec_distance_cosine(v1, v1)
    h.assert_equal_float("vec-1.4a", dist_cos_self, 0.0, 0.001, "Cosine distance of vector to itself is 0.0")

    # Orthogonal vectors: [1, 0] and [0, 1] -> distance = 1.0
    var v_x = parse_vector("[1.0, 0.0]")
    var v_y = parse_vector("[0.0, 1.0]")
    var dist_cos_orth = vec_distance_cosine(v_x, v_y)
    h.assert_equal_float("vec-1.4b", dist_cos_orth, 1.0, 0.001, "Cosine distance of orthogonal vectors is 1.0")

    # 5. SQL Engine Query Integration & Nearest Neighbor (KNN) Search
    var con = connect(":memory:")
    var cur = con.cursor()
    cur.execute("CREATE TABLE embeddings (id INT, label TEXT, embedding TEXT)")
    cur.execute("INSERT INTO embeddings VALUES (1, 'database', '[0.9, 0.1, 0.0]')")
    cur.execute("INSERT INTO embeddings VALUES (2, 'relational', '[0.85, 0.15, 0.05]')")
    cur.execute("INSERT INTO embeddings VALUES (3, 'deep_learning', '[0.05, 0.95, 0.8]')")

    # Query: Find top-1 closest to query vector [0.95, 0.05, 0.0]
    var query_vec = "'[0.95, 0.05, 0.0]'"
    cur.execute("SELECT id, label, vec_distance_cosine(embedding, " + query_vec + ") AS dist FROM embeddings ORDER BY dist ASC LIMIT 2")
    var knn_rows = cur.fetchall()

    h.assert_equal_int("vec-1.5a", len(knn_rows), 2, "KNN query returns top 2 nearest neighbors")
    h.assert_equal("vec-1.5b", knn_rows[0].get_string(1), "database", "First nearest neighbor is 'database'")
    h.assert_equal("vec-1.5c", knn_rows[1].get_string(1), "relational", "Second nearest neighbor is 'relational'")

    # Dimension checking in SQL
    cur.execute("SELECT vec_dims(embedding) FROM embeddings WHERE id = 1")
    var dim_row = cur.fetchone()
    if dim_row:
        h.assert_equal_int("vec-1.6", Int(dim_row.value().get_int(0)), 3, "vec_dims() in SQL returns 3")


def main() raises:
    var h = TestHarness("Suite 23: Vector Similarity")
    run_vector_tests(h)
    h.summary()
