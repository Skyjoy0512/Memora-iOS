#!/bin/bash
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-live-buffer.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export SWIFT_BACKTRACE=enable=no
swiftc -swift-version 6 -D MEMORA_HOST_CHECKS \
  App/LiveAudioBufferQueue.swift \
  tools/checks/LiveAudioBufferQueueChecks.swift \
  -o "$check_dir/checks"
"$check_dir/checks"
