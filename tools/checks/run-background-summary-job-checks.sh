#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import json
project = json.load(open('Project.json'))
info = project['targets']['Memora']['info']['properties']
assert 'app.memora.summaries.processing' in info['BGTaskSchedulerPermittedIdentifiers']
assert 'processing' in info['UIBackgroundModes']
assert '$(PRODUCT_BUNDLE_IDENTIFIER).summaries.continued.*' in info['BGTaskSchedulerPermittedIdentifiers']
PY
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-background-summary.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/AIEngine.swift App/MemoraIntelligence.swift App/LLMSelection.swift \
  App/LLMProvider.swift App/LLMModelOption.swift App/SummaryTemplate.swift App/SummaryMarketTemplate.swift \
  App/SummaryProcessingMode.swift App/SummaryTemplateCategory.swift App/SummaryTemplateChoice.swift App/SummaryPreferences.swift \
  App/SummaryLength.swift App/SummarySensitivity.swift App/PendingSummaryJob.swift App/SummarySubmissionIntent.swift \
  tools/checks/BackgroundSummaryJobChecks.swift -o "$check_dir/check"
"$check_dir/check"
swiftc \
  Shared/MemoraIcon.swift App/AIEngine.swift App/MemoraIntelligence.swift App/LLMSelection.swift \
  App/LLMProvider.swift App/LLMModelOption.swift App/SummaryTemplate.swift App/SummaryMarketTemplate.swift \
  App/SummaryProcessingMode.swift App/SummaryTemplateCategory.swift App/SummaryTemplateChoice.swift App/SummaryPreferences.swift \
  App/SummaryLength.swift App/SummarySensitivity.swift App/PendingSummaryJob.swift App/SummarySubmissionIntent.swift \
  App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift \
  App/MeetingStatus.swift App/RecordPrivacy.swift App/RecordAccessPolicy.swift App/AIAnswerFailure.swift \
  App/MeetingSummary.swift App/MeetingSummaryInput.swift App/GeneratedSummaryEvidence.swift \
  App/SummaryActionItem.swift App/SummaryResponseParser.swift App/MarkdownSummaryExtractor.swift \
  App/MemoraTask.swift App/TaskRelationships.swift App/TaskProgress.swift \
  App/SummaryDiagnostics.swift App/LocalStore.swift App/ProcessingService.swift App/SummaryBackgroundScheduling.swift App/SummaryJobFingerprint.swift \
  App/MemoraModel+BackgroundSummary.swift App/MemoraModel+SummaryGeneration.swift App/MemoraModel+SummaryTasks.swift \
  tools/checks/BackgroundSummaryFixture.swift tools/checks/BackgroundSummaryExecutionChecks.swift -o "$check_dir/execution"
"$check_dir/execution"
