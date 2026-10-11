import Foundation
import LocalAuthentication

@main
struct AppLockChecks {
  @MainActor
  static func main() async {
    for code in [LAError.Code.passcodeNotSet, .biometryLockout, .invalidContext, .systemCancel, .userCancel] {
      let service = AppLockService(authentication: {
        throw NSError(domain: LAError.errorDomain, code: code.rawValue)
      }, lockEnabled: { true })
      service.lockIfEnabled()
      await service.unlock()
      precondition(service.isLocked && service.authenticationMessage != nil && !service.isAuthenticating)
    }
    let rejected = AppLockService(authentication: { false }, lockEnabled: { true })
    rejected.lockIfEnabled()
    await rejected.unlock()
    precondition(rejected.isLocked && rejected.authenticationMessage != nil)
    var attempts = 0
    let retry = AppLockService(authentication: {
      attempts += 1
      return attempts > 1
    }, lockEnabled: { true })
    retry.lockIfEnabled()
    await retry.unlock()
    precondition(retry.isLocked)
    await retry.unlock()
    precondition(!retry.isLocked && retry.authenticationMessage == nil)
    let disabled = AppLockService(authentication: { true }, lockEnabled: { false })
    disabled.lockIfEnabled()
    precondition(!disabled.isLocked)
    print("App lock checks passed")
  }
}
