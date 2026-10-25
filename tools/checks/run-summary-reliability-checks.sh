#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-summary-reliability.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/SummaryDiagnostics.swift App/AIAnswerFailure.swift App/FoundationModelFailure.swift \
  App/AgentSessionBudget.swift App/AgentToolCall.swift App/AgentTurn.swift App/CloudAgentTurnDecoder.swift App/CloudSummaryResponse.swift \
  App/CloudStreamAccumulator.swift App/CloudSSEEventDecoder.swift App/CloudTurnStreamReader.swift \
  tools/checks/LongSummaryChecks.swift -o "$check_dir/long-summary"
"$check_dir/long-summary"
bash tools/checks/run-deepseek-summary-checks.sh
