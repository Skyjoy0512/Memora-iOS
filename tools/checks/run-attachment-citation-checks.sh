#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-attachment-citations.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export SWIFT_BACKTRACE=enable=no
swiftc App/AIAttachment.swift App/AIAttachmentFileReference.swift App/AIAttachmentCitation.swift \
  App/PreparedAIAttachment.swift App/AIAttachmentText.swift App/ProjectSourceText.swift \
  App/ProjectCitation.swift App/ProjectEvidenceChunk.swift App/ProjectContextBuilder.swift \
  App/SourceTextSelection.swift tools/checks/AttachmentCitationChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
