import Foundation

/// Hold a real worker result so the test controls the publication ordering without sleeps.
actor CompanyPresentationPreviewGate {
  private var result: Result<Void, Error>?
  private var arrival: CheckedContinuation<Void, Error>?
  private var held: CheckedContinuation<Void, Never>?

  func hold() async {
    await withCheckedContinuation { continuation in
      held = continuation
      result = .success(())
      arrival?.resume(); arrival = nil
    }
  }

  func arrived() async throws {
    if let result { try result.get(); return }
    try await withCheckedThrowingContinuation { arrival = $0 }
  }

  func fail(_ error: Error) {
    result = .failure(error)
    arrival?.resume(throwing: error); arrival = nil
  }

  func release() { held?.resume(); held = nil }
}
