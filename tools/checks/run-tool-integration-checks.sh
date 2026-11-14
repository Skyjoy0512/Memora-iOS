#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-integration-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT

swiftc App/ToolInputValidator.swift App/AIToolDefinition.swift App/AIToolRegistry.swift App/AIPluginExecutionPolicy.swift \
  App/MCPEventStream.swift App/MCPOAuthSettings.swift App/MCPServerConfig.swift App/MCPTool.swift \
  App/MCPPublicAddressPolicy.swift App/MCPDNSLookup.swift App/MCPClientError.swift App/MemoraSkill.swift App/MemoraSkill+Business.swift App/MemoraSkill+Workflows.swift App/MemoraSkill+Breadth.swift \
  App/IntegrationProvider.swift App/IntegrationToolResult.swift App/IntegrationConnectionError.swift App/ComposioProvider.swift \
  tools/checks/ToolIntegrationChecks.swift -o "$check_dir/tools"
"$check_dir/tools"

swiftc App/AIWebSearchIntent.swift tools/checks/AIWebSearchIntentChecks.swift -o "$check_dir/web"
"$check_dir/web"

swiftc App/AIAttachmentCitation.swift App/AIRecordFingerprint.swift App/AIRecordReference.swift App/RecordPrivacyTarget.swift \
  App/AIConversationProvenance.swift App/AIEpisode.swift App/ProjectCitation.swift App/AIAttachment.swift App/AIAttachmentFileReference.swift App/AIConversationEntry.swift \
  tools/checks/AIConversationProvenanceChecks.swift -o "$check_dir/privacy"
"$check_dir/privacy"

# Pure fixtures only: this does not sign in or contact a token endpoint.
swiftc App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift App/MCPOAuthSettings.swift App/MCPOAuthError.swift App/MCPOAuthPolicy.swift App/MCPOAuthCredential.swift \
  App/MCPConnectionPolicy.swift App/MCPClientError.swift App/ProjectSourceURL.swift App/ProjectSource.swift \
  App/RecordPrivacy.swift App/SummarySensitivity.swift tools/checks/MCPOAuthChecks.swift -o "$check_dir/oauth"
"$check_dir/oauth"
