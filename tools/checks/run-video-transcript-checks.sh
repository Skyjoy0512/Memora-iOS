#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-video-transcript.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/LocalStore.swift App/MemoraSpace.swift App/RecordPrivacy.swift \
  App/SummarySensitivity.swift App/SummaryMarketTemplate.swift App/SummaryTemplateCategory.swift \
  App/SummaryLength.swift App/SummaryUseCase.swift App/VideoSummaryTemplate.swift \
  App/ProjectSource.swift App/ProjectCitation.swift App/LocalImportContext.swift \
  App/Meeting.swift App/MeetingSource.swift App/MeetingStatus.swift App/TranscriptSegment.swift \
  App/SpeakerIdentificationStatus.swift App/RecordingMarker.swift App/AudioInbox.swift \
  App/VideoTranscript.swift App/MemoraModel+VideoTranscript.swift \
  tools/checks/AudioImportFixtureServices.swift tools/checks/VideoTranscriptImportFixture.swift \
  tools/checks/VideoTranscriptImportChecks.swift -lsqlite3 -o "$check_dir/check"
"$check_dir/check"
