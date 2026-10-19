import Foundation
import Observation

@MainActor @Observable
final class ClubhouseDirectoryStore {
  private(set) var sections: [ClubSection] = []
  private(set) var canCreate = false
  private(set) var error: String?
  @ObservationIgnored let community: CommunityStore
  @ObservationIgnored private var generation = 0
  init(community: CommunityStore) { self.community = community }
  func clear() {
    generation += 1
    sections = []
    canCreate = false
    error = nil
  }
  func refresh() async {
    let version = generation
    guard community.isVerified else {
      clear()
      return
    }
    do {
      let result = try await community.decoded(ClubDirectory.self, path: "sections")
      guard version == generation, community.isVerified, !Task.isCancelled else { return }
      sections = result.sections
      canCreate = result.canCreate
      error = nil
    } catch is CancellationError { return } catch {
      clear()
      self.error = error.localizedDescription
    }
  }
}

@MainActor @Observable
final class ClubSectionStore {
  let id: String
  private(set) var section: ClubSection?
  private(set) var posts: [ClubPost] = []
  private(set) var hasOlder = false
  private(set) var members: [ClubMember] = []
  private(set) var moderation: ClubModeration?
  private(set) var busy = false
  private(set) var error: String?
  private(set) var notice: String?
  @ObservationIgnored let community: CommunityStore
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var pendingPost: ClubPostDraft?

  init(id: String, community: CommunityStore) {
    self.id = id
    self.community = community
  }
  var path: String { "sections/\(id)" }

  func clear() {
    generation += 1
    section = nil
    posts = []
    hasOlder = false
    members = []
    moderation = nil
    pendingPost = nil
    error = nil
    notice = nil
  }
  func showError(_ message: String) { error = message }

  func refresh() async {
    let version = generation
    guard community.isVerified else {
      clear()
      return
    }
    do {
      _ = try CommunityInput.pathID(id)
      let result = try await community.decoded(ClubSection.self, path: path)
      guard version == generation, community.isVerified, !Task.isCancelled else { return }
      guard result.id == id else { throw APIError.invalidResponse }
      section = result
      members = []
      moderation = nil
      if result.canRead {
        let page = try await community.decoded(ClubPostPage.self, path: "\(path)/posts")
        guard version == generation, community.isVerified, !Task.isCancelled else { return }
        guard page.posts.allSatisfy({ $0.sectionID == id }) else { throw APIError.invalidResponse }
        posts = page.posts
        hasOlder = page.hasOlder
      } else {
        posts = []
        hasOlder = false
      }
      error = nil
    } catch is CancellationError { return } catch {
      clear()
      self.error = error.localizedDescription
    }
  }

  func older() async {
    guard !busy, hasOlder, let last = posts.last else { return }
    busy = true
    defer { busy = false }
    let version = generation
    do {
      let page = try await community.decoded(
        ClubPostPage.self, path: "\(path)/posts",
        query: [
          URLQueryItem(name: "before_id", value: last.id)
        ])
      guard version == generation, community.isVerified else { return }
      guard page.posts.allSatisfy({ $0.sectionID == id }) else { throw APIError.invalidResponse }
      let known = Set(posts.map(\.id))
      posts += page.posts.filter { !known.contains($0.id) }
      hasOlder = page.hasOlder
    } catch { failedRead(error) }
  }

  @discardableResult
  func mutate(
    _ suffix: String = "", method: String = "POST", body: Data? = nil,
    message: String = "Saved with the section."
  ) async -> Bool {
    guard !busy else { return false }
    busy = true
    defer { busy = false }
    let version = generation
    do {
      _ = try await community.request(path: path + suffix, method: method, body: body)
      guard version == generation, community.isVerified else { return false }
      await refresh()
      notice = message
      return true
    } catch is CancellationError { return false } catch {
      failedRead(error)
      return false
    }
  }

  func loadModeration() async {
    let version = generation
    do {
      struct Members: Decodable, Sendable { let members: [ClubMember] }
      let people = try await community.decoded(Members.self, path: "\(path)/members")
      let review = try await community.decoded(ClubModeration.self, path: "\(path)/moderation")
      guard version == generation, community.isVerified else { return }
      members = people.members
      moderation = review
      error = nil
    } catch { failedRead(error) }
  }

  func memberAction(_ target: String, action: String) async {
    guard (try? CommunityInput.pathID(target)) != nil else { return }
    if await mutate(
      "/members/\(target)", method: "PUT", body: try? JSONEncoder().encode(["action": action]))
    {
      await loadModeration()
    }
  }

  func publish(_ draft: ClubPostDraft) async -> Bool {
    guard draft.isValid, !busy else { return false }
    busy = true
    defer { busy = false }
    let version = generation
    var sending = draft
    if let previous = pendingPost {
      var comparable = previous
      comparable.clientID = draft.clientID
      sending.clientID = comparable == draft ? previous.clientID : UUID()
    }
    pendingPost = sending
    do {
      let saved = try await community.decoded(
        ClubPost.self, path: "\(path)/posts", method: "POST",
        body: APICoding.encoder().encode(sending))
      guard version == generation, community.isVerified else { return false }
      guard saved.sectionID == id, saved.authorID == community.memberID,
        saved.clientID == sending.clientID
      else {
        throw APIError.invalidResponse
      }
      await refresh()
      pendingPost = nil
      notice = "Post confirmed by the section."
      return true
    } catch is CancellationError { return false } catch {
      failedRead(error)
      self.error = "Post not confirmed. Retry to check the same send. \(error.localizedDescription)"
      return false
    }
  }

