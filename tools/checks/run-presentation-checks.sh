#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-presentation.XXXXXX")
swiftc -DDEBUG App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift \
  App/ArtifactProjectSourceReference.swift Shared/MemoraIcon.swift App/MemoraDocumentKind.swift \
  App/SlideArchetype.swift App/SlideContent.swift App/DocumentSlide.swift App/PresentationPlan.swift App/MemoraDocument.swift \
  App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift \
  App/PresentationLayoutEngine.swift App/PresentationValidator.swift App/PresentationExportCheck.swift \
  App/PresentationOOXML.swift App/PresentationDrawing.swift App/PresentationExample.swift App/PresentationToolInput.swift \
  App/SlidePage.swift App/SlidePageLayout.swift App/ZipArchive.swift App/PPTXWriter.swift \
  tools/checks/PresentationPlanningChecks.swift tools/checks/PresentationLayoutChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$check_dir/output"
python3 -B tools/checks/validate-presentation-packages.py "$check_dir/output"
echo "Presentation artifacts: $check_dir/output"
