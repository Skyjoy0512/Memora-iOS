#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-gmail-agent.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/AgentTool.swift App/AgentToolCall.swift App/AgentToolOutcome.swift \
  App/AgentStep.swift App/AgentApproval.swift App/AgentTaskDraft.swift App/ReviewPeriod.swift \
  App/AIPluginExecutionPolicy.swift App/ToolInputValidator.swift App/AIToolDefinition.swift App/AIToolRegistry.swift \
  App/IntegrationProvider.swift App/IntegrationToolResult.swift App/MCPTool.swift App/MCPServerConfig.swift App/MCPOAuthSettings.swift \
  App/GmailService.swift App/GmailServiceEnvironment.swift App/GmailError.swift App/GmailMessage.swift \
  App/ExternalToolFailure.swift App/MCPClientError.swift App/MCPOAuthError.swift \
  App/AgentConversationExecutionContext.swift App/GmailAgentReadContext.swift App/MemoraModel+GmailContext.swift \
  App/MemoraModel+GmailTools.swift App/MemoraModel+IntegrationSettings.swift \
  App/AgentConversationLoop.swift App/AgentTurn.swift App/AgentRunEvent.swift App/AIAnswerResult.swift App/AIAnswerFailure.swift \
  tools/checks/HTTPResponseGate.swift tools/checks/GmailServiceFixture.swift tools/checks/GmailAgentFixtureModel.swift \
  tools/checks/GmailAgentChecks.swift -o "$check_dir/gmail-agent"
"$check_dir/gmail-agent"
