from tests.harness import TestHarness
from tests.test_suite_01_select import run_select_tests
from tests.test_suite_02_insert import run_insert_tests
from tests.test_suite_03_update_delete import run_update_delete_tests
from tests.test_suite_04_expr import run_expr_tests
from tests.test_suite_05_null_logic import run_null_tests
from tests.test_suite_06_types import run_types_tests
from tests.test_suite_07_trans import run_trans_tests
from tests.test_suite_08_scalar_funcs import run_scalar_func_tests
from tests.test_suite_09_aggregate_funcs import run_aggregate_func_tests
from tests.test_suite_10_where_index import run_where_index_tests
from tests.test_suite_11_joins import run_join_tests
from tests.test_suite_12_compound import run_compound_tests
from tests.test_suite_13_persistence import run_persistence_tests
from tests.test_suite_14_pragma_schema import run_pragma_schema_tests
from tests.test_suite_15_alter_view import run_alter_view_tests
from tests.test_suite_16_subqueries_cte import run_subqueries_cte_tests
from tests.test_suite_17_window_funcs import run_window_funcs_tests
from tests.test_suite_18_triggers import run_triggers_tests
from tests.test_suite_19_cli import run_cli_tests
from tests.test_suite_20_c_abi import run_c_abi_tests
from tests.test_suite_22_fts import run_fts_tests
from tests.test_suite_23_vector import run_vector_tests
from tests.test_suite_24_math_crypto import run_math_crypto_tests


def main() raises:
    print("=======================================================================")
    print("           SQLean: TOP 100+ FUNDAMENTAL SQLITE TESTS SUITE             ")
    print("=======================================================================")

    var h = TestHarness("Full Extended SQLite Test Suites")

    run_select_tests(h)
    run_insert_tests(h)
    run_update_delete_tests(h)
    run_expr_tests(h)
    run_null_tests(h)
    run_types_tests(h)
    run_trans_tests(h)
    run_scalar_func_tests(h)
    run_aggregate_func_tests(h)
    run_where_index_tests(h)
    run_join_tests(h)
    run_compound_tests(h)
    run_persistence_tests(h)
    run_pragma_schema_tests(h)
    run_alter_view_tests(h)
    run_subqueries_cte_tests(h)
    run_window_funcs_tests(h)
    run_triggers_tests(h)
    run_cli_tests(h)
    run_c_abi_tests(h)
    run_fts_tests(h)
    run_vector_tests(h)
    run_math_crypto_tests(h)

    print("\n=======================================================================")
    print("                    FINAL EXTENDED TEST SUITE RESULTS                  ")
    print("=======================================================================")
    h.summary()
    print("All fundamental test suites completed successfully!")
