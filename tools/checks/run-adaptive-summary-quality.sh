#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-summary-quality.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
baseline=342094666b366f5420bfe09d48f478ba08ea30ea
for name in SummaryMarkdownBuilder SummaryPrompt ReadabilityGuide SummaryTemplateCatalog; do
  git show "$baseline:App/$name.swift" | sed -e "s/enum $name/enum Baseline$name/" -e 's/ReadabilityGuide\./BaselineReadabilityGuide./g' > "$check_dir/Baseline$name.swift"
done
git show "$baseline:App/SummaryTemplateCatalog+Workflows.swift" | sed 's/extension SummaryTemplateCatalog/extension BaselineSummaryTemplateCatalog/' > "$check_dir/BaselineWorkflows.swift"
sources=(Shared/MemoraIcon.swift App/SummaryKnowledge.swift App/SummaryProcessingMode.swift App/ReadabilityGuide.swift App/SummaryPrompt.swift
  App/TranscriptSegment.swift App/SpeakerIdentificationStatus.swift App/MemoraFormat.swift App/SummaryArtifactScope.swift App/MeetingSummaryInput.swift
  App/SummaryTemplate.swift App/SummaryMarketTemplate.swift App/SummaryTemplateChoice.swift App/SummaryUseCase.swift
  App/VideoSummaryTemplate.swift App/SummarySensitivity.swift App/SummaryLength.swift App/SummaryPreferences.swift
  App/SummaryTemplateCategory.swift App/SummaryTemplateCatalog.swift App/SummaryTemplateCatalog+Workflows.swift App/OccupationSummaryTemplates.swift
  App/SummaryTopic.swift App/SummaryRelation.swift App/SummaryRelationMarkdown.swift App/SummaryMarkdownBuilder.swift
  App/SummaryActionItem.swift App/SummaryResponseParser.swift App/GeneratedSummaryEvidence.swift App/MeetingSummary.swift App/MarkdownSummaryExtractor.swift App/TokenEstimate.swift)
swiftc "${sources[@]}" "$check_dir"/Baseline*.swift tools/checks/AdaptiveSummaryQualityChecks.swift -o "$check_dir/quality"
"$check_dir/quality" tools/checks/fixtures/adaptive-summary-quality.json "${1:-$check_dir/results}"
