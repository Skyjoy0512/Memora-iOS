#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-recording-recovery.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_AUDIO_INBOX_DIRECTORY="$check_dir/Inbox"
export SWIFT_BACKTRACE=enable=no
swiftc -D MEMORA_HOST_CHECKS Shared/MemoraIcon.swift \
  App/LocalStore.swift App/AudioInbox.swift App/MemoraSpace.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  App/Meeting.swift App/MeetingSource.swift App/MeetingStatus.swift App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift \
  App/LifeLogEntry.swift App/LifeLogKind.swift App/LifeLogSource.swift App/LifeLogOrigin.swift \
  App/RecordingMarker.swift App/RecordingAudioValidation.swift App/ProjectFiling.swift App/MemoraModel+RecordingRecovery.swift \
  tools/checks/AudioImportFixtureServices.swift tools/checks/RecordingRecoveryStoreFixture.swift \
  tools/checks/RecordingRecoveryFixtureModel.swift tools/checks/RecordingRecoveryGate.swift \
  tools/checks/RecordingRecoveryChecks.swift -lsqlite3 -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
