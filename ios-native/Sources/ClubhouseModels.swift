import Foundation

struct ClubSection: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let description: String
  let joinPolicy: String
  let state: String
  let revision: Int
  let membership: String
  let role: String
  let canRead: Bool
  let canPost: Bool
  let canModerate: Bool
  let canConfigure: Bool

  var accessLabel: String {
    switch joinPolicy {
    case "open": "Open to chapter members"
    case "approval": "Join by approval"
    default: "Invitation only"
    }
  }
  var membershipLabel: String {
    switch membership {
    case "active": role == "moderator" ? "Section moderator" : "Joined"
    case "invited": "Invitation waiting"
    case "requested": "Approval requested"
    case "removed": "Ask a moderator for an invitation"
    default: "Not joined"
    }
  }
}

struct ClubDirectory: Decodable, Sendable {
  let canCreate: Bool
  let sections: [ClubSection]
}

struct ClubPost: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let sectionID: String
  let authorID: String
  let clientID: UUID
  let kind: String
  let title: String
  let body: String
  let author: String
  let createdAt: Date
  let closesAt: Date?
  let closedAt: Date?
  let pinned: Bool
  let removed: Bool
  let commentCount: Int
  let myVote: String?
  let options: [ClubPollOption]
  let pollOpen: Bool

  enum CodingKeys: String, CodingKey {
    case id, kind, title, body, author, createdAt, closesAt, closedAt, pinned, removed
    case commentCount, myVote, options, pollOpen
    case sectionID = "sectionId"
    case authorID = "authorId"
    case clientID = "clientId"
  }
  var kindLabel: String {
    switch kind {
    case "poll": "Chapter poll"
    case "announcement": "Announcement"
    default: "Discussion"
    }
  }
}

struct ClubPollOption: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let votes: Int
}

struct ClubPostPage: Decodable, Sendable {
  let posts: [ClubPost]
  let hasOlder: Bool
}

struct ClubComment: Decodable, Identifiable, Sendable {
  let id: Int
  let authorID: String
  let clientID: UUID
  let author: String
  let body: String
  let createdAt: Date
  let removed: Bool
  enum CodingKeys: String, CodingKey {
    case id, author, body, createdAt, removed
    case authorID = "authorId"
    case clientID = "clientId"
  }
}

struct ClubCommentPage: Decodable, Sendable {
  let comments: [ClubComment]
  let hasOlder: Bool
}

struct ClubMember: Decodable, Identifiable, Sendable {
  let id: String
  let displayName: String
  let state: String
  let role: String
}

struct ClubReport: Decodable, Identifiable, Sendable {
  let id: String
  let postID: String
  let commentID: Int?
  let reason: String
  let createdAt: Date
  enum CodingKeys: String, CodingKey {
    case id, reason, createdAt
    case postID = "postId"
    case commentID = "commentId"
  }
}

struct ClubActivity: Decodable, Identifiable, Sendable {
  let id: Int
  let actorID: String?
  let targetID: String?
  let action: String
  let note: String
  let createdAt: Date
  enum CodingKeys: String, CodingKey {
    case id, action, note, createdAt
    case actorID = "actorId"
    case targetID = "targetId"
  }
}

struct ClubModeration: Decodable, Sendable {
  let reports: [ClubReport]
  let activity: [ClubActivity]
}

struct ClubPostDraft: Encodable, Equatable, Sendable {
  var clientID = UUID()
  var kind = "discussion"
  var title = ""
  var body = ""
  var options: [String] = []
  var closesAt: Date?

  var isValid: Bool {
    guard ClubInput.text(title, limit: 150) != nil,
      ClubInput.text(body, limit: 6000, allowEmpty: true) != nil
    else { return false }
    guard kind == "poll" else { return ["discussion", "announcement"].contains(kind) }
    let cleaned = options.compactMap { ClubInput.text($0, limit: 150) }
    return (2...8).contains(cleaned.count) && cleaned.count == options.count
      && Set(cleaned.map { $0.lowercased() }).count == cleaned.count
      && closesAt.map { $0 > .now && $0 < .now.addingTimeInterval(90 * 86400) } == true
  }
}

enum ClubInput {
  static func text(_ value: String, limit: Int, allowEmpty: Bool = false) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard allowEmpty || !trimmed.isEmpty, trimmed.unicodeScalars.count <= limit,
      !trimmed.unicodeScalars.contains(where: {
        ($0.value < 32 && $0 != "\n" && $0 != "\t") || $0.value == 127
      })
    else { return nil }
    return trimmed
  }
}
