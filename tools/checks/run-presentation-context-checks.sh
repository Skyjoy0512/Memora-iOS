#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-presentation-context.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
for suite in PresentationContextChecks PresentationDeepContextChecks; do
  swiftc App/TokenEstimate.swift App/PresentationEvidencePack.swift "tools/checks/$suite.swift" -o "$check_dir/$suite"
  "$check_dir/$suite"
done
swiftc App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift \
  App/ArtifactProjectSourceReference.swift Shared/MemoraIcon.swift App/MemoraDocumentKind.swift \
  App/SlideArchetype.swift App/SlideContent.swift App/DocumentSlide.swift App/PresentationPlan.swift \
  App/DocumentArtifactRevision.swift App/MemoraDocument.swift App/TokenEstimate.swift App/PresentationEvidencePack.swift \
  App/MemoraModel+PresentationContext.swift tools/checks/PresentationAccessChecks.swift -o "$check_dir/access"
"$check_dir/access"
