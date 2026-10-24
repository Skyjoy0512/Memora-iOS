#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-summary-reading.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
sources=(Shared/MemoraIcon.swift App/ReadabilityGuide.swift App/SummaryPrompt.swift
  App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift App/MemoraFormat.swift
  App/MeetingSummaryInput.swift App/SummaryTemplate.swift App/SummaryMarketTemplate.swift
  App/SummaryTemplateChoice.swift App/SummarySensitivity.swift App/SummaryLength.swift
  App/SummaryPreferences.swift App/SummaryTemplateCategory.swift App/SummaryTemplateCatalog.swift
  App/OccupationSummaryTemplates.swift App/SummaryTemplateSelector.swift)
swiftc "${sources[@]}" tools/checks/SummaryPromptChecks.swift -o "$check_dir/prompt"
"$check_dir/prompt"
swiftc "${sources[@]}" App/TranscriptReadability.swift tools/checks/TranscriptReadabilityChecks.swift -o "$check_dir/transcript"
"$check_dir/transcript"
swiftc App/MarkdownBlock.swift App/SourcedMarkdownBlock.swift App/MarkdownFence.swift App/MarkdownBlockParser.swift \
  App/SummaryActionItem.swift App/GeneratedSummaryEvidence.swift App/MeetingSummary.swift \
  App/SummaryResponseParser.swift App/MarkdownSummaryExtractor.swift App/MeetingSummaryPosterContent.swift \
  tools/checks/MeetingSummaryPosterChecks.swift -o "$check_dir/poster"
"$check_dir/poster"
swiftc App/RecordPrivacy.swift App/SummarySensitivity.swift App/MeetingSummaryPosterSnapshot.swift \
  tools/checks/MeetingSummaryPosterAccessChecks.swift -o "$check_dir/poster-access"
"$check_dir/poster-access"
swiftc App/LocalStore.swift App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift \
  App/MemoraModel+Meetings.swift tools/checks/MeetingEditChecks.swift -o "$check_dir/meeting-edit"
"$check_dir/meeting-edit"
layout_sources=("${sources[@]}" App/SummaryTopic.swift App/SummaryRelation.swift App/SummaryRelationMarkdown.swift
  App/SummaryMarkdownBuilder.swift App/SummaryActionItem.swift App/SummaryResponseParser.swift
  App/GeneratedSummaryEvidence.swift App/MeetingSummary.swift App/MarkdownSummaryExtractor.swift)
swiftc "${layout_sources[@]}" tools/checks/SummaryLayoutChecks.swift -o "$check_dir/layout"
"$check_dir/layout"
swiftc "${layout_sources[@]}" App/LocalStore.swift App/MarkdownBlock.swift App/SourcedMarkdownBlock.swift \
  App/MarkdownFence.swift App/MarkdownBlockParser.swift App/MarkdownBlockWriter.swift \
  tools/checks/SummaryRelationChecks.swift -o "$check_dir/relations"
"$check_dir/relations" "$@"
