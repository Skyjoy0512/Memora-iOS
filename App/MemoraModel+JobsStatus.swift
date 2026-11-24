import Foundation

extension MemoraModel {
  /// The queued summaries as the person would act on them. The queue itself is
  /// the only state: this reads it, it never keeps its own copy.
  var jobStatusRows: [JobStatusRow] {
    pendingSummaryJobs.compactMap { job -> JobStatusRow? in
      guard let meeting = meeting(id: job.meetingID) else { return nil }
      let isRunning = processing.isActive(meeting.id)
      let state: JobStatusRow.State
      if job.requiresUserRetry == true {
        state = .stopped(reason: "前回の処理が途中で止まりました。もう一度要約してください。")
      } else if job.attemptStartedAt != nil {
        state = .stopped(reason: "送信を始めた記録のため、自動では送り直しません。内容を確認してもう一度要約してください。")
      } else if job.cloudDisclosureConfirmed {
        state = .stopped(reason: "前回のクラウド送信の確認は使い回しません。もう一度確認してください。")
      } else if isRunning {
        let stage: String
        if case .organizing(let detail) = meeting.status, !detail.isEmpty {
          stage = detail
        } else {
          stage = meeting.status.shortLabel
        }
        state = .running(stage: stage)
      } else {
        state = .waiting
      }
      return JobStatusRow(
        jobID: job.id, meetingID: meeting.id, title: meeting.displayTitle,
        state: state, receivedAt: job.createdAt, startedAt: job.attemptStartedAt)
    }
    .sorted {
      if $0.urgency != $1.urgency { return $0.urgency < $1.urgency }
      return $0.receivedAt > $1.receivedAt
    }
  }
}
