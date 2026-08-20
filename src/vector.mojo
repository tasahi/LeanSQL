from std.math import sqrt
from src.row import Value


struct Vector(Copyable, Movable):
    var data: List[Float64]

    def __init__(out self):
        self.data = List[Float64]()

    def __init__(out self, values: List[Float64]):
        self.data = values.copy()

    def __moveinit__(out self, mut existing: Self):
        self.data = existing.data^

    def __copyinit__(out self, existing: Self):
        self.data = existing.data.copy()

    def dim(self) -> Int:
        return len(self.data)

    def to_json(self) -> String:
        var out_str = String("[")
        for i in range(len(self.data)):
            if i > 0:
                out_str += ", "
            out_str += String(self.data[i])
        out_str += "]"
        return out_str


def parse_vector(raw_str: String) -> Vector:
    """Parses a vector from string format like '[0.1, 0.2, 0.3]' or '0.1,0.2,0.3'."""
    var s = String(raw_str.strip())
    if s.startswith("[") and s.endswith("]"):
        s = String(s[byte=1 : s.byte_length() - 1].strip())
    
    var vec = Vector()
    if s.byte_length() == 0:
        return vec^

    var parts = s.split(",")
    for i in range(len(parts)):
        var num_str = String(parts[i].strip())
        if num_str.byte_length() > 0:
            try:
                vec.data.append(Float64(atof(num_str)))
            except:
                vec.data.append(0.0)
    return vec^


def vec_dot_product(v1: Vector, v2: Vector) -> Float64:
    """Computes the dot product of two vectors."""
    var n = len(v1.data)
    if len(v2.data) < n:
        n = len(v2.data)

    var dot: Float64 = 0.0
    for i in range(n):
        dot += v1.data[i] * v2.data[i]
    return dot


def vec_l2_norm(v: Vector) -> Float64:
    """Computes the Euclidean (L2) norm of a vector."""
    var dot = vec_dot_product(v, v)
    return sqrt(dot)


def vec_distance_l2(v1: Vector, v2: Vector) -> Float64:
    """Computes the Euclidean (L2) distance between two vectors: sqrt(sum((a_i - b_i)^2))."""
    var n = len(v1.data)
    if len(v2.data) < n:
        n = len(v2.data)

    var sum_sq: Float64 = 0.0
    for i in range(n):
        var diff = v1.data[i] - v2.data[i]
        sum_sq += diff * diff
    return sqrt(sum_sq)


def vec_distance_cosine(v1: Vector, v2: Vector) -> Float64:
    """Computes the Cosine distance: 1.0 - (v1 . v2) / (||v1|| * ||v2||)."""
    var norm1 = vec_l2_norm(v1)
    var norm2 = vec_l2_norm(v2)
    if norm1 == 0.0 or norm2 == 0.0:
        return 1.0
    var dot = vec_dot_product(v1, v2)
    var sim = dot / (norm1 * norm2)
    if sim > 1.0:
        sim = 1.0
    elif sim < -1.0:
        sim = -1.0
    return 1.0 - sim
