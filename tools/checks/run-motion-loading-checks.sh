#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-motion-loading.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
python3 tools/checks/check-motion-policy.py
swiftc App/MemoraLoadingState.swift App/MemoraLoadingPolicy.swift App/MemoraLoadSnapshot.swift App/JournalCalendarRequest.swift tools/checks/LoadingPolicyChecks.swift -o "$check_dir/loading"
"$check_dir/loading"
swiftc App/ConversationScrollState.swift tools/checks/ConversationScrollChecks.swift -o "$check_dir/scroll"
"$check_dir/scroll"
