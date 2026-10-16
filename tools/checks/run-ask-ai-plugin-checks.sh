#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-mention-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/ComposerMention.swift App/ComposerMentionToken.swift App/AIPluginExecutionPolicy.swift \
  App/AIToolRegistry.swift App/AIToolDefinition.swift App/ToolInputValidator.swift App/ExternalToolFailure.swift App/GmailError.swift App/MCPClientError.swift App/MCPOAuthError.swift App/IntegrationProvider.swift App/IntegrationToolResult.swift \
  tools/checks/ComposerMentionChecks.swift -o "$check_dir/mentions"
"$check_dir/mentions"
swiftc App/AIToolRegistry.swift App/AIToolDefinition.swift App/ToolInputValidator.swift App/AIPluginExecutionPolicy.swift \
  App/IntegrationProvider.swift App/IntegrationToolResult.swift tools/checks/PluginDispatchChecks.swift -o "$check_dir/dispatch"
"$check_dir/dispatch"
bash tools/checks/run-tool-integration-checks.sh

swiftc App/AIHistorySearch.swift App/AIEpisode.swift App/AIConversationEntry.swift App/AIConversationProvenance.swift \
  App/AIRecordReference.swift App/AIRecordFingerprint.swift App/RecordPrivacyTarget.swift \
  tools/checks/AIHistorySearchChecks.swift -o "$check_dir/history"
"$check_dir/history"

swiftc Shared/MemoraIcon.swift App/AIJournalPrivacy.swift App/LifeLogKind.swift App/LifeLogOrigin.swift \
  tools/checks/AIJournalPrivacyChecks.swift -o "$check_dir/journal-privacy"
"$check_dir/journal-privacy"

swiftc Shared/MemoraIcon.swift App/RootTab.swift App/RootNavigation.swift App/LibraryRoute.swift \
  App/LibrarySection.swift App/AIQueryScope.swift App/MemoraArtwork.swift \
  tools/checks/RootNavigationChecks.swift -o "$check_dir/navigation"
"$check_dir/navigation"

swiftc App/RecordPrivacy.swift App/RecordAccessPolicy.swift App/SummarySensitivity.swift \
  tools/checks/RecordPrivacyChecks.swift -o "$check_dir/record-privacy"
"$check_dir/record-privacy"
