import AppKit
import Foundation
import PDFKit

/// Compares the pinned Jinba catalog pages with Memora's rendered 65 layouts.
/// It measures geometry and ink, not taste: a passing row means the page is not
/// obviously emptier or differently margined, never that the design is approved.
@main
enum CompareJinbaCatalog {
  struct Metrics {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double
    var inkRatio: Double
    var blueShare: Double
    var orangeShare: Double
    var box: CGRect
  }

  static func main() throws {
    let arguments = CommandLine.arguments
    guard arguments.count >= 4 else {
      print("usage: compare-jinba-catalog <SlideCatalog_16x9.pdf> <memora-png-dir> <report.md>")
      exit(2)
    }
    let catalogURL = URL(fileURLWithPath: arguments[1])
    let memoraURL = URL(fileURLWithPath: arguments[2])
    let reportURL = URL(fileURLWithPath: arguments[3])
    guard let catalog = PDFDocument(url: catalogURL) else { throw Failure("Jinba PDFを開けません") }
    guard catalog.pageCount == SlideArchetype.allCases.count else {
      throw Failure("Jinba PDFのページ数 \(catalog.pageCount) が65型と一致しません")
    }

    var rows: [String] = []
    var flagged = 0
    for (index, layout) in SlideArchetype.allCases.enumerated() {
      guard let page = catalog.page(at: index),
            let jinba = metrics(rasterize(page)),
            let memoraImage = NSImage(contentsOf: memoraURL.appendingPathComponent(layout.rawValue + ".png")),
            let memora = metrics(memoraImage) else {
        rows.append("| \(layout.rawValue) | \(layout.title) | 読み込み失敗 | - | - | - |")
        flagged += 1
        continue
      }
      let marginDelta = max(abs(jinba.left - memora.left), abs(jinba.top - memora.top),
        abs(jinba.right - memora.right), abs(jinba.bottom - memora.bottom))
      let inkRatio = jinba.inkRatio > 0.0001 ? memora.inkRatio / jinba.inkRatio : 0
      let intersection = jinba.box.intersection(memora.box)
      let union = jinba.box.union(memora.box)
      let overlap = union.width * union.height > 0 ? (intersection.width * intersection.height) / (union.width * union.height) : 0
      var notes: [String] = []
      if marginDelta > 0.08 { notes.append("余白差") }
      if inkRatio < 0.4 || inkRatio > 2.5 { notes.append("情報密度差") }
      if overlap < 0.45 { notes.append("版面位置差") }
      if memora.inkRatio < 0.01 { notes.append("空きすぎ") }
      if !notes.isEmpty { flagged += 1 }
      rows.append(String(
        format: "| %@ | %@ | %.1f%% | %.1f%% | %.2f | %.0f%% | %@ |",
        layout.rawValue, layout.title, marginDelta * 100, memora.inkRatio * 100,
        inkRatio, overlap * 100, notes.isEmpty ? "一致" : notes.joined(separator: "・")))
    }

    let header = """
    # Jinba原本とMemora 65型の機械比較

    - Jinba: `\(catalogURL.lastPathComponent)`（\(catalog.pageCount)ページ）
    - Memora: `\(memoraURL.path)`
    - 検査日: \(Date.now.formatted(date: .numeric, time: .shortened))
    - 比較するもの: 余白、インク量（情報密度）、版面の重なり、青/オレンジの使用率
    - **合格の意味**: 明らかな余白・密度・位置の差がないこと。色・書体・最終的な美しさは
      目視とPowerPoint/Keynoteの実描画で確認する。自動一致は完成証明ではない。

    | 型 | 名前 | 余白差 | Memora密度 | 密度比 | 版面重なり | 判定 |
    |---|---|---|---|---|---|---|
    """
    let footer = """

    ## 集計

    - 比較: 65/65
    - 機械的な差あり: \(flagged)/65
    - 目視・実描画で合格: 0/65（未実施。機械比較は完成証明ではない）
    - 色はJinbaの暖色とMemoraの白黒青オレンジで意図的に異なるため、判定に含めない。
    - 残課題: 目視レビュー、PowerPoint/Keynote/PDFの実描画、実データでの折返し・表の改行。
    """
    try (header + "\n" + rows.joined(separator: "\n") + "\n" + footer)
      .write(to: reportURL, atomically: true, encoding: .utf8)
    print("Jinba comparison: 65 pages, \(flagged) flagged, report \(reportURL.path)")
  }

  // MARK: - Metrics

  static func rasterize(_ page: PDFPage) -> NSImage {
    page.thumbnail(of: NSSize(width: 960, height: 540), for: .mediaBox)
  }

  static func metrics(_ image: NSImage) -> Metrics? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff), let cg = bitmap.cgImage else { return nil }
    let width = 240, height = 135
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

    var minX = width, minY = height, maxX = -1, maxY = -1
    var ink = 0, blue = 0, orange = 0
    for y in 0..<height {
      for x in 0..<width {
        let offset = (y * width + x) * 4
        let r = Double(pixels[offset]) / 255
        let g = Double(pixels[offset + 1]) / 255
        let b = Double(pixels[offset + 2]) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let isInk = luminance < 0.92
        guard isInk else { continue }
        ink += 1
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
        if b > r + 0.12 && b > g + 0.05 { blue += 1 }
        if r > b + 0.12 && g > b + 0.02 && r > 0.5 { orange += 1 }
      }
    }
    let total = Double(width * height)
    let box = maxX >= minX && maxY >= minY
      ? CGRect(x: Double(minX) / Double(width), y: Double(minY) / Double(height),
               width: Double(maxX - minX) / Double(width), height: Double(maxY - minY) / Double(height))
      : .zero
    let inkCount = max(1, ink)
    return Metrics(left: box.minX, top: box.minY,
      right: 1 - box.maxX, bottom: 1 - box.maxY,
      inkRatio: Double(ink) / total,
      blueShare: Double(blue) / Double(inkCount), orangeShare: Double(orange) / Double(inkCount),
      box: box)
  }

  struct Failure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
  }
}
