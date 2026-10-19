import Foundation

struct ChapterFeed: Codable, Equatable, Sendable {
  let chapter: Chapter
  let news: [ChapterArticle]
  let events: [ChapterEvent]
  let pages: [ChapterPage]
  let updatedAt: Date
}

struct Chapter: Codable, Equatable, Sendable {
  let slug: String
  let name: String
  let displayName: String
  let theme: ChapterTheme
  let tagline: String
  let website: URL
  let features: ChapterFeatures
}

struct ChapterTheme: Codable, Equatable, Sendable {
  let accent: String
  let primary: String
  let background: String
}

struct ChapterFeatures: Codable, Equatable, Sendable {
  let news: Bool
  let events: Bool
  let membership: Bool
  let rsvp: Bool
  let guardian: Bool
  let intercom: Bool
}

struct ChapterArticle: Codable, Equatable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let excerpt: String
  let body: String
  let publishedAt: Date
  let url: URL
}

struct ChapterEvent: Codable, Equatable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let description: String
  let startsAt: String
  let location: String
  let url: URL
  let status: String

  var dateLabel: String {
    guard let date = APICoding.parseDate(startsAt) else { return "Time to be confirmed" }
    let offset = String(startsAt.suffix(6))
    let sign = offset.first == "-" ? -1 : 1
    let parts = offset.dropFirst().split(separator: ":").compactMap { Int($0) }
    let seconds = parts.count == 2 ? sign * (parts[0] * 3600 + parts[1] * 60) : 0
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_GB")
    formatter.timeZone = TimeZone(secondsFromGMT: seconds)
    formatter.dateFormat = "EEE d MMM yyyy '·' HH:mm"
    return formatter.string(from: date) + (seconds == 0 ? " GMT" : " UTC\(offset)")
  }
}

struct ChapterPage: Codable, Equatable, Hashable, Identifiable, Sendable {
  let slug: String
  let title: String
  let body: String
  let url: URL
  var id: String { slug }
}

enum RSVPResponse: String, Codable, CaseIterable, Sendable {
  case going, interested
  case notGoing = "not_going"
  var title: String {
    switch self {
    case .going: "Going"
    case .interested: "Interested"
    case .notGoing: "Not going"
    }
  }
}

struct MemberProfile: Codable, Equatable, Sendable {
  let id: String
  let displayName: String
  let membershipType: String
  let status: String
  let chapter: String
  let sessionExpiresAt: Date
  let verifiedAt: Date
  var rsvps: [String: RSVPResponse]
}

enum APICoding {
  static func parseDate(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let result = formatter.date(from: string) { return result }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
  }

  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { input in
      let container = try input.singleValueContainer()
      let string = try container.decode(String.self)
      guard let value = parseDate(string) else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Expected an ISO 8601 timestamp")
      }
      return value
    }
    return decoder
  }

  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

struct AppConfiguration: Equatable, Sendable {
  let baseURL: URL
  let chapterSlug: String
  var storageNamespace: String { "\(baseURL.absoluteString).\(chapterSlug)" }

  init(baseURL: URL, chapterSlug: String = "lr", allowsDebugLoopback: Bool = false) throws {
    let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
    guard baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
      baseURL.query == nil, baseURL.fragment == nil,
      ["", "/"].contains(baseURL.path),
      baseURL.scheme == "https" || (allowsDebugLoopback && isLoopback && baseURL.scheme == "http"),
      chapterSlug.range(of: "^[a-z0-9-]{2,50}$", options: .regularExpression) != nil
    else {
      throw APIError.configuration
    }
    self.baseURL = baseURL
    self.chapterSlug = chapterSlug
  }

  static func bundled() throws -> AppConfiguration {
    let raw =
      Bundle.main.object(forInfoDictionaryKey: "WidowsSonsBaseURL") as? String
      ?? "https://wsmba.the-grange.uk"
    guard let url = URL(string: raw) else { throw APIError.configuration }
    #if DEBUG
      return try AppConfiguration(baseURL: url, allowsDebugLoopback: true)
    #else
      return try AppConfiguration(baseURL: url)
    #endif
  }
}
