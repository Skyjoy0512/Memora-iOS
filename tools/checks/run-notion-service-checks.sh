#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-notion-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/NotionSaveConfiguration.swift App/NotionService.swift \
  App/MemoraTask.swift App/TaskRelationships.swift App/TaskProgress.swift \
  App/RecordPrivacy.swift App/SummarySensitivity.swift \
  tools/checks/NotionServiceFixture.swift tools/checks/HTTPResponseGate.swift \
  tools/checks/NotionServiceChecks.swift \
  -o "$check_dir/notion"
"$check_dir/notion"
