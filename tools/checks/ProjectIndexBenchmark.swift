import Foundation

@main
struct ProjectIndexBenchmark {
  static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = ProjectSearchIndex(fileURL: directory.appendingPathComponent("index.sqlite"))
    for count in [100, 1_000] {
      let project = UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", count))!
      let inputs = (0..<count).map { number in
        ProjectEvidenceInput(target: .source(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number + 1))!), title: "資料 \(number)", blocks: [
          ProjectSourceText(text: String(repeating: "箱根旅行の移動時間と予算を確認する。", count: 20), page: number + 1)
        ])
      }
      var cold: [Double] = []
      for _ in 0..<21 {
        try await index.remove(projectID: project)
        let start = ContinuousClock.now
        _ = try await index.retrieve(question: "移動時間", projectID: project, inputs: inputs)
        let d = start.duration(to: .now).components
        cold.append(Double(d.seconds) * 1_000 + Double(d.attoseconds) / 1e15)
      }
      cold.sort()
      print(String(format: "index-rebuild,%d,median=%.3f,p95=%.3f,max=%.3f", count, cold[10], cold[19], cold[20]))
      var samples: [Double] = []
      for _ in 0..<21 {
        let start = ContinuousClock.now
        let result = try await index.retrieve(question: "移動時間", projectID: project, inputs: inputs)
        precondition(!result.isEmpty && result.allSatisfy { $0.projectID == project })
        let duration = start.duration(to: .now).components
        samples.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
      }
      samples.sort()
      print(String(format: "index,%d,median=%.3f,p95=%.3f,max=%.3f", count,
        samples[10], samples[19], samples[20]))
    }
  }
}
