#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-meeting-bot.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 App/MeetingBotTarget.swift App/MeetingBotJoinRequest.swift \
  App/MeetingBotJob.swift App/MeetingBotProvider.swift tools/checks/MeetingBotContractChecks.swift \
  -o "$check_dir/checks"
"$check_dir/checks"
