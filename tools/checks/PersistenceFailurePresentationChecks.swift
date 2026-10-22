import Foundation

@main
@MainActor
struct PersistenceFailurePresentationChecks {
  static func main() {
    let presentation = PersistenceFailurePresentation()
    precondition(presentation.shouldPresentGlobally)
    let result = presentation.locallyHandled {
      precondition(!presentation.shouldPresentGlobally)
      let nested = presentation.locallyHandled {
        precondition(!presentation.shouldPresentGlobally)
        return false
      }
      precondition(!nested && !presentation.shouldPresentGlobally)
      return 42
    }
    precondition(result == 42 && presentation.shouldPresentGlobally)
    do {
      try presentation.locallyHandled {
        precondition(!presentation.shouldPresentGlobally)
        throw CocoaError(.fileWriteUnknown)
      }
      preconditionFailure("Expected test error")
    } catch { precondition(presentation.shouldPresentGlobally) }
    print("PersistenceFailurePresentationChecks: passed (global default, explicit synchronous local scope, nested return/throw cleanup, no async scope)")
  }
}
