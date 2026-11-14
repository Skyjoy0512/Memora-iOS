#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-summary-hierarchy.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/SummaryPartScheduler.swift App/SummaryNoteHierarchy.swift App/AIAnswerFailure.swift tools/checks/SummaryHierarchyChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
