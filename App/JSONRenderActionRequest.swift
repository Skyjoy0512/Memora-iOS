import Foundation

struct JSONRenderActionRequest {
  enum Action: String { case copyText, openURL, askAI, completeTask }
  var id: String
  var action: Action
  var params: [String: String]

  init?(body: [String: Any]) {
    guard let id = body["id"] as? String, id.count <= 80,
          let raw = body["action"] as? String, let action = Action(rawValue: raw),
          let params = body["params"] as? [String: String], params.count <= 2,
          params.values.allSatisfy({ $0.utf8.count <= 64 * 1_024 }) else { return nil }
    self.id = id
    self.action = action
    self.params = params
  }
}
