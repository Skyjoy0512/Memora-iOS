"""Publish metadata and source hashes, not upstream source or local paths."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("input", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
results = json.loads(args.input.read_text())
for result in results:
    result.pop("pushed_at", None)  # A push is not necessarily a source change.
    for source in result.get("sources", []):
        source.pop("localPath", None)
        source.pop("signals", None)
args.output.write_text(json.dumps({"checkedAt": "2026-10-27", "repositories": results}, ensure_ascii=False, indent=2) + "\n")
