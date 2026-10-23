#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-notion-agent.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/AgentTool.swift App/AgentToolCall.swift App/AgentToolOutcome.swift \
  App/AgentStep.swift App/AgentApproval.swift App/AgentTaskDraft.swift App/ReviewPeriod.swift App/AIChatScope.swift \
  App/AIPluginExecutionPolicy.swift App/ToolInputValidator.swift App/AIToolDefinition.swift App/AIToolRegistry.swift \
  App/IntegrationProvider.swift App/IntegrationToolResult.swift App/MCPTool.swift App/MCPServerConfig.swift App/MCPOAuthSettings.swift \
  App/MemoraTask.swift App/TaskRelationships.swift App/TaskProgress.swift App/RecordPrivacy.swift App/RecordAccessPolicy.swift \
  App/SummarySensitivity.swift App/RecordPrivacyTarget.swift App/AIAnswerFailure.swift App/GmailError.swift App/ExternalToolFailure.swift App/MCPClientError.swift App/MCPOAuthError.swift \
  App/IntegrationConfigurationRevision.swift App/NotionSaveConfiguration.swift App/NotionSaveEnvironment.swift App/NotionService.swift \
  App/AgentConversationExecutionContext.swift App/NotionExportContext.swift App/NotionAgentExecutionContext.swift \
  App/MemoraModel+NotionExport.swift App/MemoraModel+NotionTools.swift App/MemoraModel+IntegrationSettings.swift \
  tools/checks/HTTPResponseGate.swift tools/checks/NotionAgentFixtureModel.swift tools/checks/NotionAgentChecks.swift \
  -o "$check_dir/notion-agent"
"$check_dir/notion-agent"
