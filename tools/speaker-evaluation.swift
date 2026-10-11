import Foundation

@main
struct SpeakerEvaluationCommand {
  static func main() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 else {
      throw NSError(domain: "SpeakerEvaluation", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Usage: speaker-evaluation /private/path/samples.json 0.6,0.7,0.8"])
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let samples = try decoder.decode([SpeakerEvaluationSample].self,
      from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
    let values = arguments[2].split(separator: ",", omittingEmptySubsequences: false)
    let thresholds = values.compactMap { Double($0) }
    guard thresholds.count == values.count else { throw SpeakerEvaluation.Failure.invalidThresholds }
    let report = try SpeakerEvaluation.report(samples: samples, thresholds: thresholds)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}
