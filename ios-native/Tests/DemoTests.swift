import Foundation
import Testing

@testable import WidowsSons

@Suite("Self-contained product demo")
@MainActor
struct DemoTests {
  private func api() throws -> NativeChapterAPI {
    NativeChapterAPI(
      configuration: try AppConfiguration(baseURL: DemoChapter.origin, isDemo: true),
      transport: DemoHTTPTransport())
  }
  private func community(_ api: NativeChapterAPI) async throws -> CommunityStore {
    let storage = RideRequestStorage(
      namespace: UUID().uuidString,
      directory: URL.temporaryDirectory.appending(
        path: "WidowsSonsDemoTests", directoryHint: .isDirectory))
    let community = CommunityStore(api: api, rideRequestStorage: storage, isDemo: true)
    await community.authenticate(
      member: try await api.fetchMember(token: DemoChapter.token), token: DemoChapter.token)
    return community
  }
  private func decoded<T: Decodable>(
    _ type: T.Type, api: NativeChapterAPI, path: String, method: String = "GET", body: Data? = nil
  ) async throws -> T {
    try APICoding.decoder().decode(
      type,
      from: await api.request(path: path, method: method, token: DemoChapter.token, body: body))
  }

  @Test func demoConfigurationCannotPointAtTheLiveChapter() async throws {
    #expect(throws: APIError.self) {
      try AppConfiguration(baseURL: URL(string: "https://wsmba.the-grange.uk")!, isDemo: true)
    }
    do {
      _ = try await DemoHTTPTransport().send(
        URLRequest(url: URL(string: "https://wsmba.the-grange.uk/api/v1/mobile/lr/feed")!))
      Issue.record("Demo transport accepted a live-service URL")
    } catch { #expect(error as? APIError == .configuration) }
  }

  @Test func firstLaunchIsPopulatedWithoutInvitationsOrNetworkCredentials() async throws {
    let api = try api()
    let feed = try await api.fetchFeed()
    let member = try await api.fetchMember(token: DemoChapter.token)
    #expect(feed.news.count == 2 && feed.events.count == 2)
    #expect(feed.chapter.displayName.contains("demo") && member.id == DemoChapter.member)
    #expect(member.rsvps[DemoChapter.eventID] == .going)
    #expect(await DemoSessionStorage().read() == DemoChapter.token)
  }

  @Test func sendingADemoMessageIsPersistentAndRetryDoesNotDuplicateIt() async throws {
    let api = try api()
    let key = UUID().uuidString
    let body = try JSONEncoder().encode(["client_id": key, "body": "See you at the coffee stop."])
    let first = try await decoded(
      ChapterMessage.self, api: api, path: "conversations/\(DemoChapter.conversation)/messages",
      method: "POST", body: body)
    let second = try await decoded(
      ChapterMessage.self, api: api, path: "conversations/\(DemoChapter.conversation)/messages",
      method: "POST", body: body)
    #expect(first.id == second.id && first.senderID == DemoChapter.member)
    let page = try await decoded(
      MessagesPage.self, api: api, path: "conversations/\(DemoChapter.conversation)/messages")
    #expect(page.messages.filter { $0.clientID == key }.count == 1)
    let fresh = try await decoded(
      MessagesPage.self, api: self.api(), path: "conversations/\(DemoChapter.conversation)/messages"
    )
    #expect(!fresh.messages.contains { $0.clientID == key })
  }

