#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-company-export.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
output_dir=${MEMORA_COMPANY_APPEND_OUTPUT:-$check_dir/output}
entrypoint=tools/checks/CompanyPresentationExportChecks.swift
extra_sources=()
if [[ "${1:-}" == --preview ]]; then
  output_dir=${MEMORA_COMPANY_PREVIEW_OUTPUT:-$check_dir/output}
  entrypoint=tools/checks/CompanyPresentationPreviewChecks.swift
  extra_sources=(App/PresentationDrawing.swift App/CompanyPresentationPreview.swift App/CompanyPresentationColor.swift App/CompanyPresentationDecorationReader.swift App/CompanyPresentationPDF.swift tools/checks/CompanyPresentationColorChecks.swift)
fi
swiftc -DDEBUG App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift \
  App/ArtifactProjectSourceReference.swift Shared/MemoraIcon.swift App/MemoraDocumentKind.swift \
  App/SlideArchetype.swift App/SlideContent.swift App/DocumentSlide.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift \
  App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift App/PresentationExample.swift \
  App/PresentationLayoutEngine.swift App/PresentationValidator.swift App/PresentationExportCheck.swift App/PresentationOOXML.swift \
  App/SlidePage.swift App/SlidePageLayout.swift App/ZipArchive.swift App/PPTXWriter.swift \
  App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/CompanyPresentationProfile.swift App/CompanyPresentationAnalyzer.swift \
  App/CompanyPresentationExporter.swift App/OfficeXMLInsertion.swift App/OfficeTemplateTextPart.swift App/ProjectSourceText.swift \
  App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift \
  ${extra_sources[@]+"${extra_sources[@]}"} "$entrypoint" -o "$check_dir/checks"
"$check_dir/checks" "$output_dir"
python3 -B tools/checks/validate-company-packages.py "$output_dir"
