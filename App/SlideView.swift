import SwiftUI

/// Draws one slide on a white 16:9 page, at the same positions the PowerPoint
/// export uses, scaled to whatever width it is given. Slides stay on white in
/// dark mode, the way a presentation file will look.
struct SlideView: View {
  var slide: DocumentSlide

  private typealias Layout = PPTXWriter.Layout
  private static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)
  private static let ink = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

  var body: some View {
    GeometryReader { proxy in
      canvas
        .frame(width: 960, height: 540, alignment: .topLeading)
        .scaleEffect(proxy.size.width / 960, anchor: .topLeading)
    }
    .aspectRatio(16 / 9, contentMode: .fit)
    .background(Color.white)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(([slide.title] + slide.bullets).joined(separator: "、"))
  }

  private var canvas: some View {
    ZStack(alignment: .topLeading) {
      Color.white

      if slide.isTitleSlide {
        Text(slide.title)
          .font(.system(size: Layout.coverTitleSize, weight: .bold))
          .foregroundStyle(Self.ink)
          .minimumScaleFactor(0.5)
          .frame(width: Layout.contentWidth, height: Layout.coverTitleHeight, alignment: .bottomLeading)
          .offset(x: Layout.margin, y: Layout.coverTitleTop)

        Self.accent
          .frame(width: 86, height: 4)
          .offset(x: Layout.margin, y: Layout.coverAccentTop)
      } else {
        Text(slide.title)
          .font(.system(size: Layout.titleSize, weight: .bold))
          .foregroundStyle(Self.ink)
          .minimumScaleFactor(0.5)
          .frame(width: Layout.contentWidth, height: Layout.titleHeight, alignment: .bottomLeading)
          .offset(x: Layout.margin, y: Layout.titleTop)

        Self.accent
          .frame(width: 72, height: 3.6)
          .offset(x: Layout.margin, y: Layout.accentTop)

        VStack(alignment: .leading, spacing: 14) {
          ForEach(Array(slide.bullets.enumerated()), id: \.offset) { _, bullet in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text("•")
                .foregroundStyle(Self.accent)
              Text(bullet)
                .foregroundStyle(Self.ink)
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: Layout.bulletSize))
          }
        }
        .minimumScaleFactor(0.6)
        .padding(.top, 14)
        .frame(width: Layout.contentWidth, height: Layout.bodyHeight, alignment: .topLeading)
        .offset(x: Layout.margin, y: Layout.bodyTop)
      }
    }
    .environment(\.colorScheme, .light)
  }
}
