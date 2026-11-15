#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-local-voice.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 App/LocalTokenTextBuffer.swift App/LocalVoicePrompt.swift App/LiveVoiceError.swift \
  tools/checks/LocalVoiceModelChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
