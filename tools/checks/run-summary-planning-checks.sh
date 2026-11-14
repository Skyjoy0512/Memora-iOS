#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-summary-plan.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/MemoraIntelligence.swift App/LLMModelOption.swift App/LLMProvider.swift App/LLMSelection.swift \
  App/SummaryProcessingMode.swift App/ModelCapabilities.swift App/ModelCapabilityRegistry.swift \
  App/SummaryProviderAdapter.swift App/SummaryGenerationPolicy.swift tools/checks/ModelCapabilityChecks.swift -o "$check_dir/capabilities"
"$check_dir/capabilities"
swiftc App/MemoraIntelligence.swift App/LLMModelOption.swift App/LLMProvider.swift App/LLMSelection.swift App/MemoraFormat.swift App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift App/SummarySourceIndex.swift \
  App/AIAnswerFailure.swift App/ModelCapabilities.swift App/SummaryTokenBudget.swift App/SummaryInputPartition.swift \
  tools/checks/SummaryTokenPlanningChecks.swift -o "$check_dir/budget"
"$check_dir/budget"
swiftc App/AIAnswerFailure.swift App/SummaryPartScheduler.swift tools/checks/SummaryConcurrencyChecks.swift -o "$check_dir/concurrency"
"$check_dir/concurrency"
