import Foundation

extension MemoraModel {
  func dismissLoadFailure() {
    loadFailureMessage = nil
  }

  func completeOnboarding() {
    hasCompletedOnboarding = true
    UserDefaults.standard.set(true, forKey: StorageKey.hasCompletedOnboarding)
  }

  func replayOnboarding() {
    hasCompletedOnboarding = false
    UserDefaults.standard.set(false, forKey: StorageKey.hasCompletedOnboarding)
  }

  var isSignedIn: Bool {
    account != nil
  }

  func signIn(with provider: AuthProvider, email: String? = nil, displayName: String? = nil) {
    let address = email ?? Self.placeholderEmail(for: provider)
    persistAccount(
      MemoraAccount(
        displayName: displayName ?? Self.placeholderName(for: provider, email: address),
        email: address,
        provider: provider,
        createdAt: account?.createdAt ?? .now
      )
    )
  }

  func signOut() {
    persistAccount(nil)
  }

  func deleteAccount() {
    persistAccount(nil)
    aiHistory = []
  }

  /// Purchases are tied to the Apple ID, so Plus does not require a Memora
  /// account. Signing in only adds sync.
  func startSubscription(plan: MemoraPlan = .pro) {
    choosePlan(plan)
  }

  /// Sets the plan this device runs on. StoreKit is not connected, so this is a
  /// local preference: the plan screen is explicit that no billing happened.
  func choosePlan(_ plan: MemoraPlan?) {
    self.plan = plan
    isSubscribed = plan != nil || activeLicense != nil
    let defaults = UserDefaults.standard
    defaults.set(isSubscribed, forKey: StorageKey.isSubscribed)
    defaults.removeObject(forKey: StorageKey.planTier)
    if let plan {
      defaults.set(plan.rawValue, forKey: StorageKey.plan)
    } else {
      defaults.removeObject(forKey: StorageKey.plan)
      if !isSubscribed { setCloudStorageEnabled(false) }
    }
  }

  var cloudStorageStatus: String { "未接続" }

  func setCloudStorageEnabled(_ enabled: Bool) {
    cloudStorageEnabled = false
  }

  /// Offers Plus once, and only after someone has seen a conversation get
  /// organized, so the value is visible before the price is.
  func offerPlusIfNeeded() {
    guard !hasOfferedPlus, !isSubscribed else { return }
    hasOfferedPlus = true
    UserDefaults.standard.set(true, forKey: StorageKey.hasOfferedPlus)
    isPaywallPresented = true
  }

  private func persistAccount(_ account: MemoraAccount?) {
    self.account = account
    if let account, persistNow(account, forKey: StorageKey.account) {
      // The legacy copy is only cleared once the store has it.
      UserDefaults.standard.removeObject(forKey: StorageKey.account)
    } else if account == nil {
      try? RecordStore.remove(StorageKey.account)
      UserDefaults.standard.removeObject(forKey: StorageKey.account)
    }
  }

  private static func placeholderEmail(for provider: AuthProvider) -> String {
    switch provider {
    case .apple:
      "you@privaterelay.appleid.com"
    case .google:
      "you@gmail.com"
    case .email:
      "you@example.com"
    }
  }

  private static func placeholderName(for provider: AuthProvider, email: String) -> String {
    switch provider {
    case .apple, .google:
      provider.label + "ユーザー"
    case .email:
      String(email.prefix(while: { $0 != "@" }))
    }
  }
}
