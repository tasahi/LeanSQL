from std.math import log
from src.engine.row import Value


def is_alphanumeric(b: UInt8) -> Bool:
    return (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122)


def tokenize_text(text: String) -> List[String]:
    """Tokenizes text into lowercase alphanumeric tokens."""
    var tokens = List[String]()
    var current = String()
    var b = text.as_bytes()
    for i in range(len(b)):
        var byte_val = b[i]
        if is_alphanumeric(byte_val):
            # Convert uppercase to lowercase ASCII
            if byte_val >= 65 and byte_val <= 90:
                current += chr(Int(byte_val + 32))
            else:
                current += chr(Int(byte_val))
        else:
            if current.byte_length() > 0:
                tokens.append(current)
                current = String()
    if current.byte_length() > 0:
        tokens.append(current)
    return tokens^


def compute_bm25_score( query_tokens: List[String], doc_tokens: List[String],
        total_docs: Int, doc_freqs: List[Int], avg_doc_len: Float64,
        k1: Float64 = 1.2, b: Float64 = 0.75 ) -> Float64:
    """ Calculates BM25 relevance score for a document given query tokens."""
    var doc_len = Float64(len(doc_tokens))
    var score: Float64 = 0.0

    for q_idx in range(len(query_tokens)):
        var q_term = query_tokens[q_idx]
        var df = doc_freqs[q_idx] if q_idx < len(doc_freqs) else 1
        if df <= 0:
            df = 1

        # Calculate IDF: log( (N - n + 0.5) / (n + 0.5) + 1.0 )
        var n_f = Float64(df)
        var total_f = Float64(total_docs if total_docs > 0 else 1)
        var idf = log((total_f - n_f + 0.5) / (n_f + 0.5) + 1.0)
        if idf < 0.0:
            idf = 0.0001

        # Term frequency in this document
        var tf = 0
        for d_i in range(len(doc_tokens)):
            if doc_tokens[d_i] == q_term:
                tf += 1

        if tf > 0:
            var tf_f = Float64(tf)
            var num = tf_f * (k1 + 1.0)
            var den = tf_f + k1 * (1.0 - b + b * (doc_len / (avg_doc_len if avg_doc_len > 0.0 else 1.0)))
            score += idf * (num / den)
    return score


def fts_match(text: String, query: String) -> Bool:
    """ Returns True if text matches all terms in query."""
    var doc_tokens = tokenize_text(text)
    var query_tokens = tokenize_text(query)
    if len(query_tokens) == 0:
        return False

    for q_idx in range(len(query_tokens)):
        var q = query_tokens[q_idx]
        var found = False
        for d_idx in range(len(doc_tokens)):
            if doc_tokens[d_idx] == q:
                found = True
                break
        if not found:
            return False
    return True


def fts_highlight(text: String, query: String, open_tag: String = "<b>", close_tag: String = "</b>") -> String:
    """ Wraps matched terms in text with highlighting tags."""
    var q_tokens = tokenize_text(query)
    if len(q_tokens) == 0:
        return text

    var out_str = String()
    var word = String()
    var b = text.as_bytes()
    for i in range(len(b)):
        var byte_val = b[i]
        if is_alphanumeric(byte_val):
            word += chr(Int(byte_val))
        else:
            if word.byte_length() > 0:
                var word_lower = word.lower()
                var matched = False
                for q_i in range(len(q_tokens)):
                    if word_lower == q_tokens[q_i]:
                        matched = True
                        break
                if matched:
                    out_str += open_tag + word + close_tag
                else:
                    out_str += word
                word = String()
            out_str += chr(Int(byte_val))

    if word.byte_length() > 0:
        var word_lower = word.lower()
        var matched = False
        for q_i in range(len(q_tokens)):
            if word_lower == q_tokens[q_i]:
                matched = True
                break
        if matched:
            out_str += open_tag + word + close_tag
        else:
            out_str += word

    return out_str


def fts_snippet(text: String, query: String, max_words: Int = 10) -> String:
    """ Generates an excerpt snippet centered around the query term."""
    var words = text.split()
    var q_tokens = tokenize_text(query)
    if len(words) == 0 or len(q_tokens) == 0:
        return text

    var match_idx = 0
    for w_i in range(len(words)):
        var w_toks = tokenize_text(String(words[w_i]))
        var found = False
        for wt in range(len(w_toks)):
            for qt in range(len(q_tokens)):
                if w_toks[wt] == q_tokens[qt]:
                    match_idx = w_i
                    found = True
                    break
            if found:
                break
        if found:
            break

    var start = match_idx - (max_words // 2)
    if start < 0:
        start = 0
    var end = start + max_words
    if end > len(words):
        end = len(words)

    var snip = String()
    if start > 0:
        snip += "... "
    for i in range(start, end):
        if i > start:
            snip += " "
        snip += String(words[i])
    if end < len(words):
        snip += " ..."
    return snip
