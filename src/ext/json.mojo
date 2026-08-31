""" Pure Mojo SQLite-compatible JSON parsing and path extraction engine.

Supports SQLite JSON1 extension semantics:
- json_extract(json, path) / -> / ->>
- json_array_length(json, path)
- json_type(json, path)
- json_valid(json)
"""

from src.engine.row import Value
from src.core.types import SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_NULL
from src.core.utf import nocase_compare

comptime JSON_NULL = 0
comptime JSON_BOOL = 1
comptime JSON_INT = 2
comptime JSON_REAL = 3
comptime JSON_TEXT = 4
comptime JSON_ARRAY = 5
comptime JSON_OBJECT = 6


struct JsonValue(ImplicitlyCopyable, Copyable, Movable):
    var tag: Int
    var raw_val: String
    var int_val: Int64
    var float_val: Float64
    var bool_val: Bool
    var keys: List[String]
    var values: List[JsonValue]

    def __init__(out self, tag: Int = JSON_NULL, raw_val: String = ""):
        self.tag = tag
        self.raw_val = raw_val
        self.int_val = 0
        self.float_val = 0.0
        self.bool_val = False
        self.keys = List[String]()
        self.values = List[JsonValue]()

    def __init__(out self, *, copy: Self):
        self.tag = copy.tag
        self.raw_val = copy.raw_val
        self.int_val = copy.int_val
        self.float_val = copy.float_val
        self.bool_val = copy.bool_val
        self.keys = copy.keys.copy()
        self.values = copy.values.copy()

    def __init__(out self, *, deinit move: Self):
        self.tag = move.tag
        self.raw_val = move.raw_val^
        self.int_val = move.int_val
        self.float_val = move.float_val
        self.bool_val = move.bool_val
        self.keys = move.keys^
        self.values = move.values^

    def __deinit__(deinit self):
        pass

    def is_null(self) -> Bool:
        return self.tag == JSON_NULL

    def to_sqlite_value(self, unquote: Bool = False) -> Value:
        if self.tag == JSON_NULL:
            return Value.of_null()
        elif self.tag == JSON_BOOL:
            return Value.of_int(Int64(1 if self.bool_val else 0)) if unquote else Value.of_text("true" if self.bool_val else "false")
        elif self.tag == JSON_INT:
            return Value.of_int(self.int_val)
        elif self.tag == JSON_REAL:
            return Value.of_float(self.float_val)
        elif self.tag == JSON_TEXT:
            if unquote:
                return Value.of_text(self.raw_val)
            return Value.of_text("\"" + self.raw_val + "\"")
        else:
            return Value.of_text(self.raw_val)


def _skip_ws(bytes: Span[UInt8, _], mut pos: Int):
    var n = len(bytes)
    while pos < n:
        var c = bytes[pos]
        if c == 32 or c == 9 or c == 10 or c == 13: # ' ', '\t', '\n', '\r'
            pos += 1
        else:
            break


def _parse_json_string(bytes: Span[UInt8, _], mut pos: Int) raises -> String:
    var n = len(bytes)
    if pos >= n or bytes[pos] != 34: # '"'
        raise Error("Expected '\"'")
    pos += 1 # skip '"'
    var res = String()
    while pos < n:
        var c = bytes[pos]
        if c == 34: # '"'
            pos += 1
            return res^
        elif c == 92: # '\\'
            pos += 1
            if pos >= n:
                raise Error("Unterminated escape sequence in JSON string")
            var esc = bytes[pos]
            if esc == 34 or esc == 92 or esc == 47: # '"', '\\', '/'
                res += chr(Int(esc))
            elif esc == 98: # 'b'
                res += chr(8)
            elif esc == 102: # 'f'
                res += chr(12)
            elif esc == 110: # 'n'
                res += "\n"
            elif esc == 114: # 'r'
                res += "\r"
            elif esc == 116: # 't'
                res += "\t"
            elif esc == 117: # 'u'
                pos += 4 # Skip \uXXXX for simplicity
                res += "?"
            pos += 1
        else:
            res += chr(Int(c))
            pos += 1
    raise Error("Unterminated JSON string")


