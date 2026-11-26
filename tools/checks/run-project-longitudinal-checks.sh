#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-project-longitudinal.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -O App/ProjectCitation.swift App/ProjectEvidenceChunk.swift App/ProjectEvidenceInput.swift \
  App/ProjectSourceText.swift App/ProjectContextBuilder.swift App/ProjectSearchIndex.swift \
  tools/checks/ProjectLongitudinalChecks.swift -lsqlite3 -o "$check_dir/checks"
TZ=UTC "$check_dir/checks" "$check_dir"