  private func failedRead(_ error: Error) {
    if case APIError.server(let code, _) = error, [401, 403, 404].contains(code) { clear() }
    self.error = error.localizedDescription
  }
}

@MainActor @Observable
final class ClubPostStore {
  let sectionID: String
  let postID: String
  private(set) var section: ClubSection?
  private(set) var post: ClubPost?
  private(set) var comments: [ClubComment] = []
  private(set) var hasOlder = false
  private(set) var error: String?
  private(set) var notice: String?
  private(set) var busy = false
  var draft = ""
  @ObservationIgnored let community: CommunityStore
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var pendingComment: (UUID, String)?
  var path: String { "sections/\(sectionID)/posts/\(postID)" }
  init(sectionID: String, postID: String, community: CommunityStore) {
    self.sectionID = sectionID
    self.postID = postID
    self.community = community
  }
  func clear() {
    generation += 1
    section = nil
    post = nil
    comments = []
    draft = ""
    pendingComment = nil
    hasOlder = false
    notice = nil
  }
  func refresh() async {
    let version = generation
    guard community.isVerified else {
      clear()
      return
    }
    do {
      _ = try CommunityInput.pathID(sectionID)
      _ = try CommunityInput.pathID(postID)
      let access = try await community.decoded(ClubSection.self, path: "sections/\(sectionID)")
      guard access.id == sectionID, access.canRead else {
        throw APIError.server(403, "Section access has ended or is paused.")
      }
      let item = try await community.decoded(ClubPost.self, path: path)
      let page = try await community.decoded(ClubCommentPage.self, path: "\(path)/comments")
      guard version == generation, community.isVerified, !Task.isCancelled else { return }
      guard item.id == postID, item.sectionID == sectionID else { throw APIError.invalidResponse }
      section = access
      post = item
      comments = page.comments
      hasOlder = page.hasOlder
      error = nil
    } catch is CancellationError { return } catch {
      clear()
      self.error = error.localizedDescription
    }
  }
  func older() async {
    guard !busy, hasOlder, let first = comments.first else { return }
    busy = true
    defer { busy = false }
    let version = generation
    do {
      let page = try await community.decoded(
        ClubCommentPage.self, path: "\(path)/comments",
        query: [URLQueryItem(name: "before", value: String(first.id))])
      guard version == generation, community.isVerified else { return }
      let known = Set(comments.map(\.id))
      comments = page.comments.filter { !known.contains($0.id) } + comments
      hasOlder = page.hasOlder
    } catch { failedRead(error) }
  }
  @discardableResult
  func mutate(
    _ suffix: String, method: String = "POST", body: Data? = nil,
    message: String = "Saved with the section."
  ) async -> Bool {
    guard !busy else { return false }
    busy = true
    defer { busy = false }
    let version = generation
    do {
      _ = try await community.request(path: path + suffix, method: method, body: body)
      guard version == generation, community.isVerified else { return false }
      await refresh()
      notice = message
      return true
    } catch is CancellationError { return false } catch {
      failedRead(error)
      return false
    }
  }
  func comment() async {
    guard !busy, let text = ClubInput.text(draft, limit: 2000) else { return }
    if pendingComment?.1 != text { pendingComment = (UUID(), text) }
    guard let pendingComment else { return }
    struct Body: Encodable {
      let clientID: UUID
      let body: String
    }
    struct Receipt: Decodable, Sendable {
      let id: Int
      let postID: String
      let authorID: String
      let clientID: UUID
      enum CodingKeys: String, CodingKey {
        case id
        case postID = "postId"
        case authorID = "authorId"
        case clientID = "clientId"
      }
    }
    busy = true
    defer { busy = false }
    let version = generation
    do {
      let receipt = try await community.decoded(
        Receipt.self, path: "\(path)/comments", method: "POST",
        body: APICoding.encoder().encode(Body(clientID: pendingComment.0, body: text)))
      guard version == generation, community.isVerified else { return }
      guard receipt.id > 0, receipt.postID == postID, receipt.authorID == community.memberID,
        receipt.clientID == pendingComment.0
      else {
        throw APIError.invalidResponse
      }
      if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
      self.pendingComment = nil
      await refresh()
      notice = "Comment confirmed by the section."
    } catch is CancellationError { return } catch {
      failedRead(error)
      self.error =
        "Comment not confirmed. Retry to check the same send. \(error.localizedDescription)"
    }
  }
  private func failedRead(_ error: Error) {
    if case APIError.server(let code, _) = error, [401, 403, 404].contains(code) { clear() }
    self.error = error.localizedDescription
  }
}
