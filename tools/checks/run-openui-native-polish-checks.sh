#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_root=${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}
check_dir=$(mktemp -d "$check_root/memora-openui-native-polish.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT

# 1. Host logic checks: pure presentation math, the display schema and the
#    streaming validator, compiled and run as a normal macOS executable.
swiftc App/ToolInputValidator.swift App/NativeAIInterface.swift App/NativeAIInterface+JSONRender.swift App/NativeAIComponentStream.swift \
  App/AIInterfaceTableLayout.swift App/AIInterfaceTaskProgressSummary.swift App/AIInterfaceSourceRow.swift \
  App/AIInterfaceSourceListModel.swift App/AIInterfaceEvidence.swift App/AIInterfaceReferenceTarget.swift \
  App/AIChatSource.swift App/MemoraTask.swift App/TaskProgress.swift \
  App/TaskRelationships.swift App/RecordPrivacy.swift App/SummarySensitivity.swift \
  tools/checks/OpenUINativePolishChecks.swift -o "$check_dir/polish"
"$check_dir/polish"

# 2. Type-check the new SwiftUI views against the real iOS SDK. The app module
#    cannot be built here (Bitrig does not recognize this worktree), so the
#    icon helpers and the reference destination are minimal stand-ins that match
#    the production signatures. This proves the views compile, not that the app
#    builds or that anything renders; the integrator still runs the full build.
cat > "$check_dir/OpenUINativePolishViewStubs.swift" <<'STUBS'
import SwiftUI

// Stand-ins matching Shared/MemoraIcon+SwiftUI.swift and the app's icon cases.
enum MemoraIcon {
  case docText, link, chevronRight, checkmarkCircleFill, circle
}

extension Image {
  init(icon: MemoraIcon, size: CGFloat = 20) { self.init(systemName: "circle") }
}

extension Label where Title == Text, Icon == Image {
  init(_ titleKey: LocalizedStringKey, icon: MemoraIcon) {
    self.init { Text(titleKey) } icon: { Image(icon: icon) }
  }
  init<S: StringProtocol>(_ title: S, icon: MemoraIcon) {
    self.init { Text(title) } icon: { Image(icon: icon) }
  }
}

// Stand-in for the destination in NativeAIInterfaceView.swift.
struct AIInterfaceReferenceDestination: View {
  var messageID: UUID
  var target: AIInterfaceReferenceTarget
  var body: some View { EmptyView() }
}
STUBS

sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
swiftc -typecheck -swift-version 6 -sdk "$sdk" -target arm64-apple-ios26.0-simulator \
  App/ToolInputValidator.swift App/NativeAIInterface.swift App/NativeAIInterface+JSONRender.swift App/NativeAIComponentStream.swift \
  App/AIChatSource.swift App/MemoraTask.swift App/TaskProgress.swift App/TaskRelationships.swift \
  App/RecordPrivacy.swift App/SummarySensitivity.swift App/AIInterfaceTableLayout.swift \
  App/AIInterfaceTaskProgressSummary.swift App/AIInterfaceSourceRow.swift App/AIInterfaceSourceListModel.swift \
  App/AIInterfaceEvidence.swift App/AIInterfaceReferenceTarget.swift App/MemoraPalette.swift App/MemoraSpacing.swift \
  App/AIInterfaceComparisonTable.swift App/AIInterfaceSourceList.swift App/AIInterfaceTaskProgress.swift \
  "$check_dir/OpenUINativePolishViewStubs.swift"
echo "OpenUINativePolishViewTypeCheck: passed (views compile against the iOS SDK; icon/destination stubs only)"
