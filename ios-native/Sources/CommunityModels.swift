import Foundation

struct MemberAccess: Equatable, Sendable {
  let token: String
  let memberID: String
}

struct ChapterPerson: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let displayName: String
  let blocked: Bool
}

struct ConversationSummary: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let kind: String
  let title: String
  let eventID: String?
  let otherMemberID: String?
  let lastMessage: String
  let lastAt: Date?
  let unread: Int

  enum CodingKeys: String, CodingKey {
    case id, kind, title, lastMessage, lastAt, unread
    case eventID = "eventId"
    case otherMemberID = "otherMemberId"
  }
}

struct ChapterMessage: Decodable, Identifiable, Equatable, Sendable {
  let id: Int64
  let conversationID: String
  let senderID: String
  let senderName: String
  let clientID: String
  let body: String
  let sentAt: Date
  let deleted: Bool

  enum CodingKeys: String, CodingKey {
    case id, senderName, body, sentAt, deleted
    case conversationID = "conversationId"
    case senderID = "senderId"
    case clientID = "clientId"
  }
}

struct MessagesPage: Decodable, Sendable {
  let messages: [ChapterMessage]
  let hasOlder: Bool
}

struct LiveRideSession: Sendable, Equatable {
  let eventID: String
  let title: String
  let expiresAt: Date
}

struct RideSnapshot: Decodable, Sendable {
  let eventID: String
  let expiresAt: Date
  let riders: [LiveRider]
  let serverTime: Date
  enum CodingKeys: String, CodingKey {
    case expiresAt, riders, serverTime
    case eventID = "eventId"
  }
}

struct LiveRider: Decodable, Identifiable, Equatable, Sendable {
  let id: String
  let displayName: String
  let state: String
  let sharing: Bool
  let latitude: Double?
  let longitude: Double?
  let accuracy: Double?
  let capturedAt: Date?
  let receivedAt: Date?
  let checkedInAt: Date

  func status(at date: Date) -> String {
    if state == "home" { return "Home · sharing ended" }
    if state == "left" { return "Left ride safely" }
    guard sharing, latitude != nil, longitude != nil, let capturedAt else {
      return sharing ? "No recent position · check signal" : "Position not shared"
    }
    let age = max(0, Int(date.timeIntervalSince(capturedAt)))
    if age >= 120 { return "No recent position · check signal" }
    if age < 30 { return "Position \(age)s ago" }
    return "Last position \(age)s ago · check signal"
  }
}

struct LocationFix: Sendable, Equatable {
  let latitude: Double
  let longitude: Double
  let accuracy: Double
  let capturedAt: Date

  func isUsable(at date: Date) -> Bool {
    latitude.isFinite && longitude.isFinite && accuracy.isFinite
      && (-90...90).contains(latitude) && (-180...180).contains(longitude)
      && (0...1000).contains(accuracy)
      && (-30...120).contains(date.timeIntervalSince(capturedAt))
  }
}

struct VoiceGrant: Decodable, Sendable {
  let grantID: String
  let token: String
  let expiresAt: Date
  let roomName: String
  enum CodingKeys: String, CodingKey {
    case token, expiresAt, roomName
    case grantID = "grantId"
  }
}

enum CommunityInput {
  static func pathID(_ value: String) throws -> String {
    guard UUID(uuidString: value) != nil else { throw APIError.invalidResponse }
    return value
  }
  static func rideID(_ value: String) throws -> String {
    guard value.range(of: "^cms-[0-9]+$", options: .regularExpression) != nil else {
      throw APIError.invalidResponse
    }
    return value
  }
  static func message(_ value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.unicodeScalars.count <= 2000,
      !text.unicodeScalars.contains(where: { $0.value < 32 && $0 != "\n" && $0 != "\t" })
    else { return nil }
    return text
  }
}
