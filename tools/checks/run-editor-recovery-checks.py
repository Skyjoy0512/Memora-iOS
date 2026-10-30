#!/usr/bin/env python3
"""Run production draft compatibility and review persistence regression checks."""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SUITES = [
    ["App/EditorDraftEnvelope.swift", "tools/checks/EditorDraftChecks.swift"],
    ["App/WeeklyReviewBuilder.swift", "App/WeeklyReviewResult.swift",
     "App/MemoraModel+WeeklyReview.swift", "tools/checks/WeeklyReviewPersistenceChecks.swift"],
]
with tempfile.TemporaryDirectory(prefix="memora-editor-checks-") as directory:
    for index, sources in enumerate(SUITES):
        executable = str(Path(directory) / f"checks-{index}")
        subprocess.run(["swiftc", *sources, "-o", executable], cwd=ROOT, check=True)
        subprocess.run([executable], check=True)
