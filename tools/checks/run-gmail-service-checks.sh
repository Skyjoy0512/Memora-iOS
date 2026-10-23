#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-gmail-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc App/GmailService.swift App/GmailServiceEnvironment.swift App/GmailError.swift App/GmailMessage.swift \
  App/ExternalToolFailure.swift App/MCPClientError.swift App/MCPOAuthError.swift \
  tools/checks/HTTPResponseGate.swift tools/checks/GmailServiceFixture.swift tools/checks/GmailServiceChecks.swift \
  -o "$check_dir/gmail"
"$check_dir/gmail"
