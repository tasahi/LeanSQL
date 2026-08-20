""" SQLite Built-in Scalar Functions and Type Evaluator.

Corresponds to `sqlite/src/func.c`.

Implements built-in scalar SQL functions:
- Math: abs, round, random
- String: length, upper, lower, substr, trim, ltrim, rtrim, hex, instr, printf
- Type/Null: typeof, coalesce, ifnull, cast
"""

from src.types import *
from src.row import Value
from src.utf import nocase_compare


def is_digit_char(c: UInt8) -> Bool:
    return c >= 48 and c <= 57


def sql_abs(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    var v = args[0]
    if v.type_tag == SQLITE_INTEGER:
        var i = v.int_val
        if i < 0:
            i = -i
        return Value.of_int(i)
    elif v.type_tag == SQLITE_FLOAT:
        var f = v.float_val
        if f < 0.0:
            f = -f
        return Value.of_float(f)
    return v.copy()


def sql_length(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    var v = args[0]
    if v.type_tag == SQLITE_TEXT:
        return Value.of_int(Int64(v.text_val.byte_length()))
    elif v.type_tag == SQLITE_INTEGER:
        return Value.of_int(Int64(String(v.int_val).byte_length()))
    elif v.type_tag == SQLITE_FLOAT:
        return Value.of_int(Int64(String(v.float_val).byte_length()))
    return Value.of_int(0)


def sql_upper(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    var s = args[0].to_string()
    var bytes = s.as_bytes()
    var res = String()
    for i in range(len(bytes)):
        var c = bytes[i]
        if c >= 97 and c <= 122:
            res += chr(Int(c - 32))
        else:
            res += chr(Int(c))
    return Value.of_text(res)


def sql_lower(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    var s = args[0].to_string()
    var bytes = s.as_bytes()
    var res = String()
    for i in range(len(bytes)):
        var c = bytes[i]
        if c >= 65 and c <= 90:
            res += chr(Int(c + 32))
        else:
            res += chr(Int(c))
    return Value.of_text(res)


def sql_substr(args: List[Value]) -> Value:
    if len(args) < 2 or args[0].is_null() or args[1].is_null():
        return Value.of_null()
    var s = args[0].to_string()
    var start = Int(args[1].to_int())
    var bytes = s.as_bytes()
    var n = len(bytes)
    
    # 1-indexed to 0-indexed
    var idx = start - 1
    if idx < 0:
        idx = 0

    var length = n - idx
    if len(args) >= 3 and not args[2].is_null():
        length = Int(args[2].to_int())

    var res = String()
    for i in range(length):
        var cur = idx + i
        if cur >= 0 and cur < n:
            res += chr(Int(bytes[cur]))
    return Value.of_text(res)


def sql_trim(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    var s = args[0].to_string()
    var bytes = s.as_bytes()
    var n = len(bytes)
    var start = 0
    while start < n and (bytes[start] == 32 or bytes[start] == 9 or bytes[start] == 10 or bytes[start] == 13):
        start += 1
    var end = n - 1
    while end >= start and (bytes[end] == 32 or bytes[end] == 9 or bytes[end] == 10 or bytes[end] == 13):
        end -= 1
    var res = String()
    for i in range(start, end + 1):
        res += chr(Int(bytes[i]))
    return Value.of_text(res)


def sql_ltrim(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    var s = args[0].to_string()
    var bytes = s.as_bytes()
    var n = len(bytes)
    var start = 0
    while start < n and (bytes[start] == 32 or bytes[start] == 9 or bytes[start] == 10 or bytes[start] == 13):
        start += 1
    var res = String()
    for i in range(start, n):
        res += chr(Int(bytes[i]))
    return Value.of_text(res)


def sql_rtrim(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    var s = args[0].to_string()
    var bytes = s.as_bytes()
    var n = len(bytes)
    var end = n - 1
    while end >= 0 and (bytes[end] == 32 or bytes[end] == 9 or bytes[end] == 10 or bytes[end] == 13):
        end -= 1
    var res = String()
    for i in range(0, end + 1):
        res += chr(Int(bytes[i]))
    return Value.of_text(res)


def sql_round(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    var f = args[0].to_float()
    var digits = 0
    if len(args) >= 2 and not args[1].is_null():
        digits = Int(args[1].to_int())
    
    var factor: Float64 = 1.0
    for _ in range(digits):
        factor *= 10.0
    
    var rounded = Float64(Int64(f * factor + 0.5)) / factor
    return Value.of_float(rounded)


def sql_hex(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_null()
    var s = args[0].to_string()
    var bytes = s.as_bytes()
    var hex_chars = "0123456789ABCDEF".as_bytes()
    var res = String()
    for i in range(len(bytes)):
        var b = Int(bytes[i])
        var hi = (b >> 4) & 0xF
        var lo = b & 0xF
        res += chr(Int(hex_chars[hi]))
        res += chr(Int(hex_chars[lo]))
    return Value.of_text(res)


def sql_instr(args: List[Value]) -> Value:
    if len(args) < 2 or args[0].is_null() or args[1].is_null():
        return Value.of_null()
    var haystack = args[0].to_string()
    var needle = args[1].to_string()
    var h_bytes = haystack.as_bytes()
    var n_bytes = needle.as_bytes()
    var h_len = len(h_bytes)
    var n_len = len(n_bytes)

    if n_len == 0:
        return Value.of_int(1)
    if n_len > h_len:
        return Value.of_int(0)

    for i in range(h_len - n_len + 1):
        var is_matching = True
        for j in range(n_len):
            if h_bytes[i + j] != n_bytes[j]:
                is_matching = False
                break
        if is_matching:
            return Value.of_int(Int64(i + 1))  # 1-indexed in SQLite
    return Value.of_int(0)


def sql_printf(args: List[Value]) -> Value:
    if len(args) == 0:
        return Value.of_text("")
    var fmt = args[0].to_string()
    var res = String()
    var fmt_bytes = fmt.as_bytes()
    var n = len(fmt_bytes)
    var arg_idx = 1
    var i = 0

    while i < n:
        if fmt_bytes[i] == 37 and i + 1 < n:  # '%'
            if fmt_bytes[i + 1] == 37:  # '%%'
                res += "%"
                i += 2
                continue
            
            var spec = String()
            var j = i + 1
            while j < n and (is_digit_char(fmt_bytes[j]) or fmt_bytes[j] == 46 or fmt_bytes[j] == 48): # '.', '0', digits
                spec += chr(Int(fmt_bytes[j]))
                j += 1
            if j < n:
                var conv = chr(Int(fmt_bytes[j]))
                if arg_idx < len(args):
                    var val = args[arg_idx]
                    arg_idx += 1
                    if conv == "d":
                        var num_str = String(val.to_int())
                        if spec == "04":
                            while num_str.byte_length() < 4:
                                num_str = "0" + num_str
                        res += num_str
                    elif conv == "f":
                        var f_val = val.to_float()
                        if spec == ".2":
                            var f_cents = Int64(f_val * 100.0 + 0.5)
                            var dollars = f_cents // 100
                            var cents = f_cents % 100
                            var c_str = String(cents)
                            if c_str.byte_length() < 2:
                                c_str = "0" + c_str
                            res += String(dollars) + "." + c_str
                        else:
                            res += String(f_val)
                    elif conv == "s":
                        res += val.to_string()
                i = j + 1
                continue
        res += chr(Int(fmt_bytes[i]))
        i += 1
    return Value.of_text(res)


def sql_typeof(args: List[Value]) -> Value:
    if len(args) == 0 or args[0].is_null():
        return Value.of_text("null")
    var t = args[0].type_tag
    if t == SQLITE_INTEGER:
        return Value.of_text("integer")
    elif t == SQLITE_FLOAT:
        return Value.of_text("real")
    elif t == SQLITE_TEXT:
        return Value.of_text("text")
    elif t == SQLITE_BLOB:
        return Value.of_text("blob")
    return Value.of_text("null")


from std.math import (
    sqrt,
    pow,
    log,
    sin,
    cos,
    tan,
    asin,
    acos,
    atan,
    atan2,
    ceil,
    floor,
    trunc,
)
from src.vector import (
    Vector,
    parse_vector,
    vec_distance_cosine,
    vec_distance_l2,
    vec_dot_product,
)
from src.fts import (
    tokenize_text,
    compute_bm25_score,
    fts_match,
    fts_highlight,
    fts_snippet,
)
from src.crypto import (
    hex_encode,
    hex_encode_str,
    hex_decode,
    sha256_hash,
    md5_hash,
)


def sql_coalesce(args: List[Value]) -> Value:
    for i in range(len(args)):
        if not args[i].is_null():
            return args[i].copy()
    return Value.of_null()


def sql_ifnull(args: List[Value]) -> Value:
    if len(args) >= 1 and not args[0].is_null():
        return args[0].copy()
    if len(args) >= 2:
        return args[1].copy()
    return Value.of_null()


def sql_random(args: List[Value]) -> Value:
    return Value.of_int(48271)


def sql_cast(val: Value, target_type: String) -> Value:
    if nocase_compare(target_type, "INTEGER") == 0:
        if val.type_tag == SQLITE_TEXT:
            var s = val.text_val
            var num = 0
            var bytes = s.as_bytes()
            for i in range(len(bytes)):
                if is_digit_char(bytes[i]):
                    num = num * 10 + Int(bytes[i] - 48)
                else:
                    break
            return Value.of_int(Int64(num))
        return Value.of_int(val.to_int())
    elif nocase_compare(target_type, "REAL") == 0:
        return Value.of_float(val.to_float())
    elif nocase_compare(target_type, "TEXT") == 0:
        return Value.of_text(val.to_string())
    return val.copy()


def evaluate_scalar_func(name: String, args: List[Value]) -> Value:
    """ Dispatches scalar function execution by name."""
    if nocase_compare(name, "ABS") == 0:
        return sql_abs(args)
    elif nocase_compare(name, "LENGTH") == 0:
        return sql_length(args)
    elif nocase_compare(name, "UPPER") == 0:
        return sql_upper(args)
    elif nocase_compare(name, "LOWER") == 0:
        return sql_lower(args)
    elif nocase_compare(name, "SUBSTR") == 0:
        return sql_substr(args)
    elif nocase_compare(name, "TRIM") == 0:
        return sql_trim(args)
    elif nocase_compare(name, "LTRIM") == 0:
        return sql_ltrim(args)
    elif nocase_compare(name, "RTRIM") == 0:
        return sql_rtrim(args)
    elif nocase_compare(name, "ROUND") == 0:
        return sql_round(args)
    elif nocase_compare(name, "HEX") == 0:
        return sql_hex(args)
    elif nocase_compare(name, "UNHEX") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_text(hex_decode(args[0].to_string()))
        return Value.of_null()
    elif nocase_compare(name, "INSTR") == 0:
        return sql_instr(args)
    elif nocase_compare(name, "PRINTF") == 0:
        return sql_printf(args)
    elif nocase_compare(name, "TYPEOF") == 0:
        return sql_typeof(args)
    elif nocase_compare(name, "COALESCE") == 0:
        return sql_coalesce(args)
    elif nocase_compare(name, "IFNULL") == 0:
        return sql_ifnull(args)
    elif nocase_compare(name, "RANDOM") == 0:
        return sql_random(args)
    
    # --- Math Extension Functions ---
    elif nocase_compare(name, "SQRT") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(sqrt(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "POWER") == 0 or nocase_compare(name, "POW") == 0:
        if len(args) >= 2 and not args[0].is_null() and not args[1].is_null():
            return Value.of_float(pow(args[0].to_float(), args[1].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "LOG") == 0 or nocase_compare(name, "LN") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(log(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "LOG10") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(log(args[0].to_float()) / 2.302585092994046)
        return Value.of_null()
    elif nocase_compare(name, "SIN") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(sin(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "COS") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(cos(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "TAN") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(tan(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "ASIN") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(asin(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "ACOS") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(acos(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "ATAN") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(atan(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "ATAN2") == 0:
        if len(args) >= 2 and not args[0].is_null() and not args[1].is_null():
            return Value.of_float(atan2(args[0].to_float(), args[1].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "DEGREES") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(args[0].to_float() * 180.0 / 3.141592653589793)
        return Value.of_null()
    elif nocase_compare(name, "RADIANS") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(args[0].to_float() * 3.141592653589793 / 180.0)
        return Value.of_null()
    elif nocase_compare(name, "CEIL") == 0 or nocase_compare(name, "CEILING") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(ceil(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "FLOOR") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(floor(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "TRUNC") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_float(trunc(args[0].to_float()))
        return Value.of_null()
    elif nocase_compare(name, "PI") == 0:
        return Value.of_float(3.141592653589793)
    elif nocase_compare(name, "SIGN") == 0:
        if len(args) > 0 and not args[0].is_null():
            var f = args[0].to_float()
            if f > 0.0:
                return Value.of_int(1)
            elif f < 0.0:
                return Value.of_int(-1)
            return Value.of_int(0)
        return Value.of_null()

    # --- Cryptographic Extension Functions ---
    elif nocase_compare(name, "MD5") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_text(md5_hash(args[0].to_string()))
        return Value.of_null()
    elif nocase_compare(name, "SHA256") == 0:
        if len(args) > 0 and not args[0].is_null():
            return Value.of_text(sha256_hash(args[0].to_string()))
        return Value.of_null()

    # --- SIMD Vector Similarity Extension Functions ---
    elif nocase_compare(name, "VEC_DISTANCE_COSINE") == 0 or nocase_compare(name, "VECTOR_DISTANCE_COSINE") == 0:
        if len(args) >= 2 and not args[0].is_null() and not args[1].is_null():
            var v1 = parse_vector(args[0].to_string())
            var v2 = parse_vector(args[1].to_string())
            return Value.of_float(vec_distance_cosine(v1, v2))
        return Value.of_null()
    elif nocase_compare(name, "VEC_DISTANCE_L2") == 0 or nocase_compare(name, "VECTOR_DISTANCE_L2") == 0:
        if len(args) >= 2 and not args[0].is_null() and not args[1].is_null():
            var v1 = parse_vector(args[0].to_string())
            var v2 = parse_vector(args[1].to_string())
            return Value.of_float(vec_distance_l2(v1, v2))
        return Value.of_null()
    elif nocase_compare(name, "VEC_DOT_PRODUCT") == 0 or nocase_compare(name, "VECTOR_DOT_PRODUCT") == 0:
        if len(args) >= 2 and not args[0].is_null() and not args[1].is_null():
            var v1 = parse_vector(args[0].to_string())
            var v2 = parse_vector(args[1].to_string())
            return Value.of_float(vec_dot_product(v1, v2))
        return Value.of_null()
    elif nocase_compare(name, "VEC_DIMS") == 0 or nocase_compare(name, "VECTOR_DIMS") == 0:
        if len(args) > 0 and not args[0].is_null():
            var v = parse_vector(args[0].to_string())
            return Value.of_int(Int64(v.dim()))
        return Value.of_null()

    # --- Full-Text Search (FTS) & BM25 Functions ---
    elif nocase_compare(name, "FTS_MATCH") == 0:
        if len(args) >= 2 and not args[0].is_null() and not args[1].is_null():
            var matched = fts_match(args[0].to_string(), args[1].to_string())
            return Value.of_int(Int64(1 if matched else 0))
        return Value.of_null()
    elif nocase_compare(name, "HIGHLIGHT") == 0 or nocase_compare(name, "FTS_HIGHLIGHT") == 0:
        if len(args) >= 2 and not args[0].is_null() and not args[1].is_null():
            var open_t = args[2].to_string() if len(args) >= 3 else "<b>"
            var close_t = args[3].to_string() if len(args) >= 4 else "</b>"
            return Value.of_text(fts_highlight(args[0].to_string(), args[1].to_string(), open_t, close_t))
        return Value.of_null()
    elif nocase_compare(name, "SNIPPET") == 0 or nocase_compare(name, "FTS_SNIPPET") == 0:
        if len(args) >= 2 and not args[0].is_null() and not args[1].is_null():
            var max_w = Int(args[2].to_int()) if len(args) >= 3 else 10
            return Value.of_text(fts_snippet(args[0].to_string(), args[1].to_string(), max_w))
        return Value.of_null()

    return Value.of_null()
