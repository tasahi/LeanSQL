from src.types import *
from src.pager import Pager, DbPage, PAGER_OPEN, PAGER_WRITER_LOCKED


def test_pager_acid_transactions() raises:
    print("=== Testing Pager ACID Transactions & Rollback ===")
    
    var pager = Pager(":memory:", 512)
    print("  Created Pager with page size:", pager.page_size())

    # 1. Acquire Page 1 and write initial data
    var page1 = pager.acquire_page(1)
    for i in range(512):
        page1.data[i] = UInt8(i % 256)
    pager.write_page(page1)
    pager.commit()
    print("  Committed Page 1 to storage. Total DB pages:", pager.page_count())

    # 2. Modify Page 1 inside a transaction and ROLLBACK
    var page1_mod = pager.acquire_page(1)
    for i in range(512):
        page1_mod.data[i] = 0xEE
    pager.write_page(page1_mod)
    
    # Assert dirty in memory
    var p_check = pager.acquire_page(1)
    if p_check.data[0] != 0xEE:
        raise Error("Page 1 should be dirty with 0xEE before rollback")

    # Perform Rollback
    pager.rollback()
    print("  Rolled back active transaction.")

    # 3. Verify Page 1 restored to original committed state
    var page1_restored = pager.acquire_page(1)
    if page1_restored.data[0] != 0 or page1_restored.data[1] != 1 or page1_restored.data[255] != 255:
        raise Error("Rollback failed to restore pre-image data on Page 1")

    print("  Page 1 pre-image successfully verified after rollback!")

    # 4. Multi-page transaction and commit
    var page2 = pager.acquire_page(2)
    page2.data[0] = 0x42
    pager.write_page(page2)
    pager.commit()

    if pager.page_count() != 2:
        raise Error("DB size should be 2 pages after adding Page 2")

    var p2_read = pager.acquire_page(2)
    if p2_read.data[0] != 0x42:
        raise Error("Page 2 data read mismatch")

    print("Pager ACID transaction tests passed successfully!")


def main() raises:
    test_pager_acid_transactions()
