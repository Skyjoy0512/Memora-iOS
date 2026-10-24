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
