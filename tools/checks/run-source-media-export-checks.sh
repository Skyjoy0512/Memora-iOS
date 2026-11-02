#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-source-media-export.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export SWIFT_BACKTRACE=enable=no
swiftc App/SourceMediaFailure.swift App/SourceMediaChunk.swift App/SourceMediaStageLease.swift App/SourceMediaStaging.swift \
  App/SourceMediaAudioExport.swift tools/checks/SourceMediaExportChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
