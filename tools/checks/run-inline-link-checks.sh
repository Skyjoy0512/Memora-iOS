#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-inline-links.XXXXXX")
swiftc App/MCPDNSLookup.swift App/MCPClientError.swift App/MCPPublicAddressPolicy.swift \
  App/RecordPrivacy.swift App/SummarySensitivity.swift App/ProjectSource.swift App/ProjectSourceText.swift \
  App/ProjectSourceURL.swift App/WebSourceFailure.swift App/WebSourceRequest.swift App/WebSourceHTTPDecoder.swift \
  App/PinnedHTTPSConnection.swift App/WebSourceTextExtraction.swift App/WebSourceFetcher.swift \
  App/InlineURLDetector.swift App/InlineLinkSession.swift tools/checks/InlineLinkChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
