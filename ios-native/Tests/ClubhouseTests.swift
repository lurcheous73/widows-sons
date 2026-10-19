import Foundation
import Testing

@testable import WidowsSons

@Suite("Community section privacy and delivery")
@MainActor
struct ClubhouseTests {
  private let sid = "471b292a-e0f9-43ec-a77c-875dc4d818a4"
  private let pid = "297923a8-8426-4467-b5eb-20ba91fe5689"
  private func service(_ transport: any HTTPTransport) async throws -> CommunityStore {
    let native = NativeChapterAPI(
      configuration: try AppConfiguration(baseURL: URL(string: "https://wsmba.the-grange.uk")!),
      transport: transport)
    let service = CommunityStore(api: native)
    await service.authenticate(member: Fixtures.member(), token: Fixtures.token)
    return service
  }
  private func payload(_ value: String, status: Int = 200) -> HTTPPayload {
    HTTPPayload(data: Data(value.utf8), status: status)
  }
  private var section: String {
    """
    {"id":"\(sid)","title":"QA Social","description":"Optional chapter group","join_policy":"approval","state":"active","revision":0,"membership":"active","role":"member","can_read":true,"can_post":true,"can_moderate":false,"can_configure":false}
    """
  }
  private func post(sectionID: String? = nil) -> String {
    """
    {"id":"\(pid)","section_id":"\(sectionID ?? sid)","author_id":"\(Fixtures.member().id)","client_id":"d030766c-013e-4d48-b7dd-9c409da1beab","kind":"discussion","title":"Sunday coffee","body":"A private chapter post","author":"Test member","created_at":"2026-10-19T18:00:00Z","closes_at":null,"closed_at":null,"pinned":false,"removed":false,"comment_count":0,"my_vote":null,"options":[],"poll_open":false}
    """
  }

  @Test func draftValidationRejectsEmptyControlsDuplicateAndUnboundedPolls() {
    #expect(ClubInput.text("  ", limit: 10) == nil)
    #expect(ClubInput.text("bad\0text", limit: 100) == nil)
    #expect(ClubInput.text("bad\u{7f}", limit: 100) == nil)
    var draft = ClubPostDraft()
    draft.title = "Coffee stop?"
    draft.kind = "poll"
    draft.closesAt = .now.addingTimeInterval(86400)
    draft.options = ["Coffee", "Lunch"]
    #expect(draft.isValid)
    draft.options = ["Coffee", "COFFEE"]
    #expect(!draft.isValid)
    draft.options = ["Coffee", "Lunch"]
    draft.closesAt = .now.addingTimeInterval(-1)
    #expect(!draft.isValid)
  }

