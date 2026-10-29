#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-scenarios.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
output_dir=${MEMORA_SCENARIO_OUTPUT:-$check_dir/output}
swiftc -DDEBUG App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift \
  App/ArtifactProjectSourceReference.swift Shared/MemoraIcon.swift App/MemoraDocumentKind.swift \
  App/SlideArchetype.swift App/SlideContent.swift App/DocumentSlide.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift \
  App/PresentationTheme.swift App/PresentationTypography.swift App/PresentationElement.swift App/PresentationText.swift \
  App/TokenEstimate.swift App/PresentationEvidencePack.swift \
  App/PresentationLayoutEngine.swift App/PresentationValidator.swift App/PresentationExportCheck.swift \
  App/PresentationOOXML.swift App/PresentationDrawing.swift App/SlidePage.swift App/SlidePageLayout.swift \
  App/ZipArchive.swift App/PPTXWriter.swift App/AIAnswerFailure.swift App/AIAnswerResult.swift \
  tools/checks/PresentationScenarioChecks.swift -o "$check_dir/scenarios"
"$check_dir/scenarios" "$output_dir"
echo "Scenario artifacts: $output_dir"
