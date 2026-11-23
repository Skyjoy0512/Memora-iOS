import Foundation
import CoreFoundation

struct ChatGPTTokenResponse: Equatable, Sendable {
  static let planUsageScope = "chatgpt.tokens.use.direct"

  var accessToken: String
  var refreshToken: String?
  var idToken: String?
  var expiresAt: Date
  var scopes: [String]
  var earliestRefreshAt: Date?

  init(data: Data) throws {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let accessToken = object["access_token"] as? String,
          !accessToken.isEmpty,
          !accessToken.contains(where: { $0.isWhitespace }),
          let tokenType = object["token_type"] as? String,
          tokenType.lowercased() == "bearer",
          let expiresIn = Self.number(object["expires_in"]),
          expiresIn.isFinite,
          expiresIn > 0,
          let rawScope = object["scope"] as? String else {
      throw ChatGPTTokenResponseError.invalidResponse
    }

    let scopes = rawScope.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !scopes.isEmpty else { throw ChatGPTTokenResponseError.invalidResponse }

    self.accessToken = accessToken
    self.refreshToken = try Self.optionalToken(object["refresh_token"])
    self.idToken = try Self.optionalToken(object["id_token"])
    self.expiresAt = Date().addingTimeInterval(expiresIn)
    self.scopes = scopes
    self.earliestRefreshAt = Self.refreshHint(object["earliest_refresh_at"])
  }

  static func decode(_ data: Data) throws -> ChatGPTTokenResponse {
    try ChatGPTTokenResponse(data: data)
  }

  private static func optionalToken(_ raw: Any?) throws -> String? {
    guard let raw else { return nil }
    guard let token = raw as? String,
          !token.isEmpty,
          !token.contains(where: { $0.isWhitespace }) else {
      throw ChatGPTTokenResponseError.invalidResponse
    }
    return token
  }

  private static func number(_ raw: Any?) -> Double? {
    guard let raw,
          let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }
    let value = number.doubleValue
    return value.isFinite ? value : nil
  }

  private static func refreshHint(_ raw: Any?) -> Date? {
    if let text = raw as? String {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      if let date = isoDate(trimmed) { return date }
      guard let seconds = Double(trimmed), seconds.isFinite else { return nil }
      return Date(timeIntervalSince1970: seconds)
    }
    guard let seconds = number(raw) else { return nil }
    return Date(timeIntervalSince1970: seconds)
  }

  private static func isoDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
  }
}

/// Why a token response could not be used.
enum ChatGPTTokenResponseError: LocalizedError, Equatable {
  /// The response did not contain usable credentials.
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "認証サーバーの応答を利用できません。もう一度サインインしてください。"
    }
  }
}
