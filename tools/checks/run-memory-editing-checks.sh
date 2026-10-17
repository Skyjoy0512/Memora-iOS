#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-memory-editing.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/LocalStore.swift App/AIRecordFingerprint.swift App/AIMemory.swift App/AIMemory+Editing.swift \
  App/AIMemoryEditDraft.swift App/AIMemoryEditPlan.swift App/MemoraModel+MemoryManagement.swift \
  tools/checks/MemoryEditingChecks.swift -lsqlite3 -o "$check_dir/memory-editing"
"$check_dir/memory-editing" "$check_dir"
