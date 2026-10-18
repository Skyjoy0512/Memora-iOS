#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import json
project = json.load(open('Project.json'))
info = project['targets']['Memora']['info']['properties']
assert 'app.memora.summaries.processing' in info['BGTaskSchedulerPermittedIdentifiers']
assert 'processing' in info['UIBackgroundModes']
PY
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-background-summary.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/AIEngine.swift App/MemoraIntelligence.swift App/LLMSelection.swift \
  App/LLMProvider.swift App/LLMModelOption.swift App/SummaryTemplate.swift App/SummaryMarketTemplate.swift \
  App/SummaryTemplateCategory.swift App/SummaryTemplateChoice.swift App/SummaryPreferences.swift \
  App/SummaryLength.swift App/SummarySensitivity.swift App/PendingSummaryJob.swift \
  tools/checks/BackgroundSummaryJobChecks.swift -o "$check_dir/check"
"$check_dir/check"
