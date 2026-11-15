#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-native-evaluation.XXXXXX")
trap 'if [[ $? -eq 0 ]]; then rm -rf "$check_dir"; else echo "Native evaluation failure artifacts: $check_dir" >&2; fi' EXIT
PYTHONDONTWRITEBYTECODE=1 python3 tools/evaluation/tests/test_native_runner.py -v
bash tools/evaluation/build-native.sh "$check_dir/driver"
PYTHONDONTWRITEBYTECODE=1 python3 tools/evaluation/tests/test_native_runner.py --integration "$check_dir/driver" "$check_dir/results"
