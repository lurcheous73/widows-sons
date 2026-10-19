import Foundation
import Testing

@testable import WidowsSons

@Suite("Native API and model boundaries")
struct APITests {
  @Test func productionUsesHTTPS() throws {
    #expect(throws: APIError.self) {
      try AppConfiguration(baseURL: URL(string: "http://example.com")!)
    }
    #expect(throws: APIError.self) {
      try AppConfiguration(baseURL: URL(string: "https://user:secret@example.com")!)
    }
    #expect(throws: APIError.self) {
      try AppConfiguration(baseURL: URL(string: "https://example.com/?token=secret")!)
    }
    #expect(throws: APIError.self) {
      try AppConfiguration(baseURL: URL(string: "http://localhost:19820")!)
    }
    _ = try AppConfiguration(
      baseURL: URL(string: "http://localhost:19820")!, allowsDebugLoopback: true)
    #expect(throws: APIError.self) {
      try AppConfiguration(baseURL: URL(string: "http://example.com")!, allowsDebugLoopback: true)
    }
  }

  @Test func datesSupportFractionalAndWholeSeconds() {
    #expect(APICoding.parseDate("2026-10-19T12:00:00Z") != nil)
    #expect(APICoding.parseDate("2026-10-19T12:00:00.123456+00:00") != nil)
    #expect(APICoding.parseDate("invalid") == nil)
    #expect(Fixtures.event.dateLabel.contains("10:00 UTC+01:00"))
    #expect(Fixtures.event.dateLabel.contains("2099"))
  }

  @Test func feedRoundTripsWithoutPrivateRecords() throws {
    let encoded = try APICoding.encoder().encode(Fixtures.feed())
    #expect(try APICoding.decoder().decode(ChapterFeed.self, from: encoded) == Fixtures.feed())
    let text = String(decoding: encoded, as: UTF8.self)
    #expect(!text.contains(Fixtures.token))
    #expect(!text.contains("Test Member"))
  }

  @Test func publicRequestsHaveNoBearerAndTenantMismatchIsRejected() async throws {
    let transport = StubTransport([
      HTTPPayload(data: try APICoding.encoder().encode(Fixtures.feed(slug: "other")), status: 200)
    ])
    let api = NativeChapterAPI(
      configuration: try AppConfiguration(baseURL: URL(string: "https://wsmba.the-grange.uk")!),
      transport: transport)
    do {
      _ = try await api.fetchFeed()
      Issue.record("Wrong tenant feed was accepted")
    } catch { #expect(error as? APIError == .invalidResponse) }
    let requests = await transport.requests
    #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(requests.first?.url?.path == "/api/v1/mobile/lr/feed")
  }

  @Test func invitationsAndTokensStayOutOfURLs() async throws {
    let transport = StubTransport([
      HTTPPayload(data: try JSONEncoder().encode(["token": Fixtures.token]), status: 200),
      HTTPPayload(data: Data(), status: 204),
    ])
    let api = NativeChapterAPI(
      configuration: try AppConfiguration(baseURL: URL(string: "https://wsmba.the-grange.uk")!),
      transport: transport)
    let code = "wsi_" + String(repeating: "b", count: 43)
    let token = try await api.activate(code: code)
    try await api.signOut(token: token)
    let requests = await transport.requests
    #expect(
      requests.allSatisfy {
        $0.url?.query == nil && !($0.url?.absoluteString.contains(code) ?? true)
      })
    #expect(requests[0].httpMethod == "POST")
    #expect(
      try JSONDecoder().decode([String: String].self, from: requests[0].httpBody!) == ["code": code]
    )
    #expect(requests[1].httpMethod == "DELETE")
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.token)")
  }

  @Test func serverErrorsAndBadRSVPIdentifiersArePreserved() async throws {
    let transport = StubTransport([
      HTTPPayload(data: Data(#"{"detail":"Invite expired"}"#.utf8), status: 401)
    ])
    let api = NativeChapterAPI(
      configuration: try AppConfiguration(baseURL: URL(string: "https://wsmba.the-grange.uk")!),
      transport: transport)
    do {
      _ = try await api.activate(code: "unused")
      Issue.record("Expected invalid invitation")
    } catch { #expect(error as? APIError == .server(401, "Invite expired")) }
    do {
      try await api.respond(token: "test", eventID: "../me", response: .going)
      Issue.record("Expected invalid event identifier")
    } catch { #expect(error as? APIError == .invalidResponse) }
    #expect(await transport.requests.count == 1)
  }

  @Test func websiteLinksAreRestricted() {
    #expect(ApprovedWebsite.link(URL(string: "https://wsmba.the-grange.uk/contact/")) != nil)
    #expect(ApprovedWebsite.link(URL(string: "http://wsmba.the-grange.uk/contact/")) == nil)
    #expect(ApprovedWebsite.link(URL(string: "https://other.example/")) == nil)
    #expect(ApprovedWebsite.link(URL(string: "https://secret@wsmba.the-grange.uk/")) == nil)
  }
}

@Suite("Native membership state") @MainActor
struct StoreTests {
  @Test func cachedReadingSurvivesOfflineButMemberCardDoesNot() async throws {
    let session = MemorySession(token: Fixtures.token)
    let store = ChapterStore(
      api: StubAPI(feedError: .unavailable, memberError: .unavailable), sessions: session,
      cache: MemoryFeed(Fixtures.feed()))
    await store.loadOrRefresh()
    #expect(store.feed?.news.count == 1)
    #expect(store.isReadingSavedContent)
    #expect(store.isSignedIn)
    #expect(store.member == nil)
    #expect(await store.respond(to: Fixtures.event, with: .going) != nil)
  }

  @Test func expiredSessionClearsKeychain() async throws {
    let session = MemorySession(token: Fixtures.token)
    let store = ChapterStore(
      api: StubAPI(memberError: .server(401, "Sign-in ended")), sessions: session,
      cache: MemoryFeed())
    await store.loadOrRefresh()
    #expect(!store.isSignedIn)
    #expect(store.member == nil)
    #expect(try await session.read() == nil)
  }

  @Test func activationUsesSeparateSecretAndPublicStores() async throws {
    let session = MemorySession()
    let cache = MemoryFeed()
    let store = ChapterStore(api: StubAPI(), sessions: session, cache: cache)
    await store.loadOrRefresh()
    await store.activate(code: "wsi_" + String(repeating: "x", count: 43))
    #expect(store.isSignedIn)
    #expect(store.member?.displayName == "Test Member")
    #expect(try await session.read() == Fixtures.token)
    let encoded = try APICoding.encoder().encode(try #require(await cache.read()))
    #expect(!String(decoding: encoded, as: UTF8.self).contains("Test Member"))
    #expect(!String(decoding: encoded, as: UTF8.self).contains(Fixtures.token))
  }

  @Test func secureWriteFailureRevokesTheIssuedSession() async {
    let api = StubAPI()
    let store = ChapterStore(
      api: api, sessions: MemorySession(failsWrite: true), cache: MemoryFeed())
    await store.activate(code: "invite")
    #expect(!store.isSignedIn)
    #expect(store.member == nil)
    #expect(await api.signOutCalls == 1)
    #expect(store.memberError == APIError.secureStorage.localizedDescription)
  }

  @Test func failedRSVPDoesNotChangeTheSavedResponse() async {
    let store = ChapterStore(
      api: StubAPI(
        profile: Fixtures.member(response: .interested), rsvpError: .server(404, "Event removed")),
      sessions: MemorySession(token: Fixtures.token), cache: MemoryFeed())
    await store.loadOrRefresh()
    #expect(await store.respond(to: Fixtures.event, with: .going) == "Event removed")
    #expect(store.member?.rsvps["cms-42"] == .interested)
  }

  @Test func confirmedRSVPIsUpdatedAfterTheServerResponds() async {
    let api = StubAPI()
    let store = ChapterStore(
      api: api, sessions: MemorySession(token: Fixtures.token), cache: MemoryFeed())
    await store.loadOrRefresh()
    #expect(await store.respond(to: Fixtures.event, with: .going) == nil)
    #expect(store.member?.rsvps["cms-42"] == .going)
    #expect(await api.lastResponse == .going)
  }

  @Test func signOutAlsoClearsAnAlreadyExpiredSession() async throws {
    let session = MemorySession(token: Fixtures.token)
    let store = ChapterStore(
      api: StubAPI(signOutError: .server(401, "Already ended")), sessions: session,
      cache: MemoryFeed())
    await store.loadOrRefresh()
    #expect(await store.signOut() == nil)
    #expect(!store.isSignedIn && store.member == nil)
    #expect(try await session.read() == nil)
  }

  @Test func lateProfileCannotRestoreASignedOutCard() async throws {
    let api = StubAPI()
    let store = ChapterStore(
      api: api, sessions: MemorySession(token: Fixtures.token), cache: MemoryFeed())
    await store.loadOrRefresh()
    await api.delayNextMember()
    let refresh = Task { await store.refreshMember() }
    for _ in 0..<500 {
      if await api.hasPendingMember() { break }
      await Task.yield()
    }
    #expect(await api.hasPendingMember())
    #expect(await store.signOut() == nil)
    await api.completeMember()
    await refresh.value
    #expect(store.member == nil && !store.isSignedIn)
  }

  @Test func backgroundingInvalidatesVerification() async {
    let store = ChapterStore(
      api: StubAPI(), sessions: MemorySession(token: Fixtures.token), cache: MemoryFeed())
    await store.loadOrRefresh()
    #expect(store.member != nil)
    store.invalidateVerification()
    #expect(store.member == nil)
    #expect(store.isSignedIn)
  }

  @Test func invitationValidationMatchesTheServerFormat() {
    #expect(ChapterStore.isValidInvitation("wsi_" + String(repeating: "x", count: 43)))
    #expect(!ChapterStore.isValidInvitation("incomplete"))
    #expect(!ChapterStore.isValidInvitation("wss_" + String(repeating: "x", count: 43)))
  }
}

@Suite("Native device storage")
struct StorageTests {
  @Test func appBundlesTheOpenSourceLicence() throws {
    let file = try #require(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"))
    let notice = try String(contentsOf: file, encoding: .utf8)
    #expect(notice.contains("Copyright (c) 2014 kishikawa katsumi"))
    #expect(notice.contains("KeychainAccess 4.2.2"))
    #expect(notice.contains("Permission is hereby granted"))
  }

  @Test func publicCacheUsesAnIsolatedFileAndRoundTrips() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = NativeFeedCache(namespace: "test-chapter", directory: directory)
    #expect(try await cache.read() == nil)
    try await cache.write(Fixtures.feed())
    #expect(try await cache.read() == Fixtures.feed())
    let otherChapter = NativeFeedCache(namespace: "another-chapter", directory: directory)
    #expect(try await otherChapter.read() == nil)
  }

  @Test func openSourceKeychainStoreActuallyPersistsAndRemoves() async throws {
    let namespace = "unit-test." + UUID().uuidString
    let first = KeychainSessionStorage(namespace: namespace)
    let second = KeychainSessionStorage(namespace: namespace)
    try await first.write("disposable-test-secret")
    do {
      #expect(try await second.read() == "disposable-test-secret")
      try await second.remove()
      #expect(try await first.read() == nil)
    } catch {
      try? await first.remove()
      throw error
    }
  }
}
