import Foundation

@testable import WidowsSons

enum Fixtures {
  static let instant = Date(timeIntervalSince1970: 1_792_416_000)
  static let event = ChapterEvent(
    id: "cms-42", title: "Test chapter ride", description: "Test route details.",
    startsAt: "2099-07-01T10:00:00+01:00", location: "Test meeting point",
    url: URL(string: "https://wsmba.the-grange.uk/event/")!, status: "published")
  static func feed(slug: String = "lr") -> ChapterFeed {
    ChapterFeed(
      chapter: Chapter(
        slug: slug, name: "Leicestershire & Rutland Widows Sons", displayName: "Widows Sons L&R",
        theme: ChapterTheme(accent: "#c49a59", primary: "#20252e", background: "#10141b"),
        tagline: "Motorcycling · Friendship · Charity",
        website: URL(string: "https://wsmba.the-grange.uk")!,
        features: ChapterFeatures(
          news: true, events: true, membership: true, rsvp: true, guardian: false, intercom: false)),
      news: [
        ChapterArticle(
          id: "11", title: "A new home for chapter news.", excerpt: "Chapter news.",
          body: "Published chapter information.", publishedAt: instant,
          url: URL(string: "https://wsmba.the-grange.uk/news/")!)
      ],
      events: [event], pages: [], updatedAt: instant)
  }
  static func member(response: RSVPResponse? = nil) -> MemberProfile {
    MemberProfile(
      id: "7da8e118-dd70-439b-bc0d-34ef4645de77", displayName: "Test Member",
      membershipType: "member", status: "active", chapter: "Widows Sons L&R",
      sessionExpiresAt: instant.addingTimeInterval(86400), verifiedAt: instant,
      rsvps: response.map { ["cms-42": $0] } ?? [:])
  }
  static let token = "wss_" + String(repeating: "a", count: 43)
}

actor MemorySession: SessionStorage {
  private(set) var token: String?
  let failsWrite: Bool
  init(token: String? = nil, failsWrite: Bool = false) {
    self.token = token
    self.failsWrite = failsWrite
  }
  func read() throws -> String? { token }
  func write(_ token: String) throws {
    if failsWrite { throw APIError.secureStorage }
    self.token = token
  }
  func remove() throws { token = nil }
}

actor MemoryFeed: FeedStorage {
  private(set) var feed: ChapterFeed?
  init(_ feed: ChapterFeed? = nil) { self.feed = feed }
  func read() throws -> ChapterFeed? { feed }
  func write(_ feed: ChapterFeed) throws { self.feed = feed }
}

actor StubAPI: ChapterAPI {
  var feedError: APIError?
  var memberError: APIError?
  var rsvpError: APIError?
  var signOutError: APIError?
  private(set) var signOutCalls = 0
  private(set) var lastResponse: RSVPResponse?
  let profile: MemberProfile
  private var delayedMember: CheckedContinuation<MemberProfile, Error>?
  private var shouldDelay = false
  init(
    profile: MemberProfile = Fixtures.member(), feedError: APIError? = nil,
    memberError: APIError? = nil, rsvpError: APIError? = nil, signOutError: APIError? = nil
  ) {
    self.profile = profile
    self.feedError = feedError
    self.memberError = memberError
    self.rsvpError = rsvpError
    self.signOutError = signOutError
  }
  func fetchFeed() throws -> ChapterFeed {
    if let feedError { throw feedError }
    return Fixtures.feed()
  }
  func activate(code: String) throws -> String { Fixtures.token }
  func fetchMember(token: String) async throws -> MemberProfile {
    if let memberError { throw memberError }
    if shouldDelay { return try await withCheckedThrowingContinuation { delayedMember = $0 } }
    return profile
  }
  func respond(token: String, eventID: String, response: RSVPResponse) throws {
    if let rsvpError { throw rsvpError }
    lastResponse = response
  }
  func signOut(token: String) throws {
    signOutCalls += 1
    if let signOutError { throw signOutError }
  }
  func delayNextMember() { shouldDelay = true }
  func hasPendingMember() -> Bool { delayedMember != nil }
  func completeMember() {
    delayedMember?.resume(returning: profile)
    delayedMember = nil
    shouldDelay = false
  }
}

actor StubTransport: HTTPTransport {
  private var payloads: [HTTPPayload]
  private(set) var requests: [URLRequest] = []
  init(_ payloads: [HTTPPayload]) { self.payloads = payloads }
  func send(_ request: URLRequest) throws -> HTTPPayload {
    requests.append(request)
    guard !payloads.isEmpty else { throw APIError.unavailable }
    return payloads.removeFirst()
  }
}
