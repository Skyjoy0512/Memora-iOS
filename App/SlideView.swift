import SwiftUI

/// A fixed-size presentation page; surrounding reading UI supports Dynamic Type.
struct SlideView: View {
  var page: SlidePage

  private typealias Layout = SlidePageLayout
  private static let ink = Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)

  var body: some View {
    GeometryReader { proxy in
      Group {
        if let elements = page.elements {
          Canvas { context, _ in
            context.withCGContext { cg in PresentationDrawing.draw(elements, in: cg) }
          }
          .background(.white)
        } else {
          canvas
        }
      }
        .frame(width: Layout.size.width, height: Layout.size.height, alignment: .topLeading)
        .scaleEffect(proxy.size.width / Layout.size.width, anchor: .topLeading)
    }
    .aspectRatio(16 / 9, contentMode: .fit)
    .background(Color.white)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(([page.title] + (page.readingText ?? page.bullets.map(\.text))).joined(separator: "、"))
  }

  private var canvas: some View {
    let titleHeight = page.isCover ? Layout.coverLineHeight : Layout.titleLineHeight
    let titleTop = page.isCover ? Layout.coverTitleTop : Layout.titleTop
    let titleSize = page.isCover ? Layout.coverTitleSize : Layout.titleSize
    return ZStack(alignment: .topLeading) {
      Color.white
      VStack(alignment: .leading, spacing: 0) {
        ForEach(page.titleLines.indices, id: \.self) { index in
          Text(verbatim: Layout.visibleLine(page.titleLines[index]))
            .lineLimit(1)
            .font(.custom(Layout.boldFont, fixedSize: titleSize))
            .frame(width: Layout.contentWidth, height: titleHeight, alignment: .leading)
        }
      }
      .offset(x: Layout.margin, y: titleTop)

      VStack(alignment: .leading, spacing: Layout.bulletGap) {
        ForEach(page.bullets) { bullet in
          HStack(alignment: .top, spacing: 0) {
            Text(bullet.showsMarker ? "•" : "")
              .frame(width: Layout.bulletIndent, height: Layout.bulletLineHeight, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
              ForEach(bullet.lines.indices, id: \.self) { index in
                Text(verbatim: Layout.visibleLine(bullet.lines[index]))
                  .lineLimit(1)
                  .frame(width: Layout.contentWidth - Layout.bulletIndent,
                         height: Layout.bulletLineHeight, alignment: .leading)
              }
            }
          }
          .font(.custom(Layout.regularFont, fixedSize: Layout.bulletSize))
        }
      }
      .offset(x: Layout.margin, y: Layout.bodyTop)
    }
    .foregroundStyle(Self.ink)
    .environment(\.colorScheme, .light)
  }
}
