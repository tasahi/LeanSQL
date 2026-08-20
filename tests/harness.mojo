"""Standard Test Harness for SQLean / SQLite compatibility test suites.
"""

from src.connection import connect, Connection
from src.row import Value, Row


struct TestHarness:
    var total_passed: Int
    var total_failed: Int
    var current_suite_name: String

    def __init__(out self, suite_name: String):
        self.total_passed = 0
        self.total_failed = 0
        self.current_suite_name = suite_name

    def assert_true(mut self, test_id: String, cond: Bool, desc: String = "") raises:
        if cond:
            self.total_passed += 1
            print("  [PASS] " + test_id + " - " + desc)
        else:
            self.total_failed += 1
            print("  [FAIL] " + test_id + " - " + desc + " (Condition was False)")
            raise Error("Test assertion failed: " + test_id + " - " + desc)

    def assert_false(mut self, test_id: String, cond: Bool, desc: String = "") raises:
        self.assert_true(test_id, not cond, desc)

    def assert_equal(mut self, test_id: String, actual: String, expected: String, desc: String = "") raises:
        if actual == expected:
            self.total_passed += 1
            print("  [PASS] " + test_id + " - " + desc)
        else:
            self.total_failed += 1
            print("  [FAIL] " + test_id + " - " + desc + " (Expected: '" + expected + "', Got: '" + actual + "')")
            raise Error("Test assertion failed: " + test_id + " - " + desc + " (Expected: '" + expected + "', Got: '" + actual + "')")

    def assert_equal_int(mut self, test_id: String, actual: Int64, expected: Int64, desc: String = "") raises:
        if actual == expected:
            self.total_passed += 1
            print("  [PASS] " + test_id + " - " + desc)
        else:
            self.total_failed += 1
            print("  [FAIL] " + test_id + " - " + desc + " (Expected: " + String(expected) + ", Got: " + String(actual) + ")")
            raise Error("Test assertion failed: " + test_id + " - " + desc + " (Expected: " + String(expected) + ", Got: " + String(actual) + ")")

    def assert_equal_int(mut self, test_id: String, actual: Int, expected: Int, desc: String = "") raises:
        self.assert_equal_int(test_id, Int64(actual), Int64(expected), desc)

    def assert_equal_float(mut self, test_id: String, actual: Float64, expected: Float64, tolerance: Float64 = 0.0001, desc: String = "") raises:
        var diff = actual - expected
        if diff < 0:
            diff = -diff
        if diff <= tolerance:
            self.total_passed += 1
            print("  [PASS] " + test_id + " - " + desc)
        else:
            self.total_failed += 1
            print("  [FAIL] " + test_id + " - " + desc + " (Expected: " + String(expected) + ", Got: " + String(actual) + ")")
            raise Error("Test assertion failed: " + test_id + " - " + desc)

    def summary(self):
        print("\n--- Suite Summary: " + self.current_suite_name + " ---")
        print("  Passed: " + String(self.total_passed))
        print("  Failed: " + String(self.total_failed))
        print("  Total:  " + String(self.total_passed + self.total_failed))
