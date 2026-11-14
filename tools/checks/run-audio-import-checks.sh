#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-audio-import.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_WORKSPACE_FILES_DIRECTORY="$check_dir/workspace"
export MEMORA_AUDIO_INBOX_DIRECTORY="$check_dir/Inbox"
export SWIFT_BACKTRACE=enable=no
# URL fetching is outside this runner; retain the production attachment error type.
python3 - "$check_dir/intake-failure.swift" <<'PY'
from pathlib import Path
import sys
source = Path('App/ConversationSourceIntake.swift').read_text()
failure = source[source.index('  enum Failure: LocalizedError'):source.rindex('\n}')]
Path(sys.argv[1]).write_text('import Foundation\nenum ConversationSourceIntake {\n' + failure + '\n}\n')
PY
swiftc App/SummaryKnowledge.swift App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift -D MEMORA_HOST_CHECKS -D MEMORA_AUDIO_IMPORT_CHECKS -D MEMORA_SOURCE_IMPORT_CHECKS Shared/MemoraIcon.swift Shared/MemoraAppLink.swift \
  App/LocalStore.swift App/MemoraSpace.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  App/ProjectSource.swift App/ProjectCitation.swift App/IdentifiableIndex.swift App/PersistenceFailurePresentation.swift \
  App/PDFSourcePartition.swift App/PDFSourcePartitionPart.swift App/PDFSourcePartitionSnapshot.swift \
  App/PDFSourcePartitionBuilder.swift App/PDFSourcePartitionFailure.swift App/PDFSourcePartitionImportFailure.swift \
  App/PDFSourcePartitionLease.swift App/PDFSourcePartitionStaging.swift App/PDFSourceCopyLease.swift App/PDFSourceCopyJournal.swift \
  App/PDFSourcePartitioning.swift App/SourceProcessingQueue.swift App/MemoraModel+PDFSourcePartition.swift App/MemoraModel+InformationSources.swift \
  App/ProjectSourceFiles.swift App/SourceIntake.swift App/ProjectSourceText.swift App/ProjectSourceTextReader.swift App/MemoraModel+ProjectSourceImport.swift App/MemoraModel+ProjectSourceStorage.swift App/MemoraModel+InformationImport.swift App/LocalImportContext.swift App/AudioInbox.swift App/MemoraModel+Import.swift App/MemoraModel+BackupRestoreAdmission.swift App/AIAttachmentFiles.swift App/AIAttachment.swift App/MissingRecordNotice.swift \
  App/RecordingAudioPart.swift App/RecordingAudioManifest.swift App/Meeting.swift App/MeetingSource.swift App/MeetingStatus.swift App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift \
  App/RecordingMarker.swift App/ProjectFiling.swift tools/checks/ProjectSourceStorageFixture.swift \
  tools/checks/AudioImportFixtureServices.swift tools/checks/AudioImportChecks.swift "$check_dir/intake-failure.swift" -lsqlite3 -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
