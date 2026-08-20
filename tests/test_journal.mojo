from src.types import *
from src.journal import Journal, JOURNAL_MAGIC_0, JOURNAL_MAGIC_7, JOURNAL_MODE_DELETE


def test_journal_recording_and_header() raises:
    print("=== Testing Rollback Journal Recording & Header ===")
    
    var j = Journal(4096, JOURNAL_MODE_DELETE)
    j.begin(10) # 10 pages initial db size
    
    var page_1_data = List[UInt8]()
    for i in range(4096):
        page_1_data.append(UInt8(i % 256))

    j.record_page(1, page_1_data)
    if not j.has_page(1):
        raise Error("Journal should have recorded page 1")
    if j.get_page_count() != 1:
        raise Error("Journal page count should be 1")

    # Second record of same page should be ignored (keep pre-image)
    var page_1_modified = List[UInt8]()
    for _ in range(4096):
        page_1_modified.append(0xFF)
    j.record_page(1, page_1_modified)
    if j.get_page_count() != 1:
        raise Error("Journal should not overwrite pre-image")

    # Header serialization
    var hdr = j.encode_header(1)
    if len(hdr) != 28:
        raise Error("Journal header must be 28 bytes")
    if hdr[0] != UInt8(JOURNAL_MAGIC_0) or hdr[7] != UInt8(JOURNAL_MAGIC_7):
        raise Error("Journal header magic mismatch")

    # Rollback
    var restored = j.rollback()
    if len(restored) != 1 or restored[0].pgno != 1:
        raise Error("Rollback failed to return preserved pages")
    if restored[0].data[0] != 0 or restored[0].data[1] != 1:
        raise Error("Restored page content corrupted")

    print("Journal recording and rollback test passed!")


def main() raises:
    test_journal_recording_and_header()
