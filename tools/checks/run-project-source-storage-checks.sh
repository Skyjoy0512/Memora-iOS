#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-source-storage.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_WORKSPACE_FILES_DIRECTORY="$check_dir/workspace"
export SWIFT_BACKTRACE=enable=no
swiftc -D MEMORA_HOST_CHECKS Shared/MemoraIcon.swift App/LocalStore.swift App/MemoraSpace.swift \
  App/RecordPrivacy.swift App/SummarySensitivity.swift App/ProjectSource.swift App/ProjectSourceText.swift \
  App/ProjectSourceFiles.swift App/ProjectSourceTextReader.swift App/IdentifiableIndex.swift App/ProjectCitation.swift App/PersistenceFailurePresentation.swift \
  App/MemoraModel+ProjectSourceStorage.swift tools/checks/ProjectSourceStorageFixture.swift \
  tools/checks/ProjectSourceStorageChecks.swift -lsqlite3 -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
