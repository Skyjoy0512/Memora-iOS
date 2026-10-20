#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 tools/checks/test_design_tokens.py
python3 tools/checks/test_settings_presentation.py
python3 tools/checks/test_experience_presentation.py
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-design-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/SettingsCategory.swift App/MemoraIconMetrics.swift \
  tools/checks/SettingsNavigationChecks.swift -o "$check_dir/settings-navigation"
"$check_dir/settings-navigation"
swiftc App/AIPluginMenuCopy.swift tools/checks/AIPluginMenuCopyChecks.swift -o "$check_dir/plugin-menu-copy"
"$check_dir/plugin-menu-copy"
swiftc App/ProjectCitation.swift App/ProjectMentionSelection.swift App/AIPlugin.swift \
  App/MemoraSkill.swift App/MemoraSkill+Business.swift App/MemoraModel+ProjectMentions.swift \
  tools/checks/ProjectMentionChecks.swift -o "$check_dir/project-mentions"
"$check_dir/project-mentions"
bash tools/checks/run-answer-presentation-checks.sh
bash tools/checks/run-motion-loading-checks.sh
