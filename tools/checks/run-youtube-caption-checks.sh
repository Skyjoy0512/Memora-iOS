#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-youtube-captions.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export SWIFT_BACKTRACE=enable=no
swiftc App/ProjectSourceText.swift App/SourceTextChunks.swift App/SubtitleText.swift \
  App/YouTubeCaptionEnvironment.swift App/YouTubeCaptionService.swift tools/checks/YouTubeCaptionChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
