import Foundation

enum MemoraLoadingState: Equatable {
  case idle, loading, loaded, empty, failed, refreshing

  var isWorking: Bool { self == .loading || self == .refreshing }
}
