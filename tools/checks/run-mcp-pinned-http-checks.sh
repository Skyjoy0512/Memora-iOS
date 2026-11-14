#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-mcp-http.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
# No real DNS, network, OAuth account, keychain or MCP service is contacted.
swiftc App/SummaryKnowledge.swift App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift -swift-version 6 -D MCP_HTTP_CHECKS App/MCPDNSLookup.swift App/MCPClientError.swift \
  App/MCPPublicAddressPolicy.swift App/RecordPrivacy.swift App/SummarySensitivity.swift App/ProjectSource.swift \
  App/ProjectSourceURL.swift App/MCPConnectionPolicy.swift App/WebSourceFailure.swift App/WebSourceRequest.swift \
  App/WebSourceHTTPDecoder.swift App/PinnedHTTPSConnection.swift App/MCPPinnedHTTP.swift \
  App/MCPHTTPResponseReader.swift App/MCPHTTPResponseState.swift App/MCPEventStream.swift App/MCPBoundedHTTPTransport.swift \
  App/MCPOAuthSettings.swift App/MCPOAuthPolicy.swift App/MCPOAuthCredential.swift App/MCPOAuthError.swift \
  App/MCPOAuthClient.swift App/MCPServerConfig.swift App/ExternalToolFailure.swift App/GmailError.swift \
  tools/checks/MCPHTTPFixtureSDK.swift tools/checks/MCPPinnedHTTPChecks.swift -o "$check_dir/mcp-http"
"$check_dir/mcp-http"
