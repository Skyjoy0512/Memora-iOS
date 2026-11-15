import Foundation

struct OpenSourceNotice: Identifiable, Sendable {
  var id: String
  var name: String
  var version: String
  var license: String
  var copyright: String
  var files: [String]
  var url: String

  var text: String {
    files.map { file in
      guard let url = Bundle.main.url(forResource: file, withExtension: nil)
        ?? Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "Resources"),
        let text = try? String(contentsOf: url, encoding: .utf8) else {
        return "\(file) を読み込めませんでした。配布元のライセンスをご確認ください。"
      }
      return text
    }.joined(separator: "\n\n")
  }

  static let all: [Self] = [
    .init(id: "presentation", name: "consulting-pptx-skill", version: "e5f35e57 (2026-10-26)", license: "MIT",
      copyright: "Copyright (c) 2026 Carnot AI Inc.", files: ["ConsultingPPTX-LICENSE.txt"],
      url: "https://github.com/carnot-tech/jinba-consulting-pptx-skill"),
    .init(id: "mcp", name: "MCP Swift SDK", version: "0.12.1", license: "Apache-2.0 / MIT (移行中)",
      copyright: "Model Context Protocol contributors", files: ["MCPSwift-LICENSE.txt"], url: "https://github.com/modelcontextprotocol/swift-sdk"),
    .init(id: "fluid", name: "FluidAudio", version: "0.17.7", license: "Apache-2.0・第三者告知",
      copyright: "Fluid Inference and contributors", files: ["FluidAudio-LICENSE.txt", "NemoTextProcessing-NOTICE.txt",
        "FluidAudio-fastcluster-LICENSE.txt", "FluidAudio-vbx-LICENSE.txt", "FluidAudio-Nemo-LICENSE.txt",
        "FluidAudio-JapaneseG2P-LICENSE.md", "FluidAudio-KokoroAneSpanishFrenchG2P-LICENSE.md"], url: "https://github.com/FluidInference/FluidAudio"),
    .init(id: "community", name: "Community-1 Core ML", version: "df2625ac (モデル)", license: "CC BY 4.0・第三者告知",
      copyright: "pyannote, WeSpeaker, BUT Speech@FIT, Fluid Inference", files: ["Community1-LICENSE.txt", "Community1-NOTICE.txt"],
      url: "https://huggingface.co/FluidInference/speaker-diarization-coreml"),
    .init(id: "lucide", name: "LucideSwift", version: "0.9.11", license: "ISC",
      copyright: "Copyright (c) 2024", files: ["LucideSwift-LICENSE.txt"], url: "https://github.com/ajaxjiang96/lucide-swift"),
    .init(id: "yomiyasu", name: "yomiyasu", version: "2.4.0", license: "MIT",
      copyright: "Copyright (c) 2026 nanaism", files: ["Yomiyasu-LICENSE.txt"], url: "https://github.com/nanaism/yomiyasu"),
    .init(id: "chat-ui", name: "chatgpt-ios-ui", version: "dc6e6a52 (部分移植)", license: "MIT",
      copyright: "Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors", files: ["ChatGPTUI-LICENSE.txt"],
      url: "https://github.com/bryanrg22/chatgpt-ios-ui"),
    .init(id: "volocal", name: "Volocal", version: "b731963b (日本語Liveへの部分移植)", license: "MIT",
      copyright: "Copyright (c) 2026 Fikri Karim", files: ["Volocal-LICENSE.txt"],
      url: "https://github.com/fikrikarim/volocal"),
    .init(id: "writing", name: "日本語の技術文書の書き方", version: "参照指針", license: "Unlicense",
      copyright: "k16shikano (public domain dedication)", files: ["WritingGuide-UNLICENSE.txt"],
      url: "https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d"),
    .init(id: "eventsource", name: "EventSource", version: "1.5.1", license: "MIT",
      copyright: "Copyright 2025 Mattt", files: ["EventSource-LICENSE.txt"], url: "https://github.com/mattt/eventsource"),
    .init(id: "swift-system", name: "Swift System", version: "1.8.1", license: "Apache-2.0 with Runtime Library Exception",
      copyright: "Apple Inc. and the Swift project authors", files: ["SwiftSystem-LICENSE.txt"], url: "https://github.com/apple/swift-system"),
    .init(id: "swift-log", name: "SwiftLog", version: "1.16.1", license: "Apache-2.0",
      copyright: "Apple Inc. and SwiftLog project authors", files: ["SwiftLog-LICENSE.txt", "SwiftLog-NOTICE.txt"], url: "https://github.com/apple/swift-log"),
    .init(id: "swift-atomics", name: "Swift Atomics", version: "1.3.1 (解決済み間接依存)", license: "Apache-2.0 with Runtime Library Exception",
      copyright: "Apple Inc. and the Swift project authors", files: ["SwiftAtomics-LICENSE.txt"], url: "https://github.com/apple/swift-atomics"),
    .init(id: "swift-collections", name: "Swift Collections", version: "1.7.3 (解決済み間接依存)", license: "Apache-2.0 with Runtime Library Exception",
      copyright: "Apple Inc. and the Swift project authors", files: ["SwiftCollections-LICENSE.txt"], url: "https://github.com/apple/swift-collections"),
    .init(id: "swift-nio", name: "SwiftNIO", version: "2.104.0 (SDK検証用の解決依存)", license: "Apache-2.0",
      copyright: "Apple Inc. and SwiftNIO project authors", files: ["SwiftNIO-LICENSE.txt"], url: "https://github.com/apple/swift-nio")
  ]
}
