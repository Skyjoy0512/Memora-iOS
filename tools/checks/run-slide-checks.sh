#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-slides.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift \
  App/ArtifactProjectSourceReference.swift Shared/MemoraIcon.swift App/MemoraDocumentKind.swift \
  App/SlideArchetype.swift App/SlideContent.swift App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift App/PresentationLayoutEngine.swift App/PresentationValidator.swift App/PresentationExportCheck.swift App/PresentationOOXML.swift App/PresentationToolInput.swift App/DocumentSlide.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift App/SlidePage.swift App/SlidePageLayout.swift \
  App/ZipArchive.swift App/PPTXWriter.swift App/OfficeArchiveReader.swift \
  tools/checks/SlidePageChecks.swift -o "$check_dir/slides"
"$check_dir/slides" "$check_dir/output"
python3 -B tools/checks/validate-slide-package.py "$check_dir/output"
