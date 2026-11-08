#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-citation-location.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 App/ProjectCitationLocation.swift \
  tools/checks/ProjectCitationLocationChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
