"""Run independent production-code suites, retaining failures and their logs."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
# The next-generation suite already includes backup, person privacy/tasks/journal,
# cloud sessions and artifacts. Design refresh includes motion/loading checks.
SUITES = (
    ("next-generation", "bash", "run-next-generation-checks.sh"),
    ("design-refresh", "bash", "run-design-refresh-checks.sh"),
    ("background-summary", "bash", "run-background-summary-job-checks.sh"),
    ("composer-layout", "bash", "run-composer-layout-checks.sh"),
    ("optimization", "python3", "run-optimization-checks.py"),
)


def external_path(value):
    path = Path(value).expanduser().resolve()
    if path == ROOT or ROOT in path.parents:
        raise ValueError("Quality artifacts must be outside the repository")
    return path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    options = parser.add_mutually_exclusive_group()
    options.add_argument("--list", action="store_true")
    options.add_argument("--output-dir", type=external_path)
    args = parser.parse_args(argv)
    if args.list:
        print("\n".join(suite[0] for suite in SUITES))
        return 0

    try:
        if args.output_dir is not None:
            output = args.output_dir
            # Never truncate caller-owned files, logs, or symlink destinations.
            output.mkdir(mode=0o700, parents=True, exist_ok=False)
        else:
            root = external_path(os.environ.get("MEMORA_CHECK_ROOT") or os.environ.get("TMPDIR") or tempfile.gettempdir())
            root.mkdir(parents=True, exist_ok=True)
            output = Path(tempfile.mkdtemp(prefix="memora-quality-", dir=root))
        scratch = output / "scratch"
        scratch.mkdir(mode=0o700)
    except (OSError, ValueError) as error:
        parser.error(str(error))

    env = os.environ.copy()
    env.update(TMPDIR=str(scratch) + "/", MEMORA_CHECK_ROOT=str(scratch),
               MEMORA_CHECK_TMPDIR=str(scratch), SWIFT_BACKTRACE="enable=no", PYTHONDONTWRITEBYTECODE="1")
    results = []
    print("Quality artifacts: " + str(output), flush=True)
    for name, interpreter, filename in SUITES:
        log = output / (name + ".log")
        result = {"suite": name, "status": "failed", "exitCode": None, "log": log.name}
        with log.open("x") as stream:
            try:
                with subprocess.Popen([interpreter, str(ROOT / "tools/checks" / filename)],
                                      cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                      start_new_session=True) as process:
                    try:
                        code = process.wait(timeout=1200)
                        result["exitCode"] = code
                        result["status"] = "passed" if code == 0 else "failed"
                    except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                        os.killpg(process.pid, signal.SIGTERM)
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait()
                        result["status"] = "interrupted" if isinstance(error, KeyboardInterrupt) else "timedOut"
            except OSError as error:
                result["status"] = "notRun"
                stream.write(str(error) + "\n")
        results.append(result)
        # An interrupted run retains only actual results, never placeholders marked passed.
        (output / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
        print(name + ": " + result["status"] + " (exit " + str(result["exitCode"]) + ")", flush=True)
        if result["status"] == "interrupted":
            return 130
    return 0 if all(result["status"] == "passed" for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
