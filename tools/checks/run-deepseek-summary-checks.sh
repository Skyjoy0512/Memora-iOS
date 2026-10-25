#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-deepseek-summary.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -O App/SummaryDiagnostics.swift App/AIAnswerFailure.swift App/AgentSessionBudget.swift \
  App/AgentToolCall.swift App/AgentTurn.swift App/CloudAgentTurnDecoder.swift App/CloudSummaryResponse.swift \
  App/CloudStreamAccumulator.swift App/CloudSSEEventDecoder.swift App/CloudTurnStreamReader.swift \
  tools/checks/DeepSeekSummaryChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
