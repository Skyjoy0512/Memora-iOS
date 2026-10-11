import Foundation
import FluidAudio

enum SpeakerModelProbe {
  static func run() async -> String {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("SpeakerProbe-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: file) }
    do {
      let samples = [Float](repeating: 0, count: 160_000)
      let data = try AudioWAV.data(from: samples, sampleRate: 16_000, normalize: false)
      try data.write(to: file, options: [.atomic, .completeFileProtection])
      _ = try await FluidSpeakerDiarizationService.shared.analyze(file)
      return "要確認：無音を発話として判定しました。実音声での検証が必要です。"
    } catch SpeakerProcessingFailure.noSpeech {
      return "モデル読み込み・無音の検出に成功しました。本人識別や日本語の実会話精度を確認した結果ではありません。"
    } catch {
      return "モデル動作チェックを完了できませんでした。\(error.localizedDescription)"
    }
  }
}
