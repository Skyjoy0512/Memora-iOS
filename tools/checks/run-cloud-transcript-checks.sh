#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-cloud-transcript.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift App/CloudTranscriptDecoder.swift \
  tools/checks/CloudTranscriptChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
