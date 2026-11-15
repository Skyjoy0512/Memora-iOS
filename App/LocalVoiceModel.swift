import Foundation

enum LocalVoiceModel {
  static let name = "Qwen3.5-2B"
  static let filename = "Qwen_Qwen3.5-2B-Q4_K_S.gguf"
  static let byteCount: Int64 = 1_327_696_992
  static let sha256 = "55b574899b75180d084238ffbf5d3d165c568a3d73e1edbd3c826682a986c8d4"
  static let downloadURL = URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF/resolve/7d26695454df6de5fbcce2e58681e62dae06ce43/" + filename)!

  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LocalVoiceModels", isDirectory: true)
  }

  static var fileURL: URL { directory.appendingPathComponent(filename) }
  static var receiptURL: URL { directory.appendingPathComponent("verified-sha256.txt") }

  static var isInstalled: Bool {
    let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
    return (attributes?[.size] as? NSNumber)?.int64Value == byteCount &&
      (try? String(contentsOf: receiptURL, encoding: .utf8)) == sha256
  }
}
