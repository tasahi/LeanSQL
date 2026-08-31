from tests.harness import TestHarness
from src.engine.connection import connect


def run_window_funcs_tests(mut h: TestHarness) raises:
    print("\n=======================================================")
    print("=== Suite 17: Window Functions (window1.test)       ===")
    print("=======================================================")
    var con = connect(":memory:")
    var cur = con.cursor()

    cur.execute("CREATE TABLE scores (id INT, player TEXT, team TEXT, score INT)")
    cur.execute("INSERT INTO scores VALUES (1, 'Alice', 'Red', 100)")
    cur.execute("INSERT INTO scores VALUES (2, 'Bob', 'Red', 80)")
    cur.execute("INSERT INTO scores VALUES (3, 'Charlie', 'Blue', 95)")
    cur.execute("INSERT INTO scores VALUES (4, 'David', 'Blue', 95)")
    cur.execute("INSERT INTO scores VALUES (5, 'Eve', 'Red', 60)")

    # 1. ROW_NUMBER() OVER (ORDER BY score DESC)
    cur.execute("SELECT player, score, ROW_NUMBER() OVER (ORDER BY score DESC) AS rnum FROM scores ORDER BY score DESC")
    var q1 = cur.fetchall()
    h.assert_equal_int("win-1.1a", Int64(len(q1)), 5, "5 rows returned with ROW_NUMBER")
    h.assert_equal("win-1.1b", q1[0].get_string(0), "Alice", "Top player is Alice")
    h.assert_equal_int("win-1.1c", q1[0].get_int(2), 1, "Alice row_number is 1")
    h.assert_equal_int("win-1.1d", q1[4].get_int(2), 5, "Fifth player row_number is 5")

    # 2. ROW_NUMBER() OVER (PARTITION BY team ORDER BY score DESC)
    cur.execute("SELECT player, team, ROW_NUMBER() OVER (PARTITION BY team ORDER BY score DESC) AS team_rank FROM scores ORDER BY team ASC, score DESC")
    var q2 = cur.fetchall()
    h.assert_equal_int("win-1.2a", Int64(len(q2)), 5, "Partitioned ROW_NUMBER returned 5 rows")
    h.assert_equal("win-1.2b", q2[0].get_string(1), "Blue", "First partition team is Blue")
    h.assert_equal_int("win-1.2c", q2[0].get_int(2), 1, "Blue top rank is 1")
    h.assert_equal_int("win-1.2d", q2[1].get_int(2), 2, "Blue second rank is 2")
    h.assert_equal("win-1.2e", q2[2].get_string(1), "Red", "Second partition team is Red")
    h.assert_equal_int("win-1.2f", q2[2].get_int(2), 1, "Red top rank is 1")

    # 3. LEAD() and LAG() over score ordering
    cur.execute("SELECT score, LEAD(score, 1) OVER (ORDER BY score ASC) AS next_s, LAG(score, 1) OVER (ORDER BY score ASC) AS prev_s FROM scores ORDER BY score ASC")
    var q3 = cur.fetchall()
    h.assert_equal_int("win-1.3a", Int64(len(q3)), 5, "LEAD/LAG query returned 5 rows")
    h.assert_equal_int("win-1.3b", q3[0].get_int(0), 60, "Lowest score is 60")
    h.assert_equal_int("win-1.3c", q3[0].get_int(1), 80, "Next score after 60 is 80")
    h.assert_true("win-1.3d", q3[0].is_null(2), "Previous score before 60 is NULL")
    h.assert_equal_int("win-1.3e", q3[1].get_int(2), 60, "Previous score before 80 is 60")


def main() raises:
    var h = TestHarness("Suite 17: Window Functions")
    run_window_funcs_tests(h)
    h.summary()