def _parse_json_val(bytes: Span[UInt8, _], mut pos: Int) raises -> JsonValue:
    _skip_ws(bytes, pos)
    var n = len(bytes)
    if pos >= n:
        raise Error("Unexpected end of JSON input")

    var c = bytes[pos]

    # Object
    if c == 123: # '{'
        var start = pos
        pos += 1
        var val = JsonValue(JSON_OBJECT)
        _skip_ws(bytes, pos)
        if pos < n and bytes[pos] == 125: # '}'
            pos += 1
            var raw = String()
            for k in range(start, pos):
                raw += chr(Int(bytes[k]))
            val.raw_val = raw^
            return val^

        while pos < n:
            _skip_ws(bytes, pos)
            var key = _parse_json_string(bytes, pos)
            _skip_ws(bytes, pos)
            if pos >= n or bytes[pos] != 58: # ':'
                raise Error("Expected ':' in JSON object")
            pos += 1 # skip ':'
            var child = _parse_json_val(bytes, pos)
            val.keys.append(key^)
            val.values.append(child^)
            _skip_ws(bytes, pos)
            if pos < n and bytes[pos] == 44: # ','
                pos += 1
            elif pos < n and bytes[pos] == 125: # '}'
                pos += 1
                break
            else:
                raise Error("Expected ',' or '}' in JSON object")

        var raw = String()
        for k in range(start, pos):
            raw += chr(Int(bytes[k]))
        val.raw_val = raw^
        return val^

    # Array
    elif c == 91: # '['
        var start = pos
        pos += 1
        var val = JsonValue(JSON_ARRAY)
        _skip_ws(bytes, pos)
        if pos < n and bytes[pos] == 93: # ']'
            pos += 1
            var raw = String()
            for k in range(start, pos):
                raw += chr(Int(bytes[k]))
            val.raw_val = raw^
            return val^

        while pos < n:
            _skip_ws(bytes, pos)
            var child = _parse_json_val(bytes, pos)
            val.values.append(child^)
            _skip_ws(bytes, pos)
            if pos < n and bytes[pos] == 44: # ','
                pos += 1
            elif pos < n and bytes[pos] == 93: # ']'
                pos += 1
                break
            else:
                raise Error("Expected ',' or ']' in JSON array")

        var raw = String()
        for k in range(start, pos):
            raw += chr(Int(bytes[k]))
        val.raw_val = raw^
        return val^

    # String
    elif c == 34: # '"'
        var s = _parse_json_string(bytes, pos)
        var val = JsonValue(JSON_TEXT, s)
        return val^

    # Number
    elif (c >= 48 and c <= 57) or c == 45: # '0'-'9' or '-'
        var start = pos
        var is_float = False
        while pos < n:
            var cur = bytes[pos]
            if (cur >= 48 and cur <= 57) or cur == 45 or cur == 43:
                pos += 1
            elif cur == 46 or cur == 101 or cur == 69: # '.', 'e', 'E'
                is_float = True
                pos += 1
            else:
                break
        var num_str = String()
        for k in range(start, pos):
            num_str += chr(Int(bytes[k]))
        if is_float:
            var val = JsonValue(JSON_REAL, num_str)
            try:
                val.float_val = Float64(atof(num_str))
            except:
                val.float_val = 0.0
            return val^
        else:
            var val = JsonValue(JSON_INT, num_str)
            try:
                val.int_val = Int64(atol(num_str))
            except:
                val.int_val = 0
            return val^

    # Boolean / Null
    elif c == 116: # 't' (true)
        if pos + 4 <= n:
            pos += 4
            var val = JsonValue(JSON_BOOL, "true")
            val.bool_val = True
            return val^
    elif c == 102: # 'f' (false)
        if pos + 5 <= n:
            pos += 5
            var val = JsonValue(JSON_BOOL, "false")
            val.bool_val = False
            return val^
    elif c == 110: # 'n' (null)
        if pos + 4 <= n:
            pos += 4
            var val = JsonValue(JSON_NULL, "null")
            return val^

    raise Error("Invalid JSON token")


def parse_json(json_str: String) raises -> JsonValue:
    var b = json_str.as_bytes()
    var pos = 0
    var val = _parse_json_val(b, pos)
    return val^


