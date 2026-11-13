"""Report regressions; detection is tested with the real CLI."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

CI = Path(__file__).resolve().parents[1] / "ci"
sys.path.insert(0, str(CI))
spec = importlib.util.spec_from_file_location("semgrep_report", CI / "semgrep_report.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class SemgrepReport(unittest.TestCase):
    def check(self, data, code=0):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "scan.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            return adapter.summarize(path, code, "a" * 40)

    def test_clean_source(self):
        report = self.check({"results": [], "errors": [], "paths": {"scanned": ["main.py"]}})
        self.assertFalse(report.failed)
        self.assertEqual("Passed", report.data["checks"][0]["status"])

    def test_no_source_is_not_applicable(self):
        report = self.check({"results": [], "errors": [], "paths": {"scanned": []}})
        self.assertEqual("Not applicable", report.data["checks"][0]["status"])

    def test_finding_fails_and_preserves_location(self):
        hit = {"path": "main.py", "start": {"line": 3}, "check_id": "community.rule",
               "extra": {"message": "Unsafe code"}}
        report = self.check({"results": [hit], "errors": [], "paths": {"scanned": ["main.py"]}}, 1)
        self.assertTrue(report.failed)
        self.assertIn("main.py:3", report.data["checks"][0]["errors"][0])

    def test_scanner_errors_fail_even_with_exit_zero(self):
        self.assertTrue(self.check({"results": [], "errors": [{"message": "Parse failure"}],
                                   "paths": {"scanned": []}}).failed)

    def test_configuration_exit_code_fails(self):
        self.assertTrue(self.check({"results": [], "errors": [], "paths": {"scanned": []}}, 7).failed)

    def test_findings_exit_without_findings_fails(self):
        self.assertTrue(self.check({"results": [], "errors": [], "paths": {"scanned": []}}, 1).failed)

    def test_invalid_json_structure_fails(self):
        self.assertTrue(self.check({"results": [], "errors": []}).failed)

    def test_missing_report_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(adapter.summarize(Path(directory) / "missing.json", 2, "a" * 40).failed)


if __name__ == "__main__":
    unittest.main()