  @Test func ordinarySectionsDoNotInferMembershipOrModeratorRights() throws {
    let decoded = try APICoding.decoder().decode(ClubSection.self, from: Data(section.utf8))
    #expect(decoded.membership == "active" && !decoded.canModerate && !decoded.canConfigure)
    #expect(decoded.accessLabel == "Join by approval")
    let invitation = section.replacingOccurrences(
      of: "\"membership\":\"active\"", with: "\"membership\":\"invited\""
    ).replacingOccurrences(of: "\"can_read\":true", with: "\"can_read\":false")
    #expect(
      try APICoding.decoder().decode(ClubSection.self, from: Data(invitation.utf8)).membershipLabel
        == "Invitation waiting")
  }

  @Test func directoryAndBoardForgetPrivateContentWhenSuspended() async throws {
    let transport = StubTransport([
      payload("{\"can_create\":false,\"sections\":[\(section)]}"), payload(section),
      payload("{\"posts\":[\(post())],\"has_older\":false}"),
    ])
    let community = try await service(transport)
    let directory = ClubhouseDirectoryStore(community: community)
    let board = ClubSectionStore(id: sid, community: community)
    await directory.refresh()
    await board.refresh()
    #expect(directory.sections.count == 1 && board.posts.count == 1)
    community.suspendPrivateViews()
    await directory.refresh()
    await board.refresh()
    #expect(
      directory.sections.isEmpty && !directory.canCreate && board.section == nil
        && board.posts.isEmpty)
  }

  @Test func foreignSectionPostIsRejectedWithoutKeepingItVisible() async throws {
    let transport = StubTransport([
      payload(section),
      payload("{\"posts\":[\(post(sectionID: UUID().uuidString))],\"has_older\":false}"),
    ])
    let board = ClubSectionStore(id: sid, community: try await service(transport))
    await board.refresh()
    #expect(board.posts.isEmpty && board.section == nil && board.error != nil)
  }

  @Test func removedMembershipClearsPostAndUnsentPrivateDraft() async throws {
    let transport = StubTransport([
      payload(section), payload(post()), payload("{\"comments\":[],\"has_older\":false}"),
      payload("{\"detail\":\"Access removed\"}", status: 403),
    ])
    let thread = ClubPostStore(sectionID: sid, postID: pid, community: try await service(transport))
    await thread.refresh()
    #expect(thread.post?.id == pid)
    thread.draft = "Private unsent comment"
    await thread.refresh()
    #expect(thread.post == nil && thread.comments.isEmpty && thread.draft.isEmpty)
  }

  @Test func revokedSessionInvalidatesCommunityAndSectionLists() async throws {
    let transport = StubTransport([payload("{\"detail\":\"Session ended\"}", status: 401)])
    let community = try await service(transport)
    let directory = ClubhouseDirectoryStore(community: community)
    await directory.refresh()
    #expect(
      !community.isVerified && directory.sections.isEmpty && directory.error == "Session ended")
  }

  @Test func postRetryKeepsClientIdentityAndRejectsForeignReceipt() async throws {
    let transport = ClubhouseEchoTransport(sectionID: sid, postID: pid, section: section)
    let community = try await service(transport)
    let board = ClubSectionStore(id: sid, community: community)
    var draft = ClubPostDraft()
    draft.title = "Sunday coffee"
    draft.body = "Meet after the ride"
    #expect(await !board.publish(draft))
    #expect(await board.publish(draft))
    let sends = await transport.sentBodies
    #expect(sends.count == 2 && sends[0]["client_id"] == sends[1]["client_id"])
    #expect(board.posts.count == 1)
    await transport.forgeReceipt()
    draft.title = "New post"
    #expect(await !board.publish(draft))
    #expect(board.error?.contains("not confirmed") == true)
    let requests = await transport.requests
    #expect(
      requests.allSatisfy {
        $0.url?.query == nil
          && $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.token)"
      })
  }

  @Test func changingUnconfirmedContentGetsANewSendIdentifier() async throws {
    let transport = ClubhouseEchoTransport(sectionID: sid, postID: pid, section: section)
    let board = ClubSectionStore(id: sid, community: try await service(transport))
    var draft = ClubPostDraft()
    draft.title = "First title"
    #expect(await !board.publish(draft))
    draft.title = "Different content"
    #expect(await board.publish(draft))
    let sends = await transport.sentBodies
    #expect(sends[0]["client_id"] != sends[1]["client_id"])
  }

  @Test func sectionContentNeverAppearsInPublicFeedEncoding() throws {
    let publicJSON = String(
      decoding: try APICoding.encoder().encode(Fixtures.feed()), as: UTF8.self)
    #expect(
      !publicJSON.contains("clubhouse") && !publicJSON.contains("my_vote")
        && !publicJSON.contains("membership\":\"active"))
    let requestDraft = ClubPostDraft(kind: "discussion", title: "Title", body: "Body")
    let encoded =
      try JSONSerialization.jsonObject(with: APICoding.encoder().encode(requestDraft))
      as! [String: Any]
    #expect(encoded["client_id"] != nil && encoded["clientID"] == nil)
  }
}

actor ClubhouseEchoTransport: HTTPTransport {
  let sectionID: String
  let postID: String
  let section: String
  private var failFirst = true
  private var forge = false
  private var saved: Data?
  private(set) var sentBodies: [[String: String]] = []
  private(set) var requests: [URLRequest] = []
  init(sectionID: String, postID: String, section: String) {
    self.sectionID = sectionID
    self.postID = postID
    self.section = section
  }
  func forgeReceipt() { forge = true }
  func send(_ request: URLRequest) throws -> HTTPPayload {
    requests.append(request)
    if request.httpMethod == "POST" {
      let raw = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      sentBodies.append(raw.compactMapValues { $0 as? String })
      if failFirst {
        failFirst = false
        throw APIError.unavailable
      }
      let result: [String: Any] = [
        "id": postID, "section_id": forge ? UUID().uuidString : sectionID,
        "author_id": "7da8e118-dd70-439b-bc0d-34ef4645de77",
        "client_id": raw["client_id"]!, "kind": raw["kind"]!, "title": raw["title"]!,
        "body": raw["body"]!, "author": "Test Member",
        "created_at": "2026-10-19T18:00:00Z", "closes_at": NSNull(), "closed_at": NSNull(),
        "pinned": false, "removed": false,
        "comment_count": 0, "my_vote": NSNull(), "options": [], "poll_open": false,
      ]
      let data = try JSONSerialization.data(withJSONObject: result)
      if !forge { saved = data }
      return HTTPPayload(data: data, status: 200)
    }
    if request.url?.path.hasSuffix("/posts") == true {
      let post = String(decoding: saved ?? Data(), as: UTF8.self)
      return HTTPPayload(data: Data("{\"posts\":[\(post)],\"has_older\":false}".utf8), status: 200)
    }
    return HTTPPayload(data: Data(section.utf8), status: 200)
  }
}
