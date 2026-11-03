#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-chunk-writer.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_AUDIO_DIAGNOSTICS_DIRECTORY="$check_dir/diagnostics"
export SWIFT_BACKTRACE=enable=no
source tools/checks/audio-diagnostic-sources.sh
swiftc -swift-version 6 -D MEMORA_HOST_CHECKS "${audio_diagnostic_sources[@]}" \
  App/RecordingAudioPart.swift App/RecordingAudioManifest.swift App/RecordingRotation.swift \
  App/SourceMediaFailure.swift App/SourceMediaStageLease.swift App/SourceMediaStaging.swift \
  App/RecordingChunkWriter.swift tools/checks/RecordingChunkWriterChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