  @Test func rsvpChangesAndGuestModeUseOnlyLocalDemoState() async throws {
    let api = try api()
    try await api.respond(token: DemoChapter.token, eventID: "cms-102", response: .going)
    #expect(try await api.fetchMember(token: DemoChapter.token).rsvps["cms-102"] == .going)
    try await api.signOut(token: DemoChapter.token)
    do {
      _ = try await api.fetchMember(token: DemoChapter.token)
      Issue.record("Signed-out demo was still verified")
    } catch { #expect((error as? APIError)?.requiresSignIn == true) }
    _ = try await api.activate(code: DemoChapter.invitation)
    #expect(try await api.fetchMember(token: DemoChapter.token).id == DemoChapter.member)
  }

  @Test func demoRideStartsWithOwnSharingOffAndOnlySimulatedPositions() async throws {
    let api = try api()
    _ = try await api.request(
      path: "rides/\(DemoChapter.eventID)/join", method: "POST", token: DemoChapter.token)
    let before = try await decoded(
      RideSnapshot.self, api: api, path: "rides/\(DemoChapter.eventID)/live")
    #expect(before.riders.count == 3)
    #expect(before.riders.first { $0.id == DemoChapter.member }?.sharing == false)
    #expect(before.riders.first { $0.id == DemoChapter.member }?.latitude == nil)
    _ = try await api.request(
      path: "rides/\(DemoChapter.eventID)/sharing", method: "POST", token: DemoChapter.token)
    let after = try await decoded(
      RideSnapshot.self, api: api, path: "rides/\(DemoChapter.eventID)/live")
    #expect(after.riders.first { $0.id == DemoChapter.member }?.sharing == true)
    let driver = RideLocationDriver(isDemo: true)
    driver.start()
    #expect(driver.isSharing && !driver.isAwaitingPermission)
    driver.stop()
    #expect(!driver.isSharing)
  }

  @Test func guardianScenarioKeepsIndependentReceiptsAndCanBeResolved() async throws {
    let community = try await community(api())
    _ = try await community.request(path: "demo/scenario/help", method: "POST")
    let operations = RideOperationsStore(eventID: DemoChapter.eventID, community: community)
    await operations.refresh()
    let request = try #require(operations.plan?.incidents.first)
    #expect(request.receipts.count == 1 && request.receipts[0].memberID == DemoChapter.captain)
    await operations.act(on: request, action: "acknowledged")
    let updated = try #require(operations.plan?.incidents.first)
    #expect(updated.receipts.count == 2)
    await operations.act(
      on: updated, action: "resolve", note: "Demo recovery arranged at the coffee stop.")
    #expect(operations.plan?.incidents.first?.resolvedAt != nil)
    await community.close()
  }

  @Test func pollsAndCommentsRemainInteractiveAndIsolatedBetweenDemoRuns() async throws {
    let api = try api()
    _ = try await api.request(
      path: "sections/\(DemoChapter.section)/posts/\(DemoChapter.poll)/vote", method: "PUT",
      token: DemoChapter.token, body: JSONEncoder().encode(["option_id": DemoChapter.optionCoffee]))
    let post = try await decoded(
      ClubPost.self, api: api, path: "sections/\(DemoChapter.section)/posts/\(DemoChapter.poll)")
    #expect(post.myVote == DemoChapter.optionCoffee && post.options[0].votes == 3)
    let community = try await community(api)
    let thread = ClubPostStore(
      sectionID: DemoChapter.section, postID: DemoChapter.poll, community: community)
    await thread.refresh()
    thread.draft = "Demo comment from the presenter."
    await thread.comment()
    #expect(thread.error == nil && thread.draft.isEmpty)
    #expect(thread.comments.last?.body == "Demo comment from the presenter.")
    let reset = try await decoded(
      ClubPost.self, api: self.api(),
      path: "sections/\(DemoChapter.section)/posts/\(DemoChapter.poll)")
    #expect(reset.myVote == nil && reset.options[0].votes == 2)
    await community.close()
  }

  @Test func sectionInvitationRequiresExplicitAcceptance() async throws {
    let api = try api()
    let before = try await decoded(
      ClubSection.self, api: api, path: "sections/\(DemoChapter.invitedSection)")
    #expect(before.membership == "invited" && !before.canRead)
    _ = try await api.request(
      path: "sections/\(DemoChapter.invitedSection)/join", method: "POST", token: DemoChapter.token)
    let after = try await decoded(
      ClubSection.self, api: api, path: "sections/\(DemoChapter.invitedSection)")
    #expect(after.membership == "active" && after.canRead)
  }

  @Test func demoNeverClaimsLiveVoiceOrCreatesALiveKitGrant() async throws {
    let community = try await community(api())
    await community.joinVoice()
    #expect(!community.voice.isInSession && !community.voice.isConnected)
    #expect(community.voice.error?.contains("preview") == true)
    await community.close()
  }
}
