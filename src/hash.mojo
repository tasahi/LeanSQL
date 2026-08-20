"""SQLite Multiplicative String Hash.

Corresponds to `strHash` in `sqlite/src/hash.c`.

Implements Knuth's multiplicative hash using the prime multiplier
0x9E3779B1 (~2^32 * (sqrt(5)-1)/2) with an 0xDF bitmask to achieve
case-insensitivity for ASCII SQL identifiers (e.g. table and column names).
"""

def str_hash(s: String) -> UInt32:
    """ Computes a 32-bit case-insensitive hash of string `s`."""
    var bytes = s.as_bytes()
    var h: UInt32 = 0
    for i in range(len(bytes)):
        var c = bytes[i]
        # Only bits 0xdf are hashed for case-insensitivity in ASCII
        h += UInt32(0xDF & c)
        h = h * UInt32(0x9E3779B1)
    return h
