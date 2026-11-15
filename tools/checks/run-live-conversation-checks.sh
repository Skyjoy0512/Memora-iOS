#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-live.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -O -swift-version 6 App/LiveSentenceBuffer.swift App/LiveTurnAuthority.swift App/LiveInputHealth.swift tools/checks/LiveConversationChecks.swift -o "$check_dir/live"
"$check_dir/live"
