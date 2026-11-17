#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-json-render.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 5 App/ToolInputValidator.swift App/JSONRenderPrompt.swift App/JSONRenderEnvelope.swift \
  App/JSONRenderSnapshot.swift App/LocalStore.swift App/NativeAIInterface.swift App/NativeAIInterface+JSONRender.swift \
  App/NativeAIComponentStream.swift tools/checks/JSONRenderEnvelopeChecks.swift -lsqlite3 -o "$check_dir/envelope"
"$check_dir/envelope"
swiftc -swift-version 6 App/JSONRenderSnapshot.swift App/JSONRenderActionRequest.swift App/MemoraModel+JSONRender.swift \
  tools/checks/JSONRenderContextChecks.swift -o "$check_dir/context"
"$check_dir/context"
npm --prefix tools/json-render test
