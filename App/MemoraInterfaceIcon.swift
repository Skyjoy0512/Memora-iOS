import SwiftUI

/// Regular outline glyphs share a consistent size and alignment slot.
struct MemoraInterfaceIcon: View {
  var icon: MemoraIcon

  var body: some View {
    Image(icon: outline, size: MemoraIconMetrics.glyph)
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(MemoraPalette.textPrimary)
      .frame(width: MemoraIconMetrics.slot, height: MemoraIconMetrics.slot)
      .accessibilityHidden(true)
  }

  private var outline: MemoraIcon {
    switch icon {
    case .bellFill: .bell
    case .brainFill: .brain
    case .houseFill: .house
    case .calendarBadgeCheckmarkFill: .calendarBadgeCheckmark
    case .calendarFill: .calendar
    case .chartBarFill: .chartBar
    case .chatBubbleFill: .chatBubble
    case .checklistFill: .checklist
    case .checkmarkCircleFill: .checkmarkCircle
    case .checkmarkSealFill: .checkmarkSeal
    case .phoneFill: .phone
    case .clockFill: .clock
    case .cloudFill: .cloud
    case .cpuFill: .cpu
    case .crownFill: .crown
    case .docTextFill: .docText
    case .dotRadiowavesLeftAndRightFill: .dotRadiowavesLeftAndRight
    case .exclamationmarkTriangleFill: .exclamationmarkTriangle
    case .externaldriveFill: .externaldrive
    case .faceSmilingFill: .faceSmiling
    case .faceidFill: .faceid
    case .folderFill: .folder
    case .gearshapeFill: .gearshape
    case .handRaisedFill: .handRaised
    case .infoCircleFill: .infoCircle
    case .internaldriveFill: .internaldrive
    case .iphoneFill: .iphone
    case .keyFill: .key
    case .locationFill: .location
    case .lockShieldFill: .lockShield
    case .mappinSlashFill: .mappinSlash
    case .micFill: .mic
    case .moonFill: .moon
    case .person3Fill: .person3
    case .personCropCircleFill: .personCropCircle
    case .personFill: .person
    case .photoFill: .photo
    case .playFill: .play
    case .plugsConnectedFill: .plugsConnected
    case .questionmarkCircleFill: .questionmarkCircle
    case .rectangleGrid2x2Fill: .rectangleGrid2x2
    case .rectangleStackFill: .rectangleStack
    case .sparklesFill: .sparkles
    case .stopwatchFill: .stopwatch
    case .trashFill: .trash
    case .waveformFill: .waveform
    case .xmarkCircleFill: .xmarkCircle
    default: icon
    }
  }
}
