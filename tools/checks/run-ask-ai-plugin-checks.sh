#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-mention-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/ComposerMention.swift App/ComposerMentionToken.swift App/AIPluginExecutionPolicy.swift \
  App/AIToolRegistry.swift App/AIToolDefinition.swift App/ToolInputValidator.swift App/ExternalToolFailure.swift App/GmailError.swift App/MCPClientError.swift \
  tools/checks/ComposerMentionChecks.swift -o "$check_dir/mentions"
"$check_dir/mentions"
bash tools/checks/run-tool-integration-checks.sh
