#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-adaptive-summary.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
sources=(Shared/MemoraIcon.swift App/SummaryKnowledge.swift App/SummaryProcessingMode.swift
  App/SummaryTemplate.swift App/SummaryMarketTemplate.swift App/SummaryTemplateChoice.swift App/SummaryTemplateCategory.swift
  App/SummarySensitivity.swift App/SummaryLength.swift App/SummaryPreferences.swift App/VideoSummaryTemplate.swift App/SummaryUseCase.swift
  App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift App/MeetingSummaryInput.swift App/MemoraFormat.swift
  App/SummarySection.swift App/SummaryEvidence.swift App/SummaryEvidenceLink.swift App/GeneratedSummaryEvidence.swift
  App/TemplateSummary.swift App/Meeting+SummaryContent.swift App/Meeting.swift App/MeetingStatus.swift App/MeetingSource.swift
  App/RecordPrivacy.swift App/RecordingMarker.swift App/RecordingAudioManifest.swift App/RecordingAudioPart.swift
  App/SummaryPreviewCache.swift App/MarkdownBlock.swift App/SourcedMarkdownBlock.swift App/MarkdownFence.swift App/MarkdownBlockParser.swift
  App/SummaryActionItem.swift App/MeetingSummary.swift App/SummaryResponseParser.swift App/MarkdownSummaryExtractor.swift)
swiftc "${sources[@]}" tools/checks/AdaptiveSummaryKnowledgeChecks.swift -o "$check_dir/knowledge"
"$check_dir/knowledge"
