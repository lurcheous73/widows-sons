import Foundation
import Testing

@testable import WidowsSons

@Suite("Native communications privacy and delivery")
@MainActor
struct CommunityTests {
  private let conversationID = "cdf059e6-e9a9-48d9-94b1-b9de26ecac5f"

  private func service(_ transport: any HTTPTransport) async throws -> CommunityStore {
    let native = NativeChapterAPI(
      configuration: try AppConfiguration(baseURL: URL(string: "https://wsmba.the-grange.uk")!),
      transport: transport)
    let service = CommunityStore(api: native)
    await service.authenticate(member: Fixtures.member(), token: Fixtures.token)
    return service
  }

  @Test func identifiersAndMessagesAreValidatedBeforeBuildingPaths() {
    #expect(throws: APIError.self) { try CommunityInput.pathID("../members") }
    #expect(throws: APIError.self) { try CommunityInput.rideID("cms-4/position") }
    #expect(CommunityInput.message("   ") == nil)
    #expect(CommunityInput.message("text\0hidden") == nil)
    #expect(CommunityInput.message(String(repeating: "x", count: 2001)) == nil)
    #expect(CommunityInput.message(" Hello\nchapter ") == "Hello\nchapter")
  }

  @Test func locationFixesRejectStaleInvalidAndInaccurateData() {
    let now = Date.now
    #expect(
      LocationFix(latitude: 52, longitude: -1, accuracy: 10, capturedAt: now).isUsable(at: now))
    #expect(
      !LocationFix(latitude: .nan, longitude: -1, accuracy: 10, capturedAt: now).isUsable(at: now))
    #expect(
      !LocationFix(latitude: 91, longitude: -1, accuracy: 10, capturedAt: now).isUsable(at: now))
    #expect(
      !LocationFix(latitude: 52, longitude: -1, accuracy: -1, capturedAt: now).isUsable(at: now))
    #expect(
      !LocationFix(
        latitude: 52, longitude: -1, accuracy: 10, capturedAt: now.addingTimeInterval(-121)
      ).isUsable(at: now))
  }

  @Test func positionAgeIsVisibleAndHomeDoesNotImplyCoordinates() throws {
    let json =
      #"{"id":"rider","display_name":"QA rider","state":"riding","sharing":true,"latitude":52,"longitude":-1,"accuracy":10,"captured_at":"2026-10-19T12:00:00Z","received_at":"2026-10-19T12:00:01Z","checked_in_at":"2026-10-19T12:00:01Z"}"#
    let rider = try APICoding.decoder().decode(LiveRider.self, from: Data(json.utf8))
    #expect(rider.status(at: APICoding.parseDate("2026-10-19T12:00:45Z")!).contains("45s"))
    #expect(
      rider.status(at: APICoding.parseDate("2026-10-19T12:03:00Z")!).contains("No recent position"))
    let home = json.replacingOccurrences(of: #""state":"riding""#, with: #""state":"home""#)
    #expect(
      try APICoding.decoder().decode(LiveRider.self, from: Data(home.utf8)).status(at: .now)
        == "Home · sharing ended")
  }

  @Test func snakeCaseCommunicationIdentifiersDecodeCorrectly() throws {
    let json = """
      {"id":"\(conversationID)","kind":"ride","title":"Test ride","event_id":"cms-42","other_member_id":null,"last_message":"Hello","last_at":"2026-10-19T12:00:00Z","unread":2}
      """
    let room = try APICoding.decoder().decode(ConversationSummary.self, from: Data(json.utf8))
    #expect(room.eventID == "cms-42" && room.unread == 2)
    let voice = try APICoding.decoder().decode(
      VoiceGrant.self,
      from: Data(
        #"{"grant_id":"grant","token":"private","expires_at":"2026-10-19T13:00:00Z","room_name":"chapter"}"#
          .utf8))
    #expect(voice.grantID == "grant" && voice.roomName == "chapter")
  }

  @Test func messageRetriesKeepOneClientIdentifierAndPreserveFailedDraft() async throws {
    let transport = EchoChatTransport(memberID: Fixtures.member().id, firstAttemptFails: true)
    let service = try await service(transport)
    let room = try APICoding.decoder().decode(
      ConversationSummary.self,
      from: Data(
        """
        {"id":"\(conversationID)","kind":"chapter","title":"Chapter","event_id":null,"other_member_id":null,"last_message":"","last_at":null,"unread":0}
        """.utf8))
    let thread = ChatThread(conversation: room, community: service)
    thread.draft = "Hello from Swift"
    await thread.send()
    #expect(thread.draft == "Hello from Swift" && thread.messages.isEmpty)
    await thread.send()
    #expect(thread.draft.isEmpty && thread.messages.count == 1)
    let requests = await transport.requests.filter { $0.httpMethod == "POST" }
    #expect(requests.count == 2)
    let firstBody = try JSONDecoder().decode([String: String].self, from: requests[0].httpBody!)
    let retriedBody = try JSONDecoder().decode([String: String].self, from: requests[1].httpBody!)
    #expect(firstBody == retriedBody)
    #expect(UUID(uuidString: firstBody["client_id"] ?? "") != nil)
    #expect(firstBody["body"] == "Hello from Swift")
    #expect(
      requests.allSatisfy {
        $0.url?.query == nil
          && $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.token)"
      })
  }

  @Test func backgroundingClearsPrivateListsAndDrafts() async throws {
    let transport = StubTransport([
      HTTPPayload(data: Data(#"{"conversations":[]}"#.utf8), status: 200)
    ])
    let service = try await service(transport)
    service.saveDraft("Private draft", for: conversationID)
    await service.refreshConversations()
    service.suspendPrivateViews()
    #expect(!service.isVerified && service.conversations.isEmpty && service.people.isEmpty)
    #expect(service.draft(for: conversationID).isEmpty)
    #expect(service.activeRide == nil && !service.location.isSharing && !service.voice.isConnected)
  }

  @Test func revokedSignInInvalidatesCommunications() async throws {
    let transport = StubTransport([
      HTTPPayload(data: Data(#"{"detail":"Session revoked"}"#.utf8), status: 401)
    ])
    let service = try await service(transport)
    await service.refreshConversations()
    #expect(!service.isVerified && service.conversations.isEmpty)
    #expect(service.error == "Session revoked")
  }

  @Test func paginationQueryDoesNotBecomePartOfThePathOrExposeBearer() async throws {
    let transport = StubTransport([])
    let api = NativeChapterAPI(
      configuration: try AppConfiguration(baseURL: URL(string: "https://wsmba.the-grange.uk")!),
      transport: transport)
    let request = await api.makeRequest(
      path: "conversations/\(conversationID)/messages", token: Fixtures.token,
      query: [URLQueryItem(name: "before", value: "42")])
    #expect(request.url?.path.hasSuffix("/messages") == true)
    #expect(request.url?.query == "before=42")
    #expect(request.url?.absoluteString.contains(Fixtures.token) == false)
  }

  @Test func bundledNoticesIncludeVoiceDependencies() throws {
    let url = try #require(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"))
    let notices = try String(contentsOf: url, encoding: .utf8)
    #expect(notices.contains("LiveKit Swift 2.18.0"))
    #expect(notices.contains("Apache License"))
    #expect(notices.contains("LiveKitWebRTC"))
    #expect(notices.contains("LiveKitUniFFI"))
  }
}

actor EchoChatTransport: HTTPTransport {
  let memberID: String
  private var firstAttemptFails: Bool
  private(set) var requests: [URLRequest] = []
  init(memberID: String, firstAttemptFails: Bool) {
    self.memberID = memberID
    self.firstAttemptFails = firstAttemptFails
  }
  func send(_ request: URLRequest) throws -> HTTPPayload {
    requests.append(request)
    if request.httpMethod == "POST" {
      if firstAttemptFails {
        firstAttemptFails = false
        return HTTPPayload(data: Data(#"{"detail":"Try again"}"#.utf8), status: 503)
      }
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      let conversation = request.url!.pathComponents.dropLast().last!
      let result: [String: Any] = [
        "id": 1, "conversation_id": conversation, "sender_id": memberID,
        "sender_name": "QA rider", "client_id": body["client_id"]!, "body": body["body"]!,
        "sent_at": "2026-10-19T12:00:00Z", "deleted": false,
      ]
      return HTTPPayload(data: try JSONSerialization.data(withJSONObject: result), status: 200)
    }
    return HTTPPayload(data: Data(#"{"conversations":[]}"#.utf8), status: 200)
  }
}
