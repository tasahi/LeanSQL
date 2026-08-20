""" SQLite SQL Tokenizer.

Corresponds to `sqlite/src/tokenize.c` and aligns token tag symbols with Unimo AST tags.

Splits raw SQL strings into discrete token symbols (Keywords, Identifiers, Numbers, Strings, Punctuation, Operators).
"""

from src.types import *
from src.utf import nocase_compare
from src.uast import UAST_NAME, UAST_LITERAL_NUM, UAST_LITERAL_STR, UAST_SQL_SELECT, UAST_SQL_INSERT, UAST_SQL_WHERE, UAST_SQL_FROM, UAST_SQL_CREATE_TABLE, UAST_SQL_VALUES, UAST_SQL_STAR

# === Token Types ===
comptime TK_SELECT = UAST_SQL_SELECT
comptime TK_INSERT = UAST_SQL_INSERT
comptime TK_INTO = 120
comptime TK_VALUES = UAST_SQL_VALUES
comptime TK_FROM = UAST_SQL_FROM
comptime TK_WHERE = UAST_SQL_WHERE
comptime TK_CREATE = 121
comptime TK_TABLE = 122
comptime TK_UPDATE = 123
comptime TK_SET = 124
comptime TK_DELETE = 125
comptime TK_DEFAULT = 126
comptime TK_PRIMARY = 127
comptime TK_KEY = 128
comptime TK_ORDER = 129
comptime TK_BY = 140
comptime TK_ASC = 141
comptime TK_DESC = 142
comptime TK_LIMIT = 143
comptime TK_OFFSET = 144
comptime TK_NULL = 145
comptime TK_IS = 146
comptime TK_NOT = 147
comptime TK_LIKE = 148
comptime TK_IN = 149
comptime TK_BETWEEN = 150
comptime TK_CASE = 151
comptime TK_WHEN = 152
comptime TK_THEN = 153
comptime TK_ELSE = 154
comptime TK_END = 155
comptime TK_INDEX = 156
comptime TK_DROP = 157
comptime TK_AS = 158
comptime TK_DISTINCT = 159
comptime TK_GROUP = 160
comptime TK_HAVING = 161
comptime TK_BEGIN = 162
comptime TK_COMMIT = 163
comptime TK_ROLLBACK = 164
comptime TK_SAVEPOINT = 165
comptime TK_RELEASE = 166
comptime TK_TRANSACTION = 167
comptime TK_TO = 168
comptime TK_UNIQUE = 169
comptime TK_CAST = 170

comptime TK_ID = UAST_NAME
comptime TK_INTEGER = UAST_LITERAL_NUM
comptime TK_FLOAT = 180
comptime TK_STRING = UAST_LITERAL_STR
comptime TK_COMMA = 130
comptime TK_SEMI = 131
comptime TK_LP = 132
comptime TK_RP = 133
comptime TK_STAR = UAST_SQL_STAR
comptime TK_EQ = 135
comptime TK_LT = 136
comptime TK_GT = 137
comptime TK_LE = 181
comptime TK_GE = 182
comptime TK_NE = 183
comptime TK_PLUS = 138
comptime TK_MINUS = 139
comptime TK_SLASH = 184
comptime TK_PERCENT = 185
comptime TK_CONCAT = 186
comptime TK_AND = 187
comptime TK_OR = 188
comptime TK_DOT = 189
comptime TK_JOIN = 200
comptime TK_INNER = 201
comptime TK_LEFT = 202
comptime TK_OUTER = 203
comptime TK_CROSS = 204
comptime TK_ON = 205
comptime TK_UNION = 206
comptime TK_ALL = 207
comptime TK_INTERSECT = 208
comptime TK_EXCEPT = 209
comptime TK_PRAGMA = 210
comptime TK_ALTER = 211
comptime TK_RENAME = 212
comptime TK_ADD = 213
comptime TK_COLUMN = 214
comptime TK_VIEW = 215
comptime TK_WITH = 216
comptime TK_RECURSIVE = 217
comptime TK_OVER = 218
comptime TK_PARTITION = 219
comptime TK_TRIGGER = 220
comptime TK_BEFORE = 221
comptime TK_AFTER = 222
comptime TK_FOR = 223
comptime TK_EACH = 224
comptime TK_ROW = 225
comptime TK_EOF = 199


