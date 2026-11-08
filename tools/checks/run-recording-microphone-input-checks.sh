#!/bin/bash
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-microphone-input.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export SWIFT_BACKTRACE=enable=no
swiftc -swift-version 6 -D MEMORA_HOST_CHECKS \
  App/RecordingInputContinuity.swift App/RecordingMicrophoneInput.swift App/AudioTapTiming.swift \
  App/LiveAudioBufferConverter.swift tools/checks/RecordingMicrophoneInputChecks.swift \
  -o "$check_dir/checks"
"$check_dir/checks"
