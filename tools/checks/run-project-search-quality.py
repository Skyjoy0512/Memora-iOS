#!/usr/bin/env python3
"""Run the synthetic retrieval corpus without starting the app or calling an API."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref", help="Measure the two ranking files at a Git revision; skips quality gates")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="memora-search-quality-", dir=os.environ.get("MEMORA_CHECK_ROOT")) as temporary:
        directory = Path(temporary)
        names = ["ProjectCitation", "ProjectEvidenceChunk", "ProjectEvidenceInput", "ProjectSourceText",
                 "ProjectContextBuilder", "ProjectSearchIndex"]
        sources = []
        for name in names:
            source = root / "App" / f"{name}.swift"
            if args.baseline_ref and name in {"ProjectContextBuilder", "ProjectSearchIndex"}:
                source = directory / f"{name}.swift"
                source.write_bytes(subprocess.check_output(["git", "show", f"{args.baseline_ref}:App/{name}.swift"], cwd=root))
            sources.append(str(source))
        executable = directory / "quality"
        subprocess.run(["swiftc", *sources, str(root / "tools/checks/ProjectSearchQualityChecks.swift"),
                        "-lsqlite3", "-o", str(executable)], check=True, cwd=root)
        command = [str(executable), str(root / "tools/checks/fixtures/project-search-quality.json"), str(directory)]
        if args.baseline_ref:
            command.append("--measure-only")
        subprocess.run(command, check=True, cwd=root, env={**os.environ, "SWIFT_BACKTRACE": "enable=no"}, timeout=120)


if __name__ == "__main__":
    main()
