#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-artifacts.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift Shared/MemoraIcon.swift App/MemoraDocumentKind.swift App/SlideArchetype.swift App/SlideContent.swift App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift App/PresentationLayoutEngine.swift App/PresentationValidator.swift App/PresentationExportCheck.swift App/PresentationOOXML.swift App/PresentationToolInput.swift App/DocumentSlide.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift App/ZipArchive.swift App/ProjectSourceText.swift App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift App/DOCXWriter.swift App/SlidePage.swift App/SlidePageLayout.swift App/PPTXWriter.swift App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/CompanyPresentationProfile.swift App/CompanyPresentationAnalyzer.swift App/OfficeTemplateTextPart.swift tools/checks/CompanyPresentationChecks.swift tools/checks/DocumentArtifactChecks.swift -o "$check_dir/artifacts"
"$check_dir/artifacts" "$check_dir/generated"
if [[ -n "${MEMORA_COMPANY_CHECK_OUTPUT:-}" ]]; then
  mkdir -p "$MEMORA_COMPANY_CHECK_OUTPUT"
  cp "$check_dir/generated/measured-template.pptx" "$check_dir/generated/measured-filled.pptx" "$check_dir/generated/company-profile.json" "$MEMORA_COMPANY_CHECK_OUTPUT/"
fi
python3 tools/checks/office-template-poc.py "$check_dir/generated"
bash tools/checks/run-slide-checks.sh
swiftc App/LocalStore.swift App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift Shared/MemoraIcon.swift App/MemoraDocumentKind.swift App/SlideArchetype.swift App/SlideContent.swift App/PresentationTheme.swift App/PresentationElement.swift App/PresentationText.swift App/PresentationLayoutEngine.swift App/PresentationValidator.swift App/PresentationExportCheck.swift App/PresentationOOXML.swift App/PresentationToolInput.swift App/DocumentSlide.swift App/PresentationPlan.swift App/DocumentArtifactRevision.swift App/MemoraDocument.swift App/ZipArchive.swift App/ProjectSourceText.swift App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift App/DOCXWriter.swift App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/CompanyPresentationProfile.swift App/CompanyPresentationAnalyzer.swift App/OfficeTemplateTextPart.swift App/MemoraModel+CompanyTemplateAnalysis.swift tools/checks/CompanyTemplateAnalysisChecks.swift -o "$check_dir/analysis"
"$check_dir/analysis" "$check_dir/generated"
if [[ "${MEMORA_KEEP_SPLIT_FIXTURES:-0}" == "1" ]]; then
  cp "$check_dir/generated/split-runs.docx" docs/fixtures/ask-ai-artifacts/split-runs.docx
  cp "$check_dir/generated/split-runs.pptx" docs/fixtures/ask-ai-artifacts/split-runs.pptx
fi
bash tools/checks/run-company-presentation-checks.sh
