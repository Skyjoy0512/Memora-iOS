#!/bin/bash
set -euo pipefail
if [[ $# != 2 ]]; then
  echo "Usage: bash tools/checks/run-company-template-profile.sh input.pptx output.json" >&2
  exit 64
fi
cd "$(dirname "$0")/../.."
profile_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-company-profile.XXXXXX")
trap 'rm -rf "$profile_dir"' EXIT
swiftc App/CompanyTemplate.swift App/CompanyTemplateEngine.swift App/CompanyPresentationProfile.swift \
  App/CompanyPresentationAnalyzer.swift App/OfficeTemplateTextPart.swift App/OfficeArchiveReader.swift \
  App/OfficeXMLDocument.swift App/OfficeDocumentExtraction.swift App/ZipArchive.swift App/ProjectSourceText.swift \
  tools/checks/MeasureCompanyTemplate.swift -o "$profile_dir/measure"
"$profile_dir/measure" "$1" "$2"
