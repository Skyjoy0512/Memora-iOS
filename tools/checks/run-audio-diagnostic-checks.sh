#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-audio-diagnostics.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_AUDIO_DIAGNOSTICS_DIRECTORY="$check_dir/runtime"
export SWIFT_BACKTRACE=enable=no
source tools/checks/audio-diagnostic-sources.sh
swiftc -D MEMORA_HOST_CHECKS "${audio_diagnostic_sources[@]}" tools/checks/AudioDiagnosticChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
python3 -B tools/checks/audio-measurements.py report "$check_dir/example-metrics.json" > "$check_dir/summary.json"
python3 - "$check_dir/summary.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as file:
    result = json.load(file)
assert len(result["traces"]) == 12
assert result["stageAggregates"][0]["medianRTF"] == .1
print("Swift metrics JSON → local Python report: PASS; synthetic RTF only, no model throughput claim.")
PY
