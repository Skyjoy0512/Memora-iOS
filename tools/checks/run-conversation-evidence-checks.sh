#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-conversation-evidence.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export SWIFT_BACKTRACE=enable=no
swiftc App/AIEpisode.swift App/AIConversationEntry.swift App/AIAttachmentCitation.swift Shared/MemoraIcon.swift App/AgentStep.swift App/AIAttachment.swift App/AIAttachmentFileReference.swift App/ComposerMention.swift App/AIAnswerDetails.swift App/AIChatSource.swift App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift App/AIConversationProvenance.swift App/AgentSourceReference.swift App/AICalendarEventReference.swift App/AICalendarReadSnapshot.swift App/ProjectCitation.swift App/AIChatMessage.swift App/ToolInputValidator.swift App/NativeAIInterface.swift App/NativeAIInterface+JSONRender.swift App/NativeAIComponentStream.swift App/AIConversationSnapshot.swift tools/checks/AIConversationSnapshotChecks.swift -o "$check_dir/conversation"
"$check_dir/conversation"
