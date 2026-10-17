#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-inline.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -enable-bare-slash-regex App/ArtifactSourceTarget.swift App/AnswerSourceCitation.swift App/AnswerCitations.swift App/MeetingLink.swift App/AIAnswerDocumentBuilder.swift App/MemoraDocument.swift App/DocumentSlide.swift App/MemoraDocumentKind.swift Shared/MemoraIcon.swift App/AgentStep.swift App/AIAttachment.swift App/AIAttachmentFileReference.swift App/ComposerMention.swift App/AIAnswerDetails.swift App/AIChatSource.swift App/RecordPrivacyTarget.swift App/AIRecordReference.swift App/ArtifactProvenance.swift App/ArtifactProjectSourceReference.swift App/AIConversationProvenance.swift App/AgentSourceReference.swift App/AICalendarEventReference.swift App/AICalendarReadSnapshot.swift App/AIChatMessage.swift App/ToolInputValidator.swift App/NativeAIInterface.swift App/NativeAIComponentStream.swift App/AIConversationSnapshot.swift tools/checks/InlineCitationChecks.swift -o "$check_dir/inline"
"$check_dir/inline"
