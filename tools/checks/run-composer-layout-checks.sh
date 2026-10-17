#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-composer-layout.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -O -swift-version 6 App/AIComposerLayoutPolicy.swift tools/checks/AIComposerLayoutChecks.swift -o "$check_dir/layout"
"$check_dir/layout"
