#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-nextgen-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/BoundedTextReader.swift App/AIAttachment.swift App/PreparedAIAttachment.swift App/AIQueryScope.swift tools/checks/AttachmentScopeChecks.swift -o "$check_dir/attachments"
"$check_dir/attachments"
swiftc App/ProjectSourceFiles.swift App/ProjectSourceText.swift App/ProjectSourceTextReader.swift tools/checks/ProjectSourceReadChecks.swift -o "$check_dir/source-read"
"$check_dir/source-read"
swiftc App/ProjectCitation.swift App/ProjectChatTurn.swift App/ProjectChatThread.swift App/ProjectChatHistory.swift tools/checks/ProjectChatHistoryChecks.swift -o "$check_dir/project-history"
"$check_dir/project-history"
swiftc App/AIAnswerFailure.swift App/CloudStreamAccumulator.swift tools/checks/CloudStreamChecks.swift -o "$check_dir/stream"
"$check_dir/stream"
swiftc App/ToolInputValidator.swift App/NativeAIInterface.swift tools/checks/NativeAIInterfaceChecks.swift -o "$check_dir/ui"
"$check_dir/ui"
swiftc App/SemanticToolDiscovery.swift App/MemoraSkill.swift App/MemoraSkillMarkdown.swift tools/checks/DiscoverySkillChecks.swift -o "$check_dir/skills"
"$check_dir/skills"
swiftc Shared/MemoraIcon.swift App/ResidentAgent.swift App/ResidentTrigger.swift App/ResidentExecutionLimits.swift tools/checks/ResidentLimitsChecks.swift -o "$check_dir/residents"
"$check_dir/residents"
swiftc Shared/MemoraAppLink.swift Shared/MemoraWidgetSnapshot.swift Shared/MemoraWidgetSnapshotStore.swift tools/checks/SystemIntegrationChecks.swift -o "$check_dir/system"
"$check_dir/system" "$check_dir"
TMPDIR="$check_dir/" bash tools/checks/run-ask-ai-plugin-checks.sh
