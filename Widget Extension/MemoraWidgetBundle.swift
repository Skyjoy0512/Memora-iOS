import SwiftUI
import WidgetKit

@main
struct MemoraWidgetBundle: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    MemoraCaptureWidget()
    MemoraAskAIWidget()
    MemoraTodayWidget()
    MemoraProjectWidget()
    MemoraRecordingLiveActivity()

    if #available(iOSApplicationExtension 18.0, *) {
      MemoraRecordControl()
    }
  }
}
