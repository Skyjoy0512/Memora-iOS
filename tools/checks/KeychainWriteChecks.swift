import Foundation
import Security

@main
enum KeychainWriteChecks {
  static func main() {
    let bytes = Data([0x00, 0xFF])
    let key = kSecAttrAccount as String
    let protection = kSecAttrAccessible as String
    let data = kSecValueData as String
    let query = [key: "memora-check"]
    let cases: [(String, [OSStatus], OSStatus?, [String], Bool)] = [
      ("update", [errSecSuccess], nil, ["update"], true),
      ("locked", [errSecInteractionNotAllowed], nil, ["update"], false),
      ("unknown update failure", [errSecParam], nil, ["update"], false),
      ("insert", [errSecItemNotFound], errSecSuccess, ["update", "add"], true),
      ("insert fails", [errSecItemNotFound], errSecNotAvailable, ["update", "add"], false),
      ("concurrent insert", [errSecItemNotFound, errSecSuccess], errSecDuplicateItem, ["update", "add", "update"], true),
      ("concurrent insert then lock", [errSecItemNotFound, errSecInteractionNotAllowed], errSecDuplicateItem, ["update", "add", "update"], false)
    ]
    for (label, updateResults, addResult, expectedCalls, expectedResult) in cases {
      var remaining = updateResults
      var calls: [String] = []
      let written = KeychainStore.write(bytes, matching: query) { match, attributes in
        calls.append("update")
        precondition((match as NSDictionary)[key] as? String == "memora-check")
        let values = attributes as NSDictionary
        precondition(values[data] as? Data == bytes)
        precondition(values[protection] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        return remaining.removeFirst()
      } add: { attributes in
        calls.append("add")
        let values = attributes as NSDictionary
        precondition(values[key] as? String == "memora-check")
        precondition(values[data] as? Data == bytes)
        precondition(values[protection] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        return addResult ?? errSecParam
      }
      precondition(written == expectedResult && calls == expectedCalls && remaining.isEmpty, label)
    }
    #if DEBUG && MEMORA_ENABLE_CHATGPT_SIGN_IN
    precondition(FeatureFlags.isChatGPTSignInEnabled)
    #else
    precondition(!FeatureFlags.isChatGPTSignInEnabled)
    #endif
    print("Keychain write sequencing and ChatGPT build flag passed")
  }
}
