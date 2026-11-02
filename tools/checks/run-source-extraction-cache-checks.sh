#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-source-cache.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_WORKSPACE_FILES_DIRECTORY="$check_dir/workspace"
export SWIFT_BACKTRACE=enable=no
source tools/checks/audio-diagnostic-sources.sh
swiftc "${audio_diagnostic_sources[@]}" App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift -D MEMORA_HOST_CHECKS Shared/MemoraIcon.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  App/ProjectSource.swift App/ProjectSourceText.swift App/ProjectSourceFiles.swift App/ProjectSourceTextReader.swift \
  App/ProjectSourceExtractionResult.swift App/SourceIntake.swift App/ConversationLinkSnapshot.swift \
  App/SourceExtractionSnapshot.swift App/SourceExtractionPersistence.swift \
  App/SourceMediaFailure.swift App/AudioProcessingReadiness.swift App/SourceMediaChunk.swift App/SourceMediaCheckpoint.swift \
  App/SourceMediaCheckpointStore.swift App/SourceMediaSnapshot.swift App/SourceMediaTranscript.swift \
  App/SourceProcessingQueue.swift App/SourceMediaStageLease.swift App/SourceMediaStaging.swift \
  App/SourceMediaAudioExport.swift App/TranscriptionOutcome.swift App/RecordedAudioTranscription.swift App/AudioSignalInspector.swift \
  tools/checks/RecordedAudioTranscriptionChecks.swift \
  App/SourceTextChunks.swift App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift \
  tools/checks/SourceMediaCheckpointChecks.swift \
  App/RecognitionLanguage.swift App/SourceExtractionCache.swift tools/checks/SourceExtractionCacheChecks.swift -lsqlite3 -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
