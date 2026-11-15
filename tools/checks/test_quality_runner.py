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

    def test_source_mutation_does_not_report_a_passing_process_as_valid(self):
        app = self.repo / "App"
        app.mkdir()
        (app / "value.swift").write_text("original")
        (self.scripts / "change.sh").write_text("printf changed >> App/value.swift\n")
        (self.scripts / "later.sh").write_text("touch must-not-run\n")
        output = self.base / "changed"
        self.assertEqual(self.run_checks("--output-dir", str(output),
            suites=(("change", "bash", "change.sh"), ("later", "bash", "later.sh"))), 1)
        result = json.loads((output / "summary.json").read_text())
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["exitCode"], 0)
        self.assertEqual(result[0]["status"], "sourceChanged")
        self.assertNotEqual(result[0]["sourceSHA256"], result[0]["observedSnapshot"]["sha256"])
        self.assertFalse((self.repo / "must-not-run").exists())

    def test_added_and_deleted_inputs_are_detected(self):
        app = self.repo / "App"
        app.mkdir()
        for action, script in [("add", "printf content >App/new.swift\n"), ("delete", "rm App/value.swift\n")]:
            (app / "value.swift").write_text("original")
            (self.scripts / "change.sh").write_text(script)
            output = self.base / action
            self.assertEqual(self.run_checks("--output-dir", str(output), suites=(("change", "bash", "change.sh"),)), 1)
            self.assertEqual(json.loads((output / "summary.json").read_text())[0]["status"], "sourceChanged")

    def test_restored_bytes_still_invalidate_the_run(self):
        (self.repo / "App").mkdir()
        (self.repo / "App/value.swift").write_text("original")
        (self.scripts / "change.sh").write_text("printf original >App/value.swift\n")
        output = self.base / "restored"
        self.assertEqual(self.run_checks("--output-dir", str(output), suites=(("change", "bash", "change.sh"),)), 1)
        result = json.loads((output / "summary.json").read_text())[0]
        self.assertEqual(result["status"], "sourceChanged")
        self.assertEqual(result["sourceSHA256"], result["observedSnapshot"]["sha256"])
        original = json.loads((output / "source-snapshot.json").read_text())
        self.assertNotEqual(original["fileRevisionsSHA256"], result["observedSnapshot"]["fileRevisionsSHA256"])

    def test_unrelated_document_edits_keep_the_same_fingerprint(self):
        (self.repo / "docs").mkdir()
        (self.scripts / "check.sh").write_text("printf note >docs/progress.md\n")
        output = self.base / "stable"
        self.assertEqual(self.run_checks("--output-dir", str(output), suites=(("check", "bash", "check.sh"),)), 0)
        snapshot = json.loads((output / "source-snapshot.json").read_text())
        self.assertEqual(len(snapshot["sha256"]), 64)
        self.assertEqual(snapshot["fileCount"], 1)
        self.assertEqual(json.loads((output / "summary.json").read_text())[0]["sourceSHA256"], snapshot["sha256"])

    def test_unreadable_snapshot_cannot_start_a_suite(self):
        (self.scripts / "check.sh").write_text("touch must-not-run\n")
        output = self.base / "unreadable"
        with patch.object(runner, "source_snapshot", side_effect=OSError("fixture unreadable")):
            self.assertEqual(self.run_checks("--output-dir", str(output), suites=(("check", "bash", "check.sh"),)), 1)
        self.assertFalse((self.repo / "must-not-run").exists())
        self.assertTrue(json.loads((output / "source-snapshot.json").read_text())["inputUnavailable"])


if __name__ == "__main__":
    unittest.main()
