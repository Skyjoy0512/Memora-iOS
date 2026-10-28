"""Prove tee cannot turn failed checks green under the workflow's explicit bash shell."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile
import unittest


class CIFailurePropagationChecks(unittest.TestCase):
    def run_pipeline(self, producer, *, broken_log=False):
        with tempfile.TemporaryDirectory(dir=os.environ.get("MEMORA_CHECK_TMPDIR")) as directory:
            root = Path(directory)
            log = root / ("missing/log" if broken_log else "check.log")
            marker = root / "later"
            script = f"({producer}) 2>&1 | tee {shlex.quote(str(log))}\nprintf reached > {shlex.quote(str(marker))}\n"
            # These are the documented arguments GitHub uses for `shell: bash`.
            result = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", script],
                                    capture_output=True, text=True, timeout=10)
            return result.returncode, marker.exists(), log.read_text() if log.exists() else None

    def test_producer_failure_keeps_log_and_stops_later_commands(self):
        code, later, log = self.run_pipeline("printf 'fixture failed\\n'; exit 17")
        self.assertEqual(code, 17)
        self.assertFalse(later)
        self.assertEqual(log, "fixture failed\n")

    def test_consumer_failure_is_not_green(self):
        code, later, _ = self.run_pipeline("printf 'fixture passed\\n'", broken_log=True)
        self.assertNotEqual(code, 0)
        self.assertFalse(later)

    def test_success_keeps_log_and_continues(self):
        code, later, log = self.run_pipeline("printf 'fixture passed\\n'")
        self.assertEqual(code, 0)
        self.assertTrue(later)
        self.assertEqual(log, "fixture passed\n")

    def test_actual_tee_step_explicitly_selects_bash(self):
        workflow = (Path(__file__).resolve().parents[2] / ".github/workflows/quality.yml").read_text()
        step = workflow.split("      - name: Check all 65 presentation layouts and inline links\n", 1)[1].split("      - ", 1)[0]
        self.assertIn("\n        shell: bash\n", "\n" + step)
        self.assertIn("python3 -B tools/checks/test_ci_failure_propagation.py", step)
        for check in ["run-presentation-checks.sh", "run-artifact-operation-checks.sh --presentation-revision",
                      "run-inline-link-checks.sh", "verify-oss-resources.py"]:
            self.assertIn(check, step)


if __name__ == "__main__":
    unittest.main()
