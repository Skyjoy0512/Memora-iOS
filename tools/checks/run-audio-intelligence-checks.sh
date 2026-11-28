#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-audio-intelligence.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
source tools/checks/audio-diagnostic-sources.sh
swiftc "${audio_diagnostic_sources[@]}" App/AudioLevelMath.swift App/AudioSignalInspector.swift App/VoiceActivityTimeline.swift App/VoiceActivityModelAssets.swift \
  App/SourceMediaChunk.swift App/SourceMediaFailure.swift App/AudioProcessingReadiness.swift tools/checks/AudioIntelligenceChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
