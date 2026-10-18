#!/bin/bash
# Type-checks App/ and Shared/ against the iOS Simulator SDK. This does not
# replace a Bitrig build or link; it exists so a linked git worktree, which
# Bitrig does not register as a project, can still be checked.
# Usage: typecheck-ios-app.sh <products-dir> [debug|release]
set -euo pipefail
cd "$(dirname "$0")/../.."
products=${1:?usage: typecheck-ios-app.sh <products-dir> [debug|release]}
configuration=${2:-debug}
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
derived=$(cd "$products/../../.." && pwd)
fluid="$derived/SourcePackages/checkouts/FluidAudio/Sources"
flags=(-typecheck -enable-bare-slash-regex -sdk "$sdk" -target arm64-apple-ios26.0-simulator
  -I "$products" -F "$products" -I "$products/include")
[[ -d "$fluid/FastClusterWrapper/include" ]] && flags+=(-I "$fluid/FastClusterWrapper/include")
[[ -d "$fluid/MachTaskSelfWrapper/include" ]] && flags+=(-I "$fluid/MachTaskSelfWrapper/include")
[[ "$configuration" == "debug" ]] && flags+=(-D DEBUG)
find App Shared -name '*.swift' -print0 | xargs -0 xcrun swiftc "${flags[@]}"
