#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-openui-native-polish.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/ToolInputValidator.swift App/NativeAIInterface.swift App/NativeAIComponentStream.swift \
  App/AIInterfaceTableLayout.swift App/AIInterfaceTaskProgressSummary.swift App/AIInterfaceSourceRow.swift \
  App/AIInterfaceSourceListModel.swift App/AIChatSource.swift App/MemoraTask.swift App/TaskProgress.swift \
  App/TaskRelationships.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  tools/checks/OpenUINativePolishChecks.swift -o "$check_dir/polish"
"$check_dir/polish"
