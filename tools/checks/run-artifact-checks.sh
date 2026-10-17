#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-artifacts.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift Shared/MemoraIcon.swift App/MemoraDocumentKind.swift App/DocumentSlide.swift App/MemoraDocument.swift App/ZipArchive.swift App/ProjectSourceText.swift App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift App/DOCXWriter.swift App/PPTXWriter.swift App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/OfficeTemplateTextPart.swift tools/checks/DocumentArtifactChecks.swift -o "$check_dir/artifacts"
"$check_dir/artifacts" "$check_dir/generated"
python3 tools/checks/office-template-poc.py "$check_dir/generated"
swiftc App/LocalStore.swift App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift Shared/MemoraIcon.swift App/MemoraDocumentKind.swift App/DocumentSlide.swift App/MemoraDocument.swift App/ZipArchive.swift App/ProjectSourceText.swift App/OfficeArchiveReader.swift App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift App/DOCXWriter.swift App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/OfficeTemplateTextPart.swift App/MemoraModel+CompanyTemplateAnalysis.swift tools/checks/CompanyTemplateAnalysisChecks.swift -o "$check_dir/analysis"
"$check_dir/analysis" "$check_dir/generated"
if [[ "${MEMORA_KEEP_SPLIT_FIXTURES:-0}" == "1" ]]; then
  cp "$check_dir/generated/split-runs.docx" docs/fixtures/ask-ai-artifacts/split-runs.docx
  cp "$check_dir/generated/split-runs.pptx" docs/fixtures/ask-ai-artifacts/split-runs.pptx
fi
