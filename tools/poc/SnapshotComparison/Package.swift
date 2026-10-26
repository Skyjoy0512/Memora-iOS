// swift-tools-version: 6.0
import PackageDescription

// Development-only image comparison. Not linked to any Memora app target.
let package = Package(
  name: "MemoraSnapshotComparisonPoC",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.7")
  ],
  targets: [
    .testTarget(name: "SimulatorImageComparisonTests", dependencies: [
      .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
    ])
  ]
)
