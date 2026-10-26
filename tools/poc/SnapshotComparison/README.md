# SnapshotTesting image-comparison PoC

Test-only MIT-licensed SnapshotTesting 1.19.7, outside the app dependency graph.
The tests compare real Simulator PNGs already in `docs/comprehensive-improvement`.
They never create/update baselines, access application records or contact an AI.

Run on the Mac with Swift 6, placing all build/cache data on external scratch:

```sh
MEMORA_SNAPSHOT_FIXTURES_DIRECTORY="<checkout>/docs/comprehensive-improvement" \
swift test --package-path tools/poc/SnapshotComparison \
  --scratch-path <external-scratch>/build --cache-path <external-scratch>/cache \
  --config-path <external-scratch>/config --security-path <external-scratch>/security
```

Optionally set `MEMORA_SNAPSHOT_DIFF_OUTPUT_DIRECTORY` to an external scratch
directory to retain difference PNGs (never the baseline directory).

Five identical pairs must match; five deliberately different pairs must not match,
including the source/edited PPTX's actual Quick Look cover renderings.
This proves the Mac comparator and fixture pipeline, not an iOS XCTest host,
SwiftUI capture, keyboard/IME automation, approved visual regressions or device tests.
App/Project.json is unchanged; no SnapshotTesting runtime is shipped to the iPhone.
The package and transitive notices must be retained if redistributing the tool.