struct Token(ImplicitlyCopyable, Copyable, Movable):
    """ Represents an SQL lexer token with type tag and string slice value."""
    var token_type: Int
    var text: String

    def __init__(out self, token_type: Int, text: String):
        self.token_type = token_type
        self.text = text

    def __init__(out self, *, copy: Self):
        self.token_type = copy.token_type
        self.text = copy.text

    def __init__(out self, *, deinit move: Self):
        self.token_type = move.token_type
        self.text = move.text^


def is_digit(c: UInt8) -> Bool:
    """ Checks if ASCII byte is 0-9."""
    return c >= 48 and c <= 57


def is_alpha(c: UInt8) -> Bool:
    """ Checks if ASCII byte is a-z, A-Z, or underscore."""
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95


def tokenize_sql(sql: String) raises -> List[Token]:
    """ Scans raw SQL text and produces a list of `Token`s."""
    var tokens = List[Token]()
    var bytes = sql.as_bytes()
    var n = len(bytes)
    var i = 0

    while i < n:
        var c = bytes[i]

        # 1. Skip whitespace
        if c == 32 or c == 9 or c == 10 or c == 13:
            i += 1
            continue

        # 2. Multi-character operators
        if c == 124 and i + 1 < n and bytes[i + 1] == 124:  # '||'
            tokens.append(Token(TK_CONCAT, "||"))
            i += 2
            continue
        if c == 33 and i + 1 < n and bytes[i + 1] == 61:  # '!='
            tokens.append(Token(TK_NE, "!="))
            i += 2
            continue
        if c == 60 and i + 1 < n and bytes[i + 1] == 62:  # '<>'
            tokens.append(Token(TK_NE, "<>"))
            i += 2
            continue
        if c == 60 and i + 1 < n and bytes[i + 1] == 61:  # '<='
            tokens.append(Token(TK_LE, "<="))
            i += 2
            continue
        if c == 62 and i + 1 < n and bytes[i + 1] == 61:  # '>='
            tokens.append(Token(TK_GE, ">="))
            i += 2
            continue

        # 3. Single-character punctuation / operators
        if c == 44:  # ','
            tokens.append(Token(TK_COMMA, ","))
            i += 1
            continue
        if c == 59:  # ';'
            tokens.append(Token(TK_SEMI, ";"))
            i += 1
            continue
        if c == 40:  # '('
            tokens.append(Token(TK_LP, "("))
            i += 1
            continue
        if c == 41:  # ')'
            tokens.append(Token(TK_RP, ")"))
            i += 1
            continue
        if c == 42:  # '*'
            tokens.append(Token(TK_STAR, "*"))
            i += 1
            continue
        if c == 61:  # '='
            tokens.append(Token(TK_EQ, "="))
            i += 1
            continue
        if c == 60:  # '<'
            tokens.append(Token(TK_LT, "<"))
            i += 1
            continue
        if c == 62:  # '>'
            tokens.append(Token(TK_GT, ">"))
            i += 1
            continue
        if c == 43:  # '+'
            tokens.append(Token(TK_PLUS, "+"))
            i += 1
            continue
        if c == 45:  # '-'
            tokens.append(Token(TK_MINUS, "-"))
            i += 1
            continue
        if c == 47:  # '/'
            tokens.append(Token(TK_SLASH, "/"))
            i += 1
            continue
        if c == 37:  # '%'
            tokens.append(Token(TK_PERCENT, "%"))
            i += 1
            continue
        if c == 46:  # '.'
            tokens.append(Token(TK_DOT, "."))
            i += 1
            continue

        # 4. String literals ('...' or "...")
        if c == 39 or c == 34:  # '\'' or '"'
            var quote_char = c
            var s = String()
            i += 1
            while i < n and bytes[i] != quote_char:
                s += chr(Int(bytes[i]))
                i += 1
            if i < n and bytes[i] == quote_char:
                i += 1
            tokens.append(Token(TK_STRING, s))
            continue

        # 5. Numeric literals (Integers or Floats)
        if is_digit(c) or (c == 45 and i + 1 < n and is_digit(bytes[i + 1])): # optional leading negative
            var num_str = String()
            if c == 45:
                num_str += "-"
                i += 1
            var has_dot = False
            while i < n and (is_digit(bytes[i]) or (bytes[i] == 46 and not has_dot)):
                if bytes[i] == 46:
                    has_dot = True
                num_str += chr(Int(bytes[i]))
                i += 1
            if has_dot:
                tokens.append(Token(TK_FLOAT, num_str))
            else:
                tokens.append(Token(TK_INTEGER, num_str))
            continue

        # 6. Keywords & Identifiers
        if is_alpha(c):
            var word = String()
            while i < n and (is_alpha(bytes[i]) or is_digit(bytes[i])):
                word += chr(Int(bytes[i]))
                i += 1

            if nocase_compare(word, "SELECT") == 0:
                tokens.append(Token(TK_SELECT, word))
            elif nocase_compare(word, "INSERT") == 0:
                tokens.append(Token(TK_INSERT, word))
            elif nocase_compare(word, "INTO") == 0:
                tokens.append(Token(TK_INTO, word))
            elif nocase_compare(word, "VALUES") == 0:
                tokens.append(Token(TK_VALUES, word))
            elif nocase_compare(word, "FROM") == 0:
                tokens.append(Token(TK_FROM, word))
            elif nocase_compare(word, "WHERE") == 0:
                tokens.append(Token(TK_WHERE, word))
            elif nocase_compare(word, "CREATE") == 0:
                tokens.append(Token(TK_CREATE, word))
            elif nocase_compare(word, "TABLE") == 0:
                tokens.append(Token(TK_TABLE, word))
            elif nocase_compare(word, "UPDATE") == 0:
                tokens.append(Token(TK_UPDATE, word))
            elif nocase_compare(word, "SET") == 0:
                tokens.append(Token(TK_SET, word))
            elif nocase_compare(word, "DELETE") == 0:
                tokens.append(Token(TK_DELETE, word))
            elif nocase_compare(word, "DEFAULT") == 0:
                tokens.append(Token(TK_DEFAULT, word))
            elif nocase_compare(word, "PRIMARY") == 0:
                tokens.append(Token(TK_PRIMARY, word))
            elif nocase_compare(word, "KEY") == 0:
                tokens.append(Token(TK_KEY, word))
            elif nocase_compare(word, "ORDER") == 0:
                tokens.append(Token(TK_ORDER, word))
            elif nocase_compare(word, "BY") == 0:
                tokens.append(Token(TK_BY, word))
            elif nocase_compare(word, "ASC") == 0:
                tokens.append(Token(TK_ASC, word))
            elif nocase_compare(word, "DESC") == 0:
                tokens.append(Token(TK_DESC, word))
            elif nocase_compare(word, "LIMIT") == 0:
                tokens.append(Token(TK_LIMIT, word))
            elif nocase_compare(word, "OFFSET") == 0:
                tokens.append(Token(TK_OFFSET, word))
            elif nocase_compare(word, "NULL") == 0:
                tokens.append(Token(TK_NULL, word))
            elif nocase_compare(word, "IS") == 0:
                tokens.append(Token(TK_IS, word))
            elif nocase_compare(word, "NOT") == 0:
                tokens.append(Token(TK_NOT, word))
            elif nocase_compare(word, "LIKE") == 0:
                tokens.append(Token(TK_LIKE, word))
            elif nocase_compare(word, "IN") == 0:
                tokens.append(Token(TK_IN, word))
            elif nocase_compare(word, "BETWEEN") == 0:
                tokens.append(Token(TK_BETWEEN, word))
            elif nocase_compare(word, "CASE") == 0:
                tokens.append(Token(TK_CASE, word))
            elif nocase_compare(word, "WHEN") == 0:
                tokens.append(Token(TK_WHEN, word))
            elif nocase_compare(word, "THEN") == 0:
                tokens.append(Token(TK_THEN, word))
            elif nocase_compare(word, "ELSE") == 0:
                tokens.append(Token(TK_ELSE, word))
            elif nocase_compare(word, "END") == 0:
                tokens.append(Token(TK_END, word))
            elif nocase_compare(word, "INDEX") == 0:
                tokens.append(Token(TK_INDEX, word))
            elif nocase_compare(word, "DROP") == 0:
                tokens.append(Token(TK_DROP, word))
            elif nocase_compare(word, "AS") == 0:
                tokens.append(Token(TK_AS, word))
            elif nocase_compare(word, "DISTINCT") == 0:
                tokens.append(Token(TK_DISTINCT, word))
            elif nocase_compare(word, "GROUP") == 0:
                tokens.append(Token(TK_GROUP, word))
            elif nocase_compare(word, "HAVING") == 0:
                tokens.append(Token(TK_HAVING, word))
            elif nocase_compare(word, "BEGIN") == 0:
                tokens.append(Token(TK_BEGIN, word))
            elif nocase_compare(word, "COMMIT") == 0:
                tokens.append(Token(TK_COMMIT, word))
            elif nocase_compare(word, "ROLLBACK") == 0:
                tokens.append(Token(TK_ROLLBACK, word))
            elif nocase_compare(word, "SAVEPOINT") == 0:
                tokens.append(Token(TK_SAVEPOINT, word))
            elif nocase_compare(word, "RELEASE") == 0:
                tokens.append(Token(TK_RELEASE, word))
            elif nocase_compare(word, "TRANSACTION") == 0:
                tokens.append(Token(TK_TRANSACTION, word))
            elif nocase_compare(word, "TO") == 0:
                tokens.append(Token(TK_TO, word))
            elif nocase_compare(word, "UNIQUE") == 0:
                tokens.append(Token(TK_UNIQUE, word))
            elif nocase_compare(word, "CAST") == 0:
                tokens.append(Token(TK_CAST, word))
            elif nocase_compare(word, "AND") == 0:
                tokens.append(Token(TK_AND, word))
            elif nocase_compare(word, "OR") == 0:
                tokens.append(Token(TK_OR, word))
            elif nocase_compare(word, "JOIN") == 0:
                tokens.append(Token(TK_JOIN, word))
            elif nocase_compare(word, "INNER") == 0:
                tokens.append(Token(TK_INNER, word))
            elif nocase_compare(word, "LEFT") == 0:
                tokens.append(Token(TK_LEFT, word))
            elif nocase_compare(word, "OUTER") == 0:
                tokens.append(Token(TK_OUTER, word))
            elif nocase_compare(word, "CROSS") == 0:
                tokens.append(Token(TK_CROSS, word))
            elif nocase_compare(word, "ON") == 0:
                tokens.append(Token(TK_ON, word))
            elif nocase_compare(word, "UNION") == 0:
                tokens.append(Token(TK_UNION, word))
            elif nocase_compare(word, "ALL") == 0:
                tokens.append(Token(TK_ALL, word))
            elif nocase_compare(word, "INTERSECT") == 0:
                tokens.append(Token(TK_INTERSECT, word))
            elif nocase_compare(word, "EXCEPT") == 0:
                tokens.append(Token(TK_EXCEPT, word))
            elif nocase_compare(word, "PRAGMA") == 0:
                tokens.append(Token(TK_PRAGMA, word))
            elif nocase_compare(word, "ALTER") == 0:
                tokens.append(Token(TK_ALTER, word))
            elif nocase_compare(word, "RENAME") == 0:
                tokens.append(Token(TK_RENAME, word))
            elif nocase_compare(word, "ADD") == 0:
                tokens.append(Token(TK_ADD, word))
            elif nocase_compare(word, "COLUMN") == 0:
                tokens.append(Token(TK_COLUMN, word))
            elif nocase_compare(word, "VIEW") == 0:
                tokens.append(Token(TK_VIEW, word))
            elif nocase_compare(word, "WITH") == 0:
                tokens.append(Token(TK_WITH, word))
            elif nocase_compare(word, "RECURSIVE") == 0:
                tokens.append(Token(TK_RECURSIVE, word))
            elif nocase_compare(word, "OVER") == 0:
                tokens.append(Token(TK_OVER, word))
            elif nocase_compare(word, "PARTITION") == 0:
                tokens.append(Token(TK_PARTITION, word))
            elif nocase_compare(word, "TRIGGER") == 0:
                tokens.append(Token(TK_TRIGGER, word))
            elif nocase_compare(word, "BEFORE") == 0:
                tokens.append(Token(TK_BEFORE, word))
            elif nocase_compare(word, "AFTER") == 0:
                tokens.append(Token(TK_AFTER, word))
            elif nocase_compare(word, "FOR") == 0:
                tokens.append(Token(TK_FOR, word))
            elif nocase_compare(word, "EACH") == 0:
                tokens.append(Token(TK_EACH, word))
            elif nocase_compare(word, "ROW") == 0:
                tokens.append(Token(TK_ROW, word))
            elif nocase_compare(word, "END") == 0:
                tokens.append(Token(TK_END, word))
            else:
                tokens.append(Token(TK_ID, word))
            continue

        i += 1

    tokens.append(Token(TK_EOF, ""))
    return tokens^
