import Foundation

/// Keeps the ChatGPT connection in the keychain.
///
/// The client ID is stored on its own as well, so it survives a cleared token
/// and the next sign-in reuses the registration instead of making a new one.
enum ChatGPTCredentialStore {
  private static let connectionKey = "chatgpt.connection"
  private static let clientIDKey = "chatgpt.clientID"

  /// Reads the stored connection, or `nil` when there is none.
  static func load() -> ChatGPTConnection? {
    guard let text = KeychainStore.string(forKey: connectionKey),
          let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let clientID = object["clientID"] as? String, !clientID.isEmpty,
          let subject = object["subject"] as? String, !subject.isEmpty,
          let accessToken = object["accessToken"] as? String, !accessToken.isEmpty,
          let scopes = object["scopes"] as? [String],
          let expiresAt = object["expiresAt"] as? Double else {
      return nil
    }
    return ChatGPTConnection(
      clientID: clientID,
      subject: subject,
      email: object["email"] as? String,
      name: object["name"] as? String,
      scopes: scopes,
      accessToken: accessToken,
      refreshToken: object["refreshToken"] as? String,
      expiresAt: Date(timeIntervalSince1970: expiresAt),
      earliestRefreshAt: (object["earliestRefreshAt"] as? Double).map { Date(timeIntervalSince1970: $0) },
      idToken: object["idToken"] as? String
    )
  }

  /// Writes the connection. Returns whether the write succeeded.
  @discardableResult
  static func save(_ connection: ChatGPTConnection) -> Bool {
    guard !connection.clientID.isEmpty, !connection.subject.isEmpty,
          !connection.accessToken.isEmpty else { return false }
    guard KeychainStore.set(connection.clientID, forKey: clientIDKey) else { return false }
    var object: [String: Any] = [
      "clientID": connection.clientID,
      "subject": connection.subject,
      "scopes": connection.scopes,
      "accessToken": connection.accessToken,
      "expiresAt": connection.expiresAt.timeIntervalSince1970
    ]
    if let email = connection.email { object["email"] = email }
    if let name = connection.name { object["name"] = name }
    if let refreshToken = connection.refreshToken { object["refreshToken"] = refreshToken }
    if let earliestRefreshAt = connection.earliestRefreshAt {
      object["earliestRefreshAt"] = earliestRefreshAt.timeIntervalSince1970
    }
    if let idToken = connection.idToken { object["idToken"] = idToken }
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object),
          let text = String(data: data, encoding: .utf8) else {
      return false
    }
    return KeychainStore.set(text, forKey: connectionKey)
  }

  /// Removes the stored connection. Returns whether the removal succeeded.
  @discardableResult
  static func clear() -> Bool {
    let removedConnection = KeychainStore.set(nil, forKey: connectionKey)
    let removedClientID = KeychainStore.set(nil, forKey: clientIDKey)
    return removedConnection && removedClientID
  }

  /// The client ID OpenAI issued, when one is stored.
  static func storedClientID() -> String? {
    guard let clientID = KeychainStore.string(forKey: clientIDKey), !clientID.isEmpty else {
      return nil
    }
    return clientID
  }

  /// Whether a plan usage permission was granted.
  static func hasPlanUsage() -> Bool {
    guard let connection = load() else { return false }
    return ChatGPTScope.includesPlanUsage(connection.scopes)
  }
}
