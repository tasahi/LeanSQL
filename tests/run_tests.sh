#!/usr/bin/env bash
set -e

# Activate conda mojo environment if not already activated
if [ -z "$CONDA_PREFIX" ] || [ "$CONDA_DEFAULT_ENV" != "moj" ]; then
    source /home/tasahi/miniconda/bin/activate moj
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "Running LeanSQL Full Extended SQLite Test Suite (100% Pure Mojo)..."
mojo run -I . tests/run_all_test_suites.mojo

echo "Running Python DB-API Driver Verification (Suite 21)..."
python tests/interop/test_leansql_python_driver.py

# Clean up temporary test files
rm -f "CREATE "* "INSERT "* "DELETE "* "UPDATE "* "SELECT "* "DROP "* suite13_persist.db test_driver_suite.db test_mem.db leansql_py_test.db
echo "Cleaned up temporary test artifacts."

