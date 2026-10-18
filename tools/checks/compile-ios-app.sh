#!/bin/bash
# Compiles App/ and Shared/ as one module to an object file against the iOS
# Simulator SDK. This catches code-generation errors but does not link an app
# bundle. It exists for linked git worktrees, which Bitrig does not register.
# Usage: compile-ios-app.sh <products-dir> [debug|release]
set -euo pipefail
cd "$(dirname "$0")/../.."
products=${1:?usage: compile-ios-app.sh <products-dir> [debug|release]}
configuration=${2:-debug}
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
derived=$(cd "$products/../../.." && pwd)
fluid="$derived/SourcePackages/checkouts/FluidAudio/Sources"
out=$(mktemp -d "${TMPDIR:-/tmp}/memora-ios-object.XXXXXX")
trap 'rm -rf "$out"' EXIT
flags=(-c -whole-module-optimization -parse-as-library -enable-bare-slash-regex
  -sdk "$sdk" -target arm64-apple-ios26.0-simulator
  -I "$products" -F "$products" -I "$products/include"
  -o "$out/Memora.o")
[[ -d "$fluid/FastClusterWrapper/include" ]] && flags+=(-I "$fluid/FastClusterWrapper/include")
[[ -d "$fluid/MachTaskSelfWrapper/include" ]] && flags+=(-I "$fluid/MachTaskSelfWrapper/include")
if [[ "$configuration" == "debug" ]]; then flags+=(-D DEBUG); else flags+=(-O); fi
find App Shared -name '*.swift' -print0 | xargs -0 xcrun swiftc "${flags[@]}"
ls -lh "$out/Memora.o"
