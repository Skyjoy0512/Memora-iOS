import Foundation

// Weekly reviews: a draft of last week, written from the records and waiting
// when a new week starts, so the review is there before anyone asks for it.
extension MemoraModel {
  /// The newest weekly review that has not been opened yet.
  var unreadWeeklyReview: MemoraDocument? {
    documents
      .filter { $0.weekStart != nil && $0.openedAt == nil }
      .max { ($0.weekStart ?? .distantPast) < ($1.weekStart ?? .distantPast) }
  }

  /// Writes last week's review once, the first time the app is opened in a
  /// new week. A week with nothing in it gets no review.
  func prepareWeeklyReviewIfNeeded() {
    guard hasCompletedOnboarding, !isRestoring, !isStoreProtected else { return }
    let calendar = Calendar.current
    guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now),
          let lastWeekDay = calendar.date(byAdding: .day, value: -1, to: thisWeek.start),
          let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastWeekDay) else { return }
    guard !documents.contains(where: { $0.weekStart == lastWeek.start }) else { return }
    makeWeeklyReview(for: lastWeek)
  }

  /// Writes, or rewrites, the review of the week containing `date`. Returns
  /// the document, or nil when there was nothing to review.
  @discardableResult
  func makeWeeklyReview(containing date: Date) -> MemoraDocument? {
    guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: date) else { return nil }
    return makeWeeklyReview(for: week)
  }

  @discardableResult
  private func makeWeeklyReview(for week: DateInterval) -> MemoraDocument? {
    // Sample records are for looking around; a review of them would read as
    // the person's own week.
    let input = WeeklyReviewBuilder.Input(
      week: week,
      meetings: meetings.filter { !SampleContent.isSample(meetingID: $0.id) },
      tasks: tasks.filter { !SampleContent.isSample(task: $0) },
      entries: lifeLogEntries.filter { !SampleContent.isSample(lifeLogEntry: $0) },
      spaceNames: Dictionary(spaces.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    )
    guard let markdown = WeeklyReviewBuilder.markdown(input) else { return nil }

    if let index = documents.firstIndex(where: { $0.weekStart == week.start }) {
      // Rewriting the current week keeps the same document, so a link to it
      // still opens the newest version.
      documents[index].title = WeeklyReviewBuilder.title(for: week)
      documents[index].markdown = markdown
      documents[index].updatedAt = .now
      persistDocuments()
      return documents[index]
    }

    let review = MemoraDocument(
      title: WeeklyReviewBuilder.title(for: week),
      kind: .document,
      markdown: markdown,
      weekStart: week.start
    )
    return addDocument(review) ? review : nil
  }

  func markDocumentOpened(_ id: UUID) {
    guard let index = documents.firstIndex(where: { $0.id == id }), documents[index].openedAt == nil else { return }
    documents[index].openedAt = .now
    persistDocuments()
  }
}
