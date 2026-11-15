import Foundation
import Synchronization

final class LocalVoiceModelDownloadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, Sendable {
  private let progress: @Sendable (Double) -> Void
  private let lastProgress = Mutex<Double>(0)

  init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    let value = min(1, Double(totalBytesWritten) / Double(LocalVoiceModel.byteCount))
    let shouldReport = lastProgress.withLock {
      guard value - $0 >= 0.005 || (value >= 1 && $0 < 1) else { return false }
      $0 = value
      return true
    }
    if shouldReport { progress(value) }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
