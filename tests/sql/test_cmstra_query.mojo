from src.engine.connection import connect


def main() raises:
    # 1. Path to SQLite database file
    var db_path = "./data/example.db"
    print("Opening database:", db_path)

    # 2. Connect to database
    var con = connect(db_path)
    var cur = con.cursor()

    # 3. Execute query
    var query = "SELECT * FROM navigation_items" # "SELECT COUNT(*) FROM rag_chunks" 
    print("Executing query:", query)
    cur.execute(query)

    # # 4. Fetch result
    # var row = cur.fetchone()
    # if row:
    #     var count_val = row.value().get_int(0)
    #     print("Result count:", count_val)
    # else:
    #     print("No rows returned.")


    # 4. Fetch all rows and print with colon separator
    var rows = cur.fetchall()
    print("Total rows returned:", len(rows))

    for r_idx in range(len(rows)):
        var row = rows[r_idx]
        var line = String()
        var num_cols = len(row)

        for c_idx in range(num_cols):
            if c_idx > 0:
                line += ","
            if row.is_null(c_idx):
                line += "NULL"
            else:
                line += row.get_string(c_idx)

        print(line)

    # 5. Close connection
    con.close()
