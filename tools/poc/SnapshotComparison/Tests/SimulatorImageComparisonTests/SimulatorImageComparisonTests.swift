import AppKit
import SnapshotTesting
import XCTest

final class SimulatorImageComparisonTests: XCTestCase {
  func testCapturedImagesMatchThemselvesExactly() throws {
    for name in ["onboarding-after", "auth-after", "plan-after", "document-revision-light", "pptx-poc-quicklook-cover"] {
      let reference = try image(name)
      let reloaded = try image(name)
      XCTAssertNil(Diffing<NSImage>.image.diffV2(reference, reloaded), name)
    }
  }

  func testBeforeAfterAndAppearanceChangesAreDetected() throws {
    for pair in [("onboarding-before", "onboarding-after"), ("auth-before", "auth-after"),
                 ("plan-before", "plan-after"), ("document-revision-light", "document-revision-dark-accessibility"),
                 ("pptx-poc-quicklook-original", "pptx-poc-quicklook-cover")] {
      let reference = try image(pair.0)
      let candidate = try image(pair.1)
      // A deliberately different fixture must fail the comparator. No baseline is recorded or updated.
      let difference = Diffing<NSImage>.image.diffV2(reference, candidate)
      XCTAssertNotNil(difference, "\(pair.0) vs \(pair.1)")
      if let folder = ProcessInfo.processInfo.environment["MEMORA_SNAPSHOT_DIFF_OUTPUT_DIRECTORY"] {
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for case let .data(bytes, name) in difference?.1 ?? [] where name == "difference.png" {
          try bytes.write(to: directory.appendingPathComponent(pair.0 + "--" + pair.1 + ".png"), options: .atomic)
        }
      }
    }
  }

  private func image(_ name: String) throws -> NSImage {
    let folder = try XCTUnwrap(ProcessInfo.processInfo.environment["MEMORA_SNAPSHOT_FIXTURES_DIRECTORY"])
    return try XCTUnwrap(NSImage(contentsOfFile: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png").path))
  }
}
