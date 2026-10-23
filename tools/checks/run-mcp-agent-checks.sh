#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-mcp-agent.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/AgentTool.swift App/AgentToolCall.swift App/AgentToolOutcome.swift \
  App/AgentStep.swift App/AgentApproval.swift App/AgentTaskDraft.swift App/ReviewPeriod.swift \
  App/AIPluginExecutionPolicy.swift App/ToolInputValidator.swift App/AIToolDefinition.swift App/AIToolRegistry.swift \
  App/IntegrationProvider.swift App/IntegrationToolResult.swift App/IntegrationUsage.swift \
  App/ExternalToolFailure.swift App/GmailError.swift App/MCPClientError.swift App/MCPOAuthError.swift \
  App/MCPTool.swift App/MCPServerConfig.swift App/MCPOAuthSettings.swift App/MCPOAuthPolicy.swift \
  App/MCPConnectionPolicy.swift App/ProjectSourceURL.swift App/ProjectSource.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  App/SemanticToolDiscovery.swift App/LocalStore.swift App/MCPAgentExecutionContext.swift App/MCPIntegrationProvider.swift \
  App/MemoraModel+MCP.swift App/MemoraModel+ToolExecution.swift \
  tools/checks/HTTPResponseGate.swift tools/checks/MCPAgentFixtureModel.swift tools/checks/MCPAgentFixtureServices.swift \
  tools/checks/MCPAgentChecks.swift -lsqlite3 -o "$check_dir/mcp-agent"
"$check_dir/mcp-agent" "$check_dir"
