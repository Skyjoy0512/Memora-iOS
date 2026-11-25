#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-media-index.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export SWIFT_BACKTRACE=enable=no
swiftc App/LocalStore.swift App/CollectionSearch.swift App/MediaIndexEntry.swift App/MemoraModel+MediaIndex.swift \
  tools/checks/MediaIndexFixture.swift tools/checks/MediaIndexChecks.swift -lsqlite3 -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
