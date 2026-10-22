"""Exercise orchestration with temporary scripts, never the app or its data."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("quality_runner", Path(__file__).with_name("run-quality-checks.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class QualityRunnerChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get("MEMORA_CHECK_TMPDIR"))
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "repo"
        self.scripts = self.repo / "tools/checks"
        self.scripts.mkdir(parents=True)

    def tearDown(self):
        self.temp.cleanup()

    def run_checks(self, *args, suites=None):
        with patch.object(runner, "ROOT", self.repo), patch.object(runner, "SUITES", suites or runner.SUITES), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return runner.main(list(args))

    def test_list_and_invalid_options_never_run_suites(self):
        self.assertEqual(self.run_checks("--list"), 0)
        for args in [("--unknown",), ("--output-dir",), ("--list", "--output-dir", str(self.base / "out")),
                     ("--output-dir", str(self.repo / "output"))]:
            with self.assertRaises(SystemExit) as error:
                self.run_checks(*args)
            self.assertEqual(error.exception.code, 2)
        self.assertFalse((self.repo / "output").exists())

    def test_failure_is_preserved_and_later_suite_still_runs(self):
        (self.scripts / "fail.sh").write_text("exit 17\n")
        (self.scripts / "later.sh").write_text('test -d "$TMPDIR" && test "$MEMORA_CHECK_ROOT/" = "$TMPDIR"\n')
        output = self.base / "results"
        code = self.run_checks("--output-dir", str(output),
                               suites=(("failure", "bash", "fail.sh"), ("later", "bash", "later.sh")))
        self.assertEqual(code, 1)
        results = json.loads((output / "summary.json").read_text())
        self.assertEqual([item["exitCode"] for item in results], [17, 0])
        self.assertEqual([item["status"] for item in results], ["failed", "passed"])

    def test_existing_output_and_symlink_are_not_overwritten(self):
        target = self.base / "target"
        target.mkdir()
        marker = target / "summary.json"
        marker.write_text("preserve")
        link = self.base / "link"
        link.symlink_to(target, target_is_directory=True)
        for path in [target, link]:
            with self.assertRaises(SystemExit):
                self.run_checks("--output-dir", str(path))
        self.assertEqual(marker.read_text(), "preserve")

    def test_relative_temp_root_becomes_absolute_for_children(self):
        (self.scripts / "check.sh").write_text('case "$TMPDIR" in /*) exit 0;; *) exit 9;; esac\n')
        previous = Path.cwd()
        try:
            os.chdir(self.base)
            with patch.dict(os.environ, {"MEMORA_CHECK_ROOT": "relative"}):
                self.assertEqual(self.run_checks(suites=(("check", "bash", "check.sh"),)), 0)
            self.assertEqual(len(list((self.base / "relative").glob("*/summary.json"))), 1)
            self.assertFalse((self.repo / "relative").exists())
        finally:
            os.chdir(previous)


if __name__ == "__main__":
    unittest.main()
