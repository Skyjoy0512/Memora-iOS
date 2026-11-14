#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-source-summary.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_WORKSPACE_FILES_DIRECTORY="$check_dir/workspace"
export SWIFT_BACKTRACE=enable=no
swiftc App/SummaryKnowledge.swift -D MEMORA_HOST_CHECKS Shared/MemoraIcon.swift App/LocalStore.swift App/MemoraSpace.swift \
  App/RecordPrivacy.swift App/RecordAccessPolicy.swift App/SummarySensitivity.swift App/ProjectSource.swift \
  App/SourceSummaryOptions.swift App/SummaryEngineChoice.swift App/SummaryLength.swift App/SummaryProcessingMode.swift \
  App/SummaryPreferences.swift App/SummaryTemplate.swift App/SummaryTemplateCategory.swift App/SummaryMarketTemplate.swift \
  App/SummaryTemplateChoice.swift App/SourceSummaryResolution.swift App/AIAnswerFailure.swift \
  App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift App/SummaryArtifactScope.swift App/MeetingSummaryInput.swift \
  App/ProjectSourceText.swift App/ProjectSourceFiles.swift App/ProjectSourceTextReader.swift App/IdentifiableIndex.swift \
  App/ProjectCitation.swift App/PersistenceFailurePresentation.swift App/MemoraModel+ProjectSourceStorage.swift \
  App/ProjectSourcePreparationContext.swift App/MemoraModel+ProjectSourceRecovery.swift \
  App/MemoraModel+SourceSummaryOptions.swift App/MemoraModel+SourceSummary.swift \
  tools/checks/SourceSummaryModelFixture.swift tools/checks/SourceSummaryChecks.swift \
  -lsqlite3 -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
