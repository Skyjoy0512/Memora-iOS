#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-intelligent-ui.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -O -swift-version 6 Shared/MemoraIcon.swift App/AgentStep.swift App/AgentActivitySummary.swift App/ToolInputValidator.swift \
  App/NativeAIInterface.swift App/NativeAIComponentStream.swift App/NativeAIResponseCache.swift tools/checks/IntelligentUIStreamingChecks.swift -o "$check_dir/ui"
"$check_dir/ui"
