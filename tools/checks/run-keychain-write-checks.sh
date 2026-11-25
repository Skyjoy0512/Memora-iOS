#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-keychain-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT

check_variant() {
  swiftc -swift-version 6 "$@" App/KeychainStore.swift App/FeatureFlags.swift \
    tools/checks/KeychainWriteChecks.swift -o "$check_dir/check"
  "$check_dir/check"
}

check_variant
check_variant -D DEBUG
check_variant -D DEBUG -D MEMORA_ENABLE_CHATGPT_SIGN_IN
check_variant -D MEMORA_ENABLE_CHATGPT_SIGN_IN
