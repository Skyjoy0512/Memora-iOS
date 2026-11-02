#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-audio-intelligence.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/AudioSignalInspector.swift App/AudioSignalReport.swift App/VoiceActivityTimeline.swift \
  App/SourceMediaChunk.swift App/SourceMediaFailure.swift tools/checks/AudioIntelligenceChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
