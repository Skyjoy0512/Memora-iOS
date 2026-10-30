#!/usr/bin/env python3
"""Exercise the production Core Text PDF writer; optionally retain its fictional fixture."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import shutil

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path)
args = parser.parse_args()
sources = ["DocumentPDFError", "DocumentPDFProgress", "MarkdownBlock", "SourcedMarkdownBlock",
           "MarkdownFence", "MarkdownBlockParser", "DocumentPDFLayout", "DocumentPDFFile", "DocumentPDFRenderer"]
with tempfile.TemporaryDirectory(prefix="memora-pdf-checks-") as temporary:
    executable = str(Path(temporary) / "pdf-checks")
    subprocess.run(["swiftc", *[f"App/{name}.swift" for name in sources],
                    "tools/checks/DocumentPDFChecks.swift", "-o", executable], cwd=root, check=True)
    output = Path(temporary) / "output"
    subprocess.run([executable, str(output)], cwd=root, check=True)
    if args.output:
        retained = args.output.resolve()
        retained.mkdir(parents=True, exist_ok=True)
        for artifact in output.iterdir():
            if artifact.suffix in {".pdf", ".png"}:
                shutil.copy2(artifact, retained / artifact.name)

with tempfile.TemporaryDirectory(prefix="memora-pdf-session-checks-") as temporary:
    executable = str(Path(temporary) / "session-checks")
    subprocess.run(["swiftc", "App/DocumentPDFProgress.swift", "App/ArtifactExportFile.swift",
                    "App/DocumentPDFExportSession.swift", "tools/checks/DocumentPDFExportSessionChecks.swift",
                    "-o", executable], cwd=root, check=True)
    subprocess.run([executable], cwd=root, check=True)
