import Foundation
import Darwin

@main enum MeasureCompanyTemplate {
  static func main() {
    do { try measure() }
    catch {
      FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      exit(1)
    }
  }

  static func measure() throws {
    guard CommandLine.arguments.count == 3 else { throw CompanyTemplateEngine.Failure.fields }
    let input = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    guard !FileManager.default.fileExists(atPath: output.path) else { throw CompanyTemplateEngine.Failure.save }
    let analysis = try CompanyTemplateEngine.analyze(input, format: .pptx)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(analysis).write(to: output, options: .withoutOverwriting)
    guard let profile = analysis.presentation else { throw OfficeArchiveReader.Failure.invalid }
    print("Measured locally: \(profile.slideCount) slides, \(profile.masters.count) masters, \(profile.layouts.count) layouts; no file modified or uploaded; master application/rendering unverified")
  }
}
