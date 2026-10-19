import Foundation

/// Intent requests recheck the same chapter/session permissions as the phone UI.
/// Only immutable request values cross into this actor; no message cache is made.
actor SiriMessageService {
  private let api: NativeChapterAPI
  private let sessions: any SessionStorage
  init(
    configuration: AppConfiguration, transport: any HTTPTransport = NativeHTTPTransport(),
    sessions: (any SessionStorage)? = nil
  ) {
    api = NativeChapterAPI(configuration: configuration, transport: transport)
    self.sessions = sessions ?? KeychainSessionStorage(namespace: configuration.storageNamespace)
  }

  private func access() async throws -> MemberAccess {
    guard let token = try await sessions.read() else {
      throw APIError.server(401, "Membership sign-in is required when safe.")
    }
    let profile = try await api.fetchMember(token: token)
    return MemberAccess(token: token, memberID: profile.id)
  }

  private func rooms(_ access: MemberAccess) async throws -> [ConversationSummary] {
    struct List: Decodable { let conversations: [ConversationSummary] }
    return try APICoding.decoder().decode(
      List.self, from: await api.request(path: "conversations", token: access.token)
    ).conversations
  }

  func people(matching value: String) async throws -> [ChapterPerson] {
    let access = try await access()
    struct List: Decodable { let members: [ChapterPerson] }
    let members = try APICoding.decoder().decode(
      List.self, from: await api.request(path: "members", token: access.token)
    ).members
    return members.filter {
      !$0.blocked
        && ($0.id == value || $0.displayName.localizedCaseInsensitiveCompare(value) == .orderedSame)
    }
  }

  func send(
    conversationID: String?, groupName: String?, recipientID: String?, content: String,
    clientID: UUID
  ) async throws -> ChapterMessage {
    guard let text = CommunityInput.message(content) else { throw APIError.invalidResponse }
    let access = try await access()
    let conversations = try await rooms(access)
    let roomID: String
    if let conversationID {
      _ = try CommunityInput.pathID(conversationID)
      guard conversations.contains(where: { $0.id == conversationID }) else {
        throw APIError.server(403, "Conversation unavailable.")
      }
      roomID = conversationID
    } else if let recipientID {
      _ = try CommunityInput.pathID(recipientID)
      struct ID: Decodable { let id: String }
      let data = try await api.request(
        path: "conversations/direct", method: "POST", token: access.token,
        body: JSONEncoder().encode(["member_id": recipientID]))
      roomID = try CommunityInput.pathID(APICoding.decoder().decode(ID.self, from: data).id)
    } else if let groupName {
      let matches = conversations.filter {
        $0.title.localizedCaseInsensitiveCompare(groupName) == .orderedSame
      }
      guard matches.count == 1, let room = matches.first else {
        throw APIError.server(409, "Choose one chapter conversation.")
      }
      roomID = room.id
    } else {
      throw APIError.server(422, "Choose a recipient or conversation.")
    }
    let body = try JSONEncoder().encode(["client_id": clientID.uuidString, "body": text])
    let data = try await api.request(
      path: "conversations/\(roomID)/messages", method: "POST", token: access.token, body: body)
    let message = try APICoding.decoder().decode(ChapterMessage.self, from: data)
    guard message.conversationID == roomID, message.senderID == access.memberID,
      message.clientID.lowercased() == clientID.uuidString.lowercased()
    else { throw APIError.invalidResponse }
    return message
  }

  func search(
    conversationIDs: [String], groupNames: [String], messageIDs: [String], unreadOnly: Bool,
    terms: [String], senderIDs: [String]
  ) async throws -> [(ChapterMessage, String)] {
    let access = try await access()
    let conversations = try await rooms(access)
    let wanted = Set(conversationIDs)
    let rooms = conversations.filter {
      (wanted.isEmpty || wanted.contains($0.id))
        && (groupNames.isEmpty || groupNames.contains($0.title))
        && (!unreadOnly || $0.unread > 0)
    }
    guard wanted.isSubset(of: Set(conversations.map(\.id))) else {
      throw APIError.server(403, "Conversation unavailable.")
    }
    var result: [(ChapterMessage, String)] = []
    for room in rooms.prefix(10) {
      _ = try CommunityInput.pathID(room.id)
      let data = try await api.request(
        path: "conversations/\(room.id)/messages", token: access.token)
      let page = try APICoding.decoder().decode(MessagesPage.self, from: data)
      let messages = unreadOnly ? Array(page.messages.suffix(room.unread)) : page.messages
      result += messages.filter {
        !$0.deleted && $0.senderID != access.memberID
          && (messageIDs.isEmpty || messageIDs.contains("\(room.id):\($0.id)"))
          && (senderIDs.isEmpty || senderIDs.contains($0.senderID))
          && terms.allSatisfy($0.body.localizedCaseInsensitiveContains)
      }.map { ($0, room.title) }
      if result.count >= 10 { break }
    }
    return Array(result.sorted { $0.0.sentAt < $1.0.sentAt }.prefix(10))
  }

  func markRead(_ ids: [String]) async throws {
    guard !ids.isEmpty, ids.count <= 50 else { throw APIError.invalidResponse }
    let access = try await access()
    let conversations = try await rooms(access)
    for identifier in ids {
      let pieces = identifier.split(separator: ":")
      guard pieces.count == 2, let messageID = Int64(pieces[1]), messageID > 0,
        conversations.contains(where: { $0.id == String(pieces[0]) })
      else { throw APIError.invalidResponse }
      let room = try CommunityInput.pathID(String(pieces[0]))
      _ = try await api.request(
        path: "conversations/\(room)/read", method: "PUT", token: access.token,
        body: JSONEncoder().encode(["message_id": messageID]))
    }
  }
}
