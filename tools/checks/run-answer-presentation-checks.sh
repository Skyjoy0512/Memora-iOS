#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-answer-presentation.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -O -swift-version 6 App/AIResponseTableLayout.swift tools/checks/AIResponseTableLayoutChecks.swift -o "$check_dir/layout"
"$check_dir/layout"
bash tools/checks/run-composer-layout-checks.sh
