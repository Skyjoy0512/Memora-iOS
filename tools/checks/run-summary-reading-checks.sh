#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-summary-reading.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
sources=(Shared/MemoraIcon.swift App/SummaryProcessingMode.swift App/ReadabilityGuide.swift App/SummaryPrompt.swift
  App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift App/MemoraFormat.swift
  App/SummaryArtifactScope.swift App/MeetingSummaryInput.swift App/SummaryTemplate.swift App/SummaryMarketTemplate.swift
  App/SummaryTemplateChoice.swift App/SummaryUseCase.swift App/VideoSummaryTemplate.swift App/SummarySensitivity.swift App/SummaryLength.swift
  App/SummaryPreferences.swift App/SummaryTemplateCategory.swift App/SummaryTemplateCatalog.swift App/SummaryTemplateCatalog+Workflows.swift
  App/OccupationSummaryTemplates.swift App/SummaryTemplateSelector.swift)
swiftc "${sources[@]}" tools/checks/SummaryPromptChecks.swift -o "$check_dir/prompt"
"$check_dir/prompt"
swiftc "${sources[@]}" App/TranscriptReadability.swift tools/checks/TranscriptReadabilityChecks.swift -o "$check_dir/transcript"
"$check_dir/transcript"
swiftc App/SummaryKnowledge.swift App/MarkdownBlock.swift App/SourcedMarkdownBlock.swift App/MarkdownFence.swift App/MarkdownBlockParser.swift \
  App/SummaryActionItem.swift App/GeneratedSummaryEvidence.swift App/MeetingSummary.swift \
  App/SummaryResponseParser.swift App/MarkdownSummaryExtractor.swift App/MeetingSummaryPosterSection.swift App/MeetingSummaryPosterContent.swift \
  tools/checks/MeetingSummaryPosterChecks.swift -o "$check_dir/poster"
"$check_dir/poster"
swiftc App/RecordPrivacy.swift App/SummarySensitivity.swift App/MeetingSummaryPosterSnapshot.swift \
  tools/checks/MeetingSummaryPosterAccessChecks.swift -o "$check_dir/poster-access"
"$check_dir/poster-access"
swiftc App/LocalStore.swift App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift \
  App/MemoraModel+Meetings.swift tools/checks/MeetingEditChecks.swift -o "$check_dir/meeting-edit"
"$check_dir/meeting-edit"
source tools/checks/audio-diagnostic-sources.sh
layout_sources=(App/SummaryKnowledge.swift "${sources[@]}" App/SummaryTopic.swift App/SummaryRelation.swift App/SummaryRelationMarkdown.swift
  App/SummaryMarkdownBuilder.swift App/SummaryActionItem.swift App/SummaryResponseParser.swift
  App/GeneratedSummaryEvidence.swift App/MeetingSummary.swift App/MarkdownSummaryExtractor.swift)
swiftc "${layout_sources[@]}" "${audio_diagnostic_sources[@]}" App/SummaryNoteHierarchy.swift App/AIEngine.swift App/MemoraIntelligence.swift App/LLMSelection.swift \
  App/LLMProvider.swift App/LLMModelOption.swift App/AIAnswerFailure.swift App/AIAnswerResult.swift \
  App/SummaryDiagnostics.swift App/ModelCapabilities.swift App/ModelCapabilityRegistry.swift App/SummaryProviderAdapter.swift App/SummaryGenerationPolicy.swift App/SummaryTokenBudget.swift App/SummaryInputPartition.swift App/SummaryPartScheduler.swift App/SummarySourceIndex.swift App/CloudHTTPTransport.swift App/LocalStore.swift App/SummaryArtifactCache.swift App/SummaryArtifactIdentity.swift App/SummaryPartArtifact.swift App/SummaryCompositionPlan.swift App/SummaryOptimizationGate.swift App/MeetingSummarizer+ParallelComposition.swift App/MeetingSummarizer.swift \
  tools/checks/ParallelCompositionChecks.swift tools/checks/SummaryPipelineChecks.swift -o "$check_dir/pipeline"
"$check_dir/pipeline"
swiftc "${layout_sources[@]}" App/SummarySection.swift App/SummaryEvidenceLink.swift \
  tools/checks/SummaryPersonalizationChecks.swift -o "$check_dir/personalization"
"$check_dir/personalization"
swiftc "${layout_sources[@]}" tools/checks/SummaryLayoutChecks.swift -o "$check_dir/layout"
"$check_dir/layout"
swiftc "${layout_sources[@]}" App/SummaryTemplateNotes.swift tools/checks/SummaryTemplateNotesChecks.swift -o "$check_dir/template-notes"
"$check_dir/template-notes"
swiftc "${layout_sources[@]}" App/LocalStore.swift App/MarkdownBlock.swift App/SourcedMarkdownBlock.swift \
  App/MarkdownFence.swift App/MarkdownBlockParser.swift App/MarkdownBlockWriter.swift \
  tools/checks/SummaryRelationChecks.swift -o "$check_dir/relations"
"$check_dir/relations" "$@"
bash tools/checks/run-infographic-checks.sh

swiftc App/SummaryKnowledge.swift App/SummaryActionItem.swift App/GeneratedSummaryEvidence.swift App/MeetingSummary.swift \
  App/SummaryResponseParser.swift App/MarkdownSummaryExtractor.swift tools/checks/GeneratedSummaryMarkdownChecks.swift -o "$check_dir/generated-markdown"
"$check_dir/generated-markdown"

swiftc "${sources[@]}" App/AIAnswerFailure.swift App/SummaryDiagnostics.swift App/SummarySourceIndex.swift tools/checks/SummarySourceIndexChecks.swift -o "$check_dir/source-index"
"$check_dir/source-index"
