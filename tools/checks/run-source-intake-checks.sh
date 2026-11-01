#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-source-intake.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_WORKSPACE_FILES_DIRECTORY="$check_dir/workspace"
export SWIFT_BACKTRACE=enable=no
swiftc App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift -D MEMORA_HOST_CHECKS Shared/MemoraIcon.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  App/ProjectSource.swift App/ProjectSourceText.swift App/ProjectSourceFiles.swift App/ProjectSourceTextReader.swift \
  App/ProjectSourceExtractionResult.swift App/PDFPageCheckpoint.swift App/PDFCheckpointStore.swift \
  App/PDFSourceSnapshot.swift App/PDFSourceExtraction.swift App/SourceExtractionSnapshot.swift \
  App/SourceTextChunks.swift App/SubtitleText.swift \
  App/ProjectCitation.swift App/ProjectEvidenceChunk.swift App/ProjectEvidenceInput.swift App/ProjectContextBuilder.swift \
  App/ProjectSearchIndex.swift App/SourceContentSearch.swift App/SourceTextSelection.swift App/SourceEvidenceRanking.swift \
  tools/checks/SourceIntakeChecks.swift -lsqlite3 -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
