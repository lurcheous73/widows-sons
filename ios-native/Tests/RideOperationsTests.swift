import CarPlay
import Foundation
import Intents
import Security
import Testing

@testable import WidowsSons

@Suite("Ride delivery, Siri permissions and CarPlay configuration")
@MainActor
struct RideOperationsTests {
  private let room = "cdf059e6-e9a9-48d9-94b1-b9de26ecac5f"
  private var configuration: AppConfiguration {
    try! AppConfiguration(baseURL: URL(string: "https://wsmba.the-grange.uk")!)
  }
  private func temporaryStorage() -> (RideRequestStorage, URL) {
    let directory = URL.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    return (RideRequestStorage(namespace: "test", directory: directory), directory)
  }

  @Test func pendingRequestRestoresAfterPrivateViewsSuspendAndRetryKeepsIdentifier() async throws {
    let (storage, directory) = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = IncidentTransport(failures: 1)
    let outbox = RideRequestOutbox(
      api: NativeChapterAPI(configuration: configuration, transport: transport), storage: storage)
    let access = MemberAccess(token: Fixtures.token, memberID: Fixtures.member().id)
    await outbox.authenticate(access)
    try await outbox.enqueue(eventID: "cms-42", kind: "sos", note: "Need recovery")
    let id = try #require(outbox.pending.first?.id)
    #expect(outbox.notice?.contains("Not delivered") == true)
    outbox.suspend()
    #expect(outbox.pending.isEmpty)
    await outbox.authenticate(access)
    #expect(outbox.pending.first?.id == id)
    await outbox.flush()
    #expect(outbox.pending.isEmpty)
    #expect(outbox.notice?.contains("Guardian acknowledgement is shown separately") == true)
    let requests = await transport.requests
    #expect(requests.count == 2)
    let bodies = try requests.map {
      try JSONDecoder().decode([String: String].self, from: $0.httpBody!)
    }
    #expect(bodies[0]["client_id"] == bodies[1]["client_id"])
    #expect(
      bodies.allSatisfy { $0["latitude"] == nil && $0["longitude"] == nil && $0["token"] == nil })
    #expect(try await storage.read(memberID: access.memberID).isEmpty)
  }

  @Test func oldRequestsNeedReconfirmationAndSignoutClearsPrivateQueue() async throws {
    let (storage, directory) = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let pending = PendingRideRequest(
      id: UUID(), eventID: "cms-42", kind: "help", note: "Unsent test", subjectID: nil,
      reportedAt: Date.now.addingTimeInterval(-901))
    try await storage.write([pending], memberID: Fixtures.member().id)
    let transport = IncidentTransport(failures: 0)
    let outbox = RideRequestOutbox(
      api: NativeChapterAPI(configuration: configuration, transport: transport), storage: storage)
    await outbox.authenticate(MemberAccess(token: Fixtures.token, memberID: Fixtures.member().id))
    await outbox.flush()
    #expect(await transport.requests.isEmpty)
    #expect(outbox.pending.count == 1 && outbox.notice?.contains("15 minutes") == true)
    await outbox.close()
    #expect(try await storage.read(memberID: Fixtures.member().id).isEmpty)
  }

  @Test func receiptForAnotherMemberCannotBeShownAsSuccessfulDelivery() async throws {
    let (storage, directory) = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = IncidentTransport(failures: 0, reporter: UUID().uuidString)
    let outbox = RideRequestOutbox(
      api: NativeChapterAPI(configuration: configuration, transport: transport), storage: storage)
    await outbox.authenticate(MemberAccess(token: Fixtures.token, memberID: Fixtures.member().id))
    try await outbox.enqueue(eventID: "cms-42", kind: "help", note: "Need help")
    #expect(outbox.pending.count == 1 && outbox.notice?.contains("Not delivered") == true)
  }

  @Test func queueIsMemberScopedProtectedAndHasNoSessionSecret() async throws {
    let (storage, directory) = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: directory) }
    let value = PendingRideRequest(
      id: UUID(), eventID: "cms-42", kind: "help", note: "Test", subjectID: nil, reportedAt: .now)
    try await storage.write([value], memberID: Fixtures.member().id)
    #expect(try await storage.read(memberID: UUID().uuidString).isEmpty)
    let files = FileManager.default.enumerator(
      at: directory, includingPropertiesForKeys: [.isExcludedFromBackupKey])!
    var inspected = false
    let urls = files.allObjects.compactMap { $0 as? URL }
    for url in urls where url.pathExtension == "json" {
      let contents = try String(contentsOf: url, encoding: .utf8)
      #expect(!contents.contains(Fixtures.token) && !contents.contains("latitude"))
      #if !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(
          attributes[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication
        )
      #endif
      #expect(
        try url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
          .isExcludedFromBackup == true)
      inspected = true
    }
    #expect(inspected)
  }

  @Test func siriSendChecksMembershipAndAllowedConversationBeforeSending() async throws {
    let profile = try APICoding.encoder().encode(Fixtures.member())
    let conversations = Data(
      """
      {"conversations":[{"id":"\(room)","kind":"chapter","title":"Chapter clubhouse","event_id":null,"other_member_id":null,"last_message":"Private text","last_at":null,"unread":1}]}
      """.utf8)
    let transport = StubTransport([
      HTTPPayload(data: profile, status: 200), HTTPPayload(data: conversations, status: 200),
    ])
    let service = SiriMessageService(
      configuration: configuration, transport: transport,
      sessions: MemorySession(token: Fixtures.token))
    do {
      _ = try await service.send(
        conversationID: UUID().uuidString, groupName: nil, recipientID: nil, content: "Wrong room",
        clientID: UUID())
      Issue.record("A room outside the member's conversation list must be rejected")
    } catch { #expect(error as? APIError == .server(403, "Conversation unavailable.")) }
    let requests = await transport.requests
    #expect(requests.count == 2 && requests.allSatisfy { $0.httpMethod == "GET" })
    #expect(
      requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.token)"
          && $0.url?.query == nil
      })
  }

  @Test func siriReportsFailureWhenMembershipHasBeenRevoked() async throws {
    let transport = StubTransport([
      HTTPPayload(data: Data(#"{"detail":"Revoked"}"#.utf8), status: 401)
    ])
    let service = SiriMessageService(
      configuration: configuration, transport: transport,
      sessions: MemorySession(token: Fixtures.token))
    do {
      _ = try await service.search(
        conversationIDs: [], groupNames: [], messageIDs: [], unreadOnly: true, terms: [],
        senderIDs: [])
      Issue.record("Revoked sessions must not reach message reads")
    } catch { #expect(error as? APIError == .server(401, "Revoked")) }
    #expect(await transport.requests.count == 1)
  }

  @Test func siriRetriesUseStableIdentifierAndUnsupportedCallTargetsFail() async {
    let first = CommunicationIntentHandler.clientID(
      identifier: "Siri-request", conversation: room, content: "Hello")
    #expect(
      first
        == CommunicationIntentHandler.clientID(
          identifier: "Siri-request", conversation: room, content: "Hello"))
    #expect(
      first
        != CommunicationIntentHandler.clientID(
          identifier: "Siri-request", conversation: room, content: "Different"))
    let handler = CommunicationIntentHandler()
    let contact = CommunicationIntentHandler.person(
      id: "ws-chapter-intercom", name: "Chapter intercom")
    let intent = INStartCallIntent(
      callRecordFilter: nil, callRecordToCallBack: nil, audioRoute: .unknown,
      destinationType: .normal, contacts: [contact], callCapability: .audioCall)
    #expect(await handler.handle(intent: intent).code == .continueInApp)
    let wrong = INStartCallIntent(
      callRecordFilter: nil, callRecordToCallBack: nil, audioRoute: .unknown,
      destinationType: .normal, contacts: [contact], callCapability: .videoCall)
    #expect(await handler.handle(intent: wrong).code == .failureContactNotSupportedByApp)
  }

  @Test func carplayDelegateImplementsRealDisconnectSelectorAndSceneIsDeclared() throws {
    let delegate = CarPlaySceneDelegate()
    #expect(
      delegate.responds(
        to: #selector(
          CPTemplateApplicationSceneDelegate.templateApplicationScene(
            _:didDisconnectInterfaceController:))))
    let manifest = try #require(
      Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any])
    #expect(manifest["UIApplicationSupportsMultipleScenes"] as? Bool == true)
    let intents = try #require(
      Bundle.main.object(forInfoDictionaryKey: "IntentsSupported") as? [String])
    #expect(
      Set(intents) == [
        "INSendMessageIntent", "INSearchForMessagesIntent", "INSetMessageAttributeIntent",
        "INStartCallIntent",
      ])
  }

  @Test func expiredSafetyLeaseNeverCountsAsSafeArrivalAndGPXEscapesText() {
    let rider = SafetyRider(
      id: "rider", displayName: "Rider", state: "riding", checkedInAt: .distantPast,
      expiresAt: .distantPast, completedAt: nil, needsCheckIn: true, sessionExpired: true)
    #expect(rider.status == "Sharing session ended · arrival unconfirmed")
    #expect(
      GPXRouteDocument.escape("Ride <test> & 'route'")
        == "Ride &lt;test&gt; &amp; &apos;route&apos;")
  }
}

actor IncidentTransport: HTTPTransport {
  private var failures: Int
  private let reporter: String
  private(set) var requests: [URLRequest] = []
  init(failures: Int, reporter: String = Fixtures.member().id) {
    self.failures = failures
    self.reporter = reporter
  }
  func send(_ request: URLRequest) throws -> HTTPPayload {
    requests.append(request)
    if failures > 0 {
      failures -= 1
      return HTTPPayload(data: Data(#"{"detail":"Offline test"}"#.utf8), status: 503)
    }
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let result: [String: Any] = [
      "client_id": body["client_id"]!,
      "id": "a3d34eaa-e74c-42b8-9bdc-a0f4828f14b5", "event_id": "cms-42", "reporter_id": reporter,
      "subject_id": reporter,
      "kind": body["kind"]!, "note": body["note"]!, "reported_at": body["reported_at"]!,
      "created_at": "2026-10-19T16:00:00Z", "resolved_at": NSNull(), "resolution": NSNull(),
      "subject_checked_in_at": NSNull(), "receipts": [], "activity": [],
    ]
    return HTTPPayload(data: try JSONSerialization.data(withJSONObject: result), status: 200)
  }
}
