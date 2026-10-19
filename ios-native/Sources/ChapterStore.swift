import Foundation
import Observation

@MainActor @Observable
final class ChapterStore {
  private(set) var feed: ChapterFeed?
  private(set) var member: MemberProfile?
  private(set) var isSignedIn = false
  private(set) var isLoading = false
  private(set) var isBusy = false
  private(set) var isReadingSavedContent = false
  private(set) var feedError: String?
  private(set) var memberError: String?

  @ObservationIgnored private let api: any ChapterAPI
  @ObservationIgnored private let sessions: any SessionStorage
  @ObservationIgnored private let cache: any FeedStorage
  @ObservationIgnored private var token: String?
  @ObservationIgnored private var didInitialize = false
  @ObservationIgnored private var verificationGeneration = 0
  @ObservationIgnored private var feedGeneration = 0

  init(api: any ChapterAPI, sessions: any SessionStorage, cache: any FeedStorage) {
    self.api = api
    self.sessions = sessions
    self.cache = cache
  }

  static func live(configuration: AppConfiguration) -> ChapterStore {
    ChapterStore(
      api: NativeChapterAPI(configuration: configuration),
      sessions: KeychainSessionStorage(namespace: configuration.storageNamespace),
      cache: NativeFeedCache(namespace: configuration.storageNamespace))
  }

  func loadOrRefresh() async {
    if !didInitialize {
      do {
        feed = try await cache.read()
        isReadingSavedContent = feed != nil
      } catch { /* A damaged public cache is replaced on a successful fetch. */  }
      do {
        token = try await sessions.read()
        isSignedIn = token != nil
      } catch { memberError = "Secure storage is unavailable. Unlock your device and try again." }
      didInitialize = true
    }
    await refresh()
  }

  func refresh() async {
    isLoading = true
    defer { isLoading = false }
    // A fixed pair of structured tasks; UI mutations remain on MainActor.
    async let publicUpdate: Void = refreshFeed()
    async let privateUpdate: Void = refreshMember()
    _ = await (publicUpdate, privateUpdate)
  }

  func refreshFeed() async {
    feedGeneration += 1
    let generation = feedGeneration
    do {
      let updated = try await api.fetchFeed()
      guard !Task.isCancelled, generation == feedGeneration else { return }
      feed = updated
      isReadingSavedContent = false
      feedError = nil
      try? await cache.write(updated)
    } catch is CancellationError { return } catch {
      guard generation == feedGeneration else { return }
      isReadingSavedContent = feed != nil
      feedError = error.localizedDescription
    }
  }

  func refreshMember() async {
    guard let token else { return }
    verificationGeneration += 1
    let generation = verificationGeneration
    do {
      let updated = try await api.fetchMember(token: token)
      guard !Task.isCancelled, self.token == token, generation == verificationGeneration else {
        return
      }
      member = updated
      memberError = nil
    } catch is CancellationError { return } catch {
      guard self.token == token, generation == verificationGeneration else { return }
      member = nil
      memberError = error.localizedDescription
      if let error = error as? APIError, error.requiresSignIn {
        self.token = nil
        isSignedIn = false
        try? await sessions.remove()
      }
    }
  }

  func invalidateVerification() {
    verificationGeneration += 1
    member = nil
  }

  func activate(code: String) async {
    guard !isBusy else { return }
    isBusy = true
    memberError = nil
    defer { isBusy = false }
    do {
      let issued = try await api.activate(
        code: code.trimmingCharacters(in: .whitespacesAndNewlines))
      do { try await sessions.write(issued) } catch {
        try? await api.signOut(token: issued)
        throw APIError.secureStorage
      }
      token = issued
      isSignedIn = true
      await refreshMember()
    } catch { memberError = error.localizedDescription }
  }

  func respond(to event: ChapterEvent, with response: RSVPResponse) async -> String? {
    guard let token, member != nil else { return "Connect and sign in before sending an RSVP." }
    guard !isBusy else { return "Your previous response is still being saved." }
    isBusy = true
    defer { isBusy = false }
    do {
      try await api.respond(token: token, eventID: event.id, response: response)
      guard self.token == token else { return nil }
      member?.rsvps[event.id] = response
      return nil
    } catch {
      if let error = error as? APIError, error.requiresSignIn { await refreshMember() }
      return error.localizedDescription
    }
  }

  func signOut() async -> String? {
    guard let token, !isBusy else { return nil }
    isBusy = true
    defer { isBusy = false }
    do {
      do { try await api.signOut(token: token) } catch let error as APIError
        where error.requiresSignIn
      { /* The server session has already ended. */  }
      invalidateVerification()
      try await sessions.remove()
      self.token = nil
      isSignedIn = false
      memberError = nil
      return nil
    } catch { return error.localizedDescription }
  }

  static func isValidInvitation(_ code: String) -> Bool {
    code.trimmingCharacters(in: .whitespacesAndNewlines)
      .range(of: "^wsi_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
  }
}
