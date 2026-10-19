import Foundation
import Observation

@MainActor @Observable
final class ChatThread {
  let conversation: ConversationSummary
  private(set) var messages: [ChapterMessage] = []
  private(set) var isSending = false
  private(set) var hasOlder = false
  private(set) var isLoadingOlder = false
  private(set) var error: String?
  private(set) var updatedAt: Date?
  var draft: String

  @ObservationIgnored private let community: CommunityStore
  @ObservationIgnored private var pending: (id: UUID, body: String)?
  @ObservationIgnored private var generation = 0

  init(conversation: ConversationSummary, community: CommunityStore) {
    self.conversation = conversation
    self.community = community
    draft = community.draft(for: conversation.id)
  }

  func clear() {
    generation += 1
    messages = []
    draft = ""
    pending = nil
    updatedAt = nil
  }

  func run() async {
    while !Task.isCancelled, community.isVerified {
      await refresh()
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
    }
  }

  func refresh() async {
    let version = generation
    do {
      let id = try CommunityInput.pathID(conversation.id)
      let page = try await community.decoded(
        MessagesPage.self, path: "conversations/\(id)/messages")
      guard !Task.isCancelled, version == generation, community.isVerified else { return }
      if messages.isEmpty { hasOlder = page.hasOlder }
      merge(page.messages)
      updatedAt = .now
      error = nil
      if let last = messages.last {
        _ = try await community.request(
          path: "conversations/\(id)/read", method: "PUT",
          body: JSONEncoder().encode(["message_id": last.id]))
      }
    } catch is CancellationError { return } catch { self.error = error.localizedDescription }
  }

  func older() async {
    guard hasOlder, !isLoadingOlder, let first = messages.first else { return }
    isLoadingOlder = true
    defer { isLoadingOlder = false }
    let version = generation
    do {
      let id = try CommunityInput.pathID(conversation.id)
      let page = try await community.decoded(
        MessagesPage.self, path: "conversations/\(id)/messages",
        query: [URLQueryItem(name: "before", value: String(first.id))])
      guard version == generation, community.isVerified else { return }
      merge(page.messages)
      hasOlder = page.hasOlder
      error = nil
    } catch { self.error = error.localizedDescription }
  }

  func send() async {
    guard !isSending, let text = CommunityInput.message(draft) else {
      error = "Write a message of up to 2,000 characters."
      return
    }
    isSending = true
    defer { isSending = false }
    let version = generation
    if pending?.body != text { pending = (UUID(), text) }
    guard let pending else { return }
    do {
      let id = try CommunityInput.pathID(conversation.id)
      struct Body: Encodable {
        let clientID: UUID
        let body: String
      }
      let body = try APICoding.encoder().encode(Body(clientID: pending.id, body: text))
      let saved = try await community.decoded(
        ChapterMessage.self, path: "conversations/\(id)/messages", method: "POST", body: body)
      guard version == generation, community.isVerified else { return }
      guard saved.conversationID == id, saved.senderID == community.memberID,
        UUID(uuidString: saved.clientID) == pending.id
      else { throw APIError.invalidResponse }
      merge([saved])
      if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
      self.pending = nil
      community.saveDraft(draft, for: conversation.id)
      error = nil
      await community.refreshConversations()
    } catch is CancellationError { return } catch {
      self.error = "Message not confirmed. Tap Send to retry. \(error.localizedDescription)"
    }
  }

  func remove(_ message: ChapterMessage) async {
    do {
      let id = try CommunityInput.pathID(conversation.id)
      _ = try await community.request(
        path: "conversations/\(id)/messages/\(message.id)", method: "DELETE")
      messages.removeAll { $0.id == message.id }
      error = nil
    } catch { self.error = error.localizedDescription }
  }

  func report(_ message: ChapterMessage, reason: String) async {
    do {
      let id = try CommunityInput.pathID(conversation.id)
      _ = try await community.request(
        path: "conversations/\(id)/messages/\(message.id)/report", method: "POST",
        body: JSONEncoder().encode(["reason": String(reason.prefix(500))]))
      error = "Report saved for chapter review. Contact the chapter directly for an urgent concern."
    } catch { self.error = error.localizedDescription }
  }

  private func merge(_ incoming: [ChapterMessage]) {
    var byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    for message in incoming { byID[message.id] = message }
    messages = byID.values.sorted { $0.id < $1.id }
  }
}
