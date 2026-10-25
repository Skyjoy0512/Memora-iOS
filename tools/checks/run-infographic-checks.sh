#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-infographic.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/LocalStore.swift App/RecordPrivacy.swift App/RecordAccessPolicy.swift App/SummarySensitivity.swift \
  App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift App/MemoraModel+Meetings.swift \
  App/GroundedQuantity.swift App/MeetingInfographic.swift App/MeetingInfographicSample.swift App/SummarizedAudioSample.swift App/MeetingInfographicPrompt.swift App/MemoraModel+Infographics.swift \
  App/MeetingSummaryPosterSnapshot.swift App/MeetingQuestionSuggestions.swift App/MemoraModel+MeetingQuestions.swift \
  App/MarkdownSummaryExtractor.swift App/SummaryActionItem.swift App/SummaryResponseParser.swift \
  App/GeneratedSummaryEvidence.swift App/MeetingSummary.swift tools/checks/MeetingInfographicChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
