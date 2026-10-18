import Foundation

@main
struct BranchIntegrationChecks {
  static func main() {
    precondition(GlobalGestureFeedbackPolicy.shouldSignalSwipe(x: 45, y: 0, hasSignalled: false))
    precondition(GlobalGestureFeedbackPolicy.shouldSignalSwipe(x: -60, y: 10, hasSignalled: false))
    precondition(!GlobalGestureFeedbackPolicy.shouldSignalSwipe(x: 44, y: 0, hasSignalled: false))
    precondition(!GlobalGestureFeedbackPolicy.shouldSignalSwipe(x: 50, y: 60, hasSignalled: false))
    precondition(!GlobalGestureFeedbackPolicy.shouldSignalSwipe(x: 80, y: 2, hasSignalled: true))
    for invalid: CGFloat in [.nan, .infinity, -.infinity] {
      precondition(!GlobalGestureFeedbackPolicy.shouldSignalSwipe(x: invalid, y: 0, hasSignalled: false))
      precondition(!GlobalGestureFeedbackPolicy.shouldSignalSwipe(x: 90, y: invalid, hasSignalled: false))
    }
    let prompt = AIAnswerPrompt.text(question: "何を確認する？", scopeLabel: "指定した人物", context: "資料の本文", history: "過去の回答")
    precondition(prompt.contains("指定した人物") && prompt.contains("資料の本文") && prompt.contains("過去の回答"))
    precondition(prompt.contains("参照用のデータ") && prompt.contains("外部アクセスや操作を実行したりしない"),
      "The legacy conversational prompt must not remove the current instruction boundary")
    precondition(prompt.contains(AIAnswerPrompt.formatting) && prompt.contains("推測せず"))
    print("BranchIntegrationChecks: passed (intentional horizontal swipe once, invalid samples, conversational formatting preserves source/scope instructions)")
  }
}
