#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-license-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/MemoraPlan.swift App/MemoraLicense.swift App/LicenseCodeError.swift \
  App/MemoraCreditMeter.swift App/MemoraModel+Plans.swift tools/checks/LicensePersistenceChecks.swift -o "$check_dir/licenses"
"$check_dir/licenses"
