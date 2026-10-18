#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-branch-integration.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -O -swift-version 6 App/ReadabilityGuide.swift tools/checks/ReadabilityGuideChecks.swift -o "$check_dir/readability"
"$check_dir/readability"
swiftc -O -swift-version 6 App/GlobalGestureFeedbackPolicy.swift App/AIAnswerPrompt.swift tools/checks/BranchIntegrationChecks.swift -o "$check_dir/branch"
"$check_dir/branch"
python3 - <<'PY'
from pathlib import Path
for p in Path('App').glob('*.swift'):
    source = p.read_text()
    assert 'retainHindsight(' not in source and 'hindsightContext(' not in source, f'Unsafe legacy external memory path restored: {p}'
assert Path('App/FlowLayout.swift').exists(), 'A legacy streaming patch deleted a current layout dependency'
print('Branch integration guard: no legacy external-memory auto-send wired; current layout retained')
PY
