from src.core.types import *
from src.sql.tokenizer import tokenize_sql, TK_SELECT, TK_FROM, TK_WHERE, TK_ID, TK_INTEGER, TK_STRING, TK_COMMA, TK_EQ, TK_EOF


def test_sql_tokenization() raises:
    print("=== Testing SQL Tokenizer ===")
    
    var sql = "SELECT id, name FROM users WHERE id = 42;"
    var tokens = tokenize_sql(sql)

    if tokens[0].token_type != TK_SELECT:
        raise Error("Expected TK_SELECT")
    if tokens[1].token_type != TK_ID or tokens[1].text != "id":
        raise Error("Expected identifier 'id'")
    if tokens[2].token_type != TK_COMMA:
        raise Error("Expected TK_COMMA")
    if tokens[3].token_type != TK_ID or tokens[3].text != "name":
        raise Error("Expected identifier 'name'")
    if tokens[4].token_type != TK_FROM:
        raise Error("Expected TK_FROM")
    if tokens[5].token_type != TK_ID or tokens[5].text != "users":
        raise Error("Expected identifier 'users'")
    if tokens[6].token_type != TK_WHERE:
        raise Error("Expected TK_WHERE")
    if tokens[7].token_type != TK_ID or tokens[7].text != "id":
        raise Error("Expected identifier 'id'")
    if tokens[8].token_type != TK_EQ:
        raise Error("Expected TK_EQ")
    if tokens[9].token_type != TK_INTEGER or tokens[9].text != "42":
        raise Error("Expected integer 42")

    print("SQL Tokenizer tests passed successfully!")


def main() raises:
    test_sql_tokenization()