struct JsonPathStep(ImplicitlyCopyable, Copyable, Movable):
    var is_index: Bool
    var key: String
    var index: Int

    def __init__(out self, key: String):
        self.is_index = False
        self.key = key
        self.index = -1

    def __init__(out self, index: Int):
        self.is_index = True
        self.key = ""
        self.index = index

    def __init__(out self, *, copy: Self):
        self.is_index = copy.is_index
        self.key = copy.key
        self.index = copy.index

    def __init__(out self, *, deinit move: Self):
        self.is_index = move.is_index
        self.key = move.key^
        self.index = move.index


def parse_json_path(path: String) -> List[JsonPathStep]:
    """ Parses a JSON path like '$.name', '$.address.city', '$.tags[0]', or '[1]'."""
    var steps = List[JsonPathStep]()
    var s = path.strip()
    var b = s.as_bytes()
    var n = len(b)
    var i = 0

    if i < n and b[i] == 36: # '$'
        i += 1

    while i < n:
        if b[i] == 46: # '.'
            i += 1
            var key = String()
            while i < n and b[i] != 46 and b[i] != 91: # '.' or '['
                key += chr(Int(b[i]))
                i += 1
            if key.byte_length() > 0:
                steps.append(JsonPathStep(key))
        elif b[i] == 91: # '['
            i += 1
            var idx_str = String()
            while i < n and b[i] != 93: # ']'
                idx_str += chr(Int(b[i]))
                i += 1
            if i < n and b[i] == 93: # ']'
                i += 1
            var idx: Int
            try:
                idx = Int(atol(idx_str))
            except:
                idx = 0
            steps.append(JsonPathStep(idx))
        else:
            var key = String()
            while i < n and b[i] != 46 and b[i] != 91:
                key += chr(Int(b[i]))
                i += 1
            if key.byte_length() > 0:
                steps.append(JsonPathStep(key))

    return steps^


def extract_json_by_path(root: JsonValue, steps: List[JsonPathStep]) -> Optional[JsonValue]:
    var cur = root.copy()
    for s_idx in range(len(steps)):
        var step = steps[s_idx]
        if step.is_index:
            if cur.tag != JSON_ARRAY:
                return None
            var idx = step.index
            if idx < 0 or idx >= len(cur.values):
                return None
            var next_val = cur.values[idx].copy()
            cur = next_val^
        else:
            if cur.tag != JSON_OBJECT:
                return None
            var found = False
            for k_idx in range(len(cur.keys)):
                if cur.keys[k_idx] == step.key:
                    var next_val = cur.values[k_idx].copy()
                    cur = next_val^
                    found = True
                    break
            if not found:
                return None
    return Optional(cur^)


def sql_json_extract(json_str: String, path_str: String, unquote: Bool = False) -> Value:
    try:
        var j_val = parse_json(json_str)
        var steps = parse_json_path(path_str)
        var res = extract_json_by_path(j_val, steps)
        if not res:
            return Value.of_null()
        return res.value().to_sqlite_value(unquote)
    except:
        return Value.of_null()


def sql_json_array_length(json_str: String, path_str: String = "$") -> Value:
    try:
        var j_val = parse_json(json_str)
        var steps = parse_json_path(path_str)
        var res = extract_json_by_path(j_val, steps)
        if not res:
            return Value.of_null()
        if res.value().tag == JSON_ARRAY:
            return Value.of_int(Int64(len(res.value().values)))
        return Value.of_int(0)
    except:
        return Value.of_null()


def sql_json_type(json_str: String, path_str: String = "$") -> Value:
    try:
        var j_val = parse_json(json_str)
        var steps = parse_json_path(path_str)
        var res = extract_json_by_path(j_val, steps)
        if not res:
            return Value.of_null()
        var tag = res.value().tag
        if tag == JSON_NULL:
            return Value.of_text("null")
        elif tag == JSON_BOOL:
            if res.value().bool_val:
                return Value.of_text("true")
            return Value.of_text("false")
        elif tag == JSON_INT or tag == JSON_REAL:
            return Value.of_text("integer" if tag == JSON_INT else "real")
        elif tag == JSON_TEXT:
            return Value.of_text("text")
        elif tag == JSON_ARRAY:
            return Value.of_text("array")
        elif tag == JSON_OBJECT:
            return Value.of_text("object")
        return Value.of_null()
    except:
        return Value.of_null()


def sql_json_valid(json_str: String) -> Value:
    try:
        _ = parse_json(json_str)
        return Value.of_int(1)
    except:
        return Value.of_int(0)
