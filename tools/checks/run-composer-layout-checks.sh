#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-composer-layout.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -O -swift-version 6 App/AIComposerLayoutPolicy.swift tools/checks/AIComposerLayoutChecks.swift -o "$check_dir/layout"
"$check_dir/layout"
swiftc -O -swift-version 6 App/AgentPromptSuggestion.swift App/MemoraModel+AgentSuggestions.swift \
  App/MemoraTask.swift App/TaskRelationships.swift App/TaskProgress.swift App/RecordPrivacy.swift \
  App/SummarySensitivity.swift App/RecordAccessPolicy.swift \
  tools/checks/AgentSuggestionFixtureModel.swift tools/checks/AgentSuggestionChecks.swift -o "$check_dir/suggestions"
"$check_dir/suggestions"
swiftc -O -swift-version 6 App/RecorderBatteryState.swift tools/checks/RecorderBatteryChecks.swift -o "$check_dir/recorder-battery"
"$check_dir/recorder-battery"
