import Foundation
import Observation

@MainActor @Observable
final class CommunityStore {
  private(set) var isVerified = false
  private(set) var memberID: String?
  private(set) var conversations: [ConversationSummary] = []
  private(set) var people: [ChapterPerson] = []
  private(set) var error: String?
  private(set) var activeRide: LiveRideSession?
  private(set) var snapshot: RideSnapshot?
  private(set) var rideNotice: String?
  private(set) var isRideBusy = false
  private(set) var isRemovingPosition = false
  private(set) var isSharingRequested = false
  private(set) var isRequestingVoice = false
  private(set) var duty: RideDuty?
  let rideOutbox: RideRequestOutbox
  let isDemo: Bool
  let location: RideLocationDriver
  let voice = VoiceIntercom()

  @ObservationIgnored private let api: NativeChapterAPI
  @ObservationIgnored private var access: MemberAccess?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var locationGeneration = 0
  @ObservationIgnored private var latestFix: LocationFix?
  @ObservationIgnored private var uploadTask: Task<Void, Never>?
  @ObservationIgnored private var stopTask: Task<Void, Never>?
  @ObservationIgnored private var expiryTask: Task<Void, Never>?
  @ObservationIgnored private var voiceGrant: VoiceGrant?
  @ObservationIgnored private var sharingID: UUID?
  @ObservationIgnored private var drafts: [String: String] = [:]

  init(api: NativeChapterAPI, rideRequestStorage: RideRequestStorage? = nil, isDemo: Bool = false) {
    self.api = api
    self.isDemo = isDemo
    location = RideLocationDriver(isDemo: isDemo)
    rideOutbox = RideRequestOutbox(
      api: api,
      storage: rideRequestStorage
        ?? RideRequestStorage(namespace: api.configuration.storageNamespace))
    location.onFix = { [weak self] fix in self?.enqueue(fix) }
  }

  func authenticate(member: MemberProfile, token: String) async {
    let updated = MemberAccess(token: token, memberID: member.id)
    if let access, access != updated { await close() }
    self.access = updated
    memberID = member.id
    isVerified = true
    await rideOutbox.authenticate(updated)
  }

  func suspendPrivateViews() {
    generation += 1
    isVerified = false
    conversations = []
    people = []
    snapshot = nil
    drafts = [:]
    duty = nil
    rideOutbox.suspend()
  }

  func close() async {
    generation += 1
    locationGeneration += 1
    uploadTask?.cancel()
    stopTask?.cancel()
    expiryTask?.cancel()
    location.stop()
    sharingID = nil
    isSharingRequested = false
    latestFix = nil
    let previousAccess = access
    let previousRide = activeRide
    let previousGrant = voiceGrant
    voiceGrant = nil
    activeRide = nil
    isRemovingPosition = false
    access = nil
    memberID = nil
    suspendPrivateViews()
    error = nil
    await voice.leave()
    await rideOutbox.close()
    if let previousAccess {
      if let previousRide {
        let body = try? JSONEncoder().encode(["state": "left"])
        _ = try? await api.request(
          path: "rides/\(previousRide.eventID)/end", method: "POST", token: previousAccess.token,
          body: body)
      }
      if let previousGrant {
        _ = try? await api.request(
          path: "voice/\(previousGrant.grantID)", method: "DELETE", token: previousAccess.token)
      }
    }
  }

  func request(
    path: String, method: String = "GET", body: Data? = nil, activeService: Bool = false,
    query: [URLQueryItem] = []
  ) async throws -> Data {
    guard let access, isVerified || activeService else {
      throw APIError.server(401, "Connect and verify your membership first.")
    }
    let version = generation
    do {
      let data = try await api.request(
        path: path, method: method, token: access.token, body: body, query: query)
      guard self.access == access, version == generation else { throw CancellationError() }
      return data
    } catch let failure as APIError where failure.requiresSignIn {
      // A revoked session must stop active microphone and location capture too.
      location.stop()
      sharingID = nil
      isSharingRequested = false
      await voice.leave()
      suspendPrivateViews()
      error = failure.localizedDescription
      throw failure
    }
  }

  func decoded<T: Decodable & Sendable>(
    _ type: T.Type, path: String, method: String = "GET", body: Data? = nil,
    activeService: Bool = false, query: [URLQueryItem] = []
  ) async throws -> T {
    let data = try await request(
      path: path, method: method, body: body, activeService: activeService, query: query)
    do { return try APICoding.decoder().decode(type, from: data) } catch {
      throw APIError.invalidResponse
    }
  }

  func refreshConversations() async {
    struct List: Decodable, Sendable { let conversations: [ConversationSummary] }
    do {
      let updated = try await decoded(List.self, path: "conversations")
      guard isVerified else { return }
      conversations = updated.conversations
      error = nil
    } catch is CancellationError { return } catch { self.error = error.localizedDescription }
  }

  func refreshPeople() async {
    struct List: Decodable, Sendable { let members: [ChapterPerson] }
    do {
      let updated = try await decoded(List.self, path: "members")
      guard isVerified else { return }
      people = updated.members
      error = nil
    } catch { self.error = error.localizedDescription }
  }

  func refreshDuty() async {
    guard isVerified else { return }
    do {
      let updated = try await decoded(RideDuty.self, path: "ride-duty")
      guard isVerified else { return }
      duty = updated
      await rideOutbox.flush()
    } catch is CancellationError { return } catch { duty = nil }
  }

  func direct(to person: ChapterPerson) async throws -> ConversationSummary {
    struct ID: Decodable, Sendable { let id: String }
    _ = try CommunityInput.pathID(person.id)
    let result = try await decoded(
      ID.self, path: "conversations/direct", method: "POST",
      body: JSONEncoder().encode(["member_id": person.id]))
    await refreshConversations()
    guard let conversation = conversations.first(where: { $0.id == result.id }) else {
      throw APIError.invalidResponse
    }
    return conversation
  }

  func rideConversation(event: ChapterEvent) async throws -> ConversationSummary {
    struct ID: Decodable, Sendable { let id: String }
    let id = try CommunityInput.rideID(event.id)
    let result = try await decoded(ID.self, path: "rides/\(id)/conversation", method: "POST")
    await refreshConversations()
    guard let conversation = conversations.first(where: { $0.id == result.id }) else {
      throw APIError.invalidResponse
    }
    return conversation
  }

  func block(_ id: String, blocked: Bool) async throws {
    let id = try CommunityInput.pathID(id)
    _ = try await request(path: "members/\(id)/block", method: blocked ? "PUT" : "DELETE")
    await refreshPeople()
  }

  func draft(for id: String) -> String { drafts[id] ?? "" }
  func saveDraft(_ text: String, for id: String) { drafts[id] = text }

  func join(event: ChapterEvent) async {
    guard !isRideBusy, !isRemovingPosition else { return }
    isRideBusy = true
    defer { isRideBusy = false }
    do {
      let id = try CommunityInput.rideID(event.id)
      struct Joined: Decodable, Sendable { let expiresAt: Date }
      let result = try await decoded(
        Joined.self, path: "rides/\(id)/join", method: "POST",
        body: JSONEncoder().encode(["minutes": 240]))
      location.stop()
      sharingID = nil
      isSharingRequested = false
      isRemovingPosition = false
      stopTask?.cancel()
      await leaveVoice()
      locationGeneration += 1
      uploadTask?.cancel()
      expiryTask?.cancel()
      activeRide = LiveRideSession(eventID: id, title: event.title, expiresAt: result.expiresAt)
      rideNotice = "Joined for up to four hours. Position sharing is off."
      snapshot = nil
      let duration = max(0, result.expiresAt.timeIntervalSinceNow)
      expiryTask = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(duration)) } catch { return }
        guard let self else { return }
        self.location.stop()
        self.sharingID = nil
        self.isSharingRequested = false
        await self.leaveVoice()
        self.activeRide = nil
        self.snapshot = nil
        self.rideNotice = "Your live ride session has ended. Join again to continue."
      }
      await refreshRide()
    } catch { rideNotice = error.localizedDescription }
  }

  func refreshRide() async {
    guard let ride = activeRide else { return }
    do {
      let updated = try await decoded(
        RideSnapshot.self, path: "rides/\(ride.eventID)/live", activeService: true)
      guard activeRide == ride else { return }
      if isVerified { snapshot = updated }
    } catch is CancellationError { return } catch {
      guard activeRide == ride else { return }
      snapshot = nil
      rideNotice = error.localizedDescription
      if case APIError.server(403, _) = error {
        location.stop()
        await leaveVoice()
        activeRide = nil
      }
    }
  }

  func startSharing() async {
    guard isVerified, activeRide != nil, !isRemovingPosition else { return }
    guard let ride = activeRide else { return }
    do {
      struct Sharing: Decodable, Sendable {
        let sharingID: UUID
        enum CodingKeys: String, CodingKey { case sharingID = "sharingId" }
      }
      let result = try await decoded(
        Sharing.self, path: "rides/\(ride.eventID)/sharing", method: "POST")
      guard activeRide == ride else { return }
      locationGeneration += 1
      sharingID = result.sharingID
      isSharingRequested = true
      rideNotice = nil
      location.start()
    } catch { rideNotice = error.localizedDescription }
  }

  private func enqueue(_ fix: LocationFix) {
    guard location.isSharing, sharingID != nil, activeRide != nil, fix.isUsable(at: .now) else {
      return
    }
    latestFix = fix
    guard uploadTask == nil else { return }
    let version = locationGeneration
    uploadTask = Task { [weak self] in
      guard let self else { return }
      defer { self.uploadTask = nil }
      while !Task.isCancelled, version == self.locationGeneration, let fix = self.latestFix,
        let ride = self.activeRide, let sharingID = self.sharingID
      {
        self.latestFix = nil
        do {
          struct Body: Encodable {
            let sharingID: UUID
            let latitude: Double
            let longitude: Double
            let accuracy: Double
            let capturedAt: Date
          }
          let body = try APICoding.encoder().encode(
            Body(
              sharingID: sharingID, latitude: fix.latitude, longitude: fix.longitude,
              accuracy: fix.accuracy, capturedAt: fix.capturedAt))
          _ = try await self.request(
            path: "rides/\(ride.eventID)/position", method: "PUT", body: body, activeService: true)
          guard version == self.locationGeneration else { return }
          self.rideNotice =
            "Position shared with this ride · \(Date.now.formatted(date: .omitted, time: .standard))"
        } catch is CancellationError { return } catch {
          guard version == self.locationGeneration else { return }
          self.rideNotice = "Position not delivered. \(error.localizedDescription)"
        }
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
      }
    }
  }

  func stopSharing() {
    location.stop()
    sharingID = nil
    isSharingRequested = false
    locationGeneration += 1
    uploadTask?.cancel()
    latestFix = nil
    guard let ride = activeRide else { return }
    isRemovingPosition = true
    stopTask?.cancel()
    stopTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled, self.activeRide == ride {
        do {
          _ = try await self.request(
            path: "rides/\(ride.eventID)/position", method: "DELETE", activeService: true)
          self.isRemovingPosition = false
          self.rideNotice = "Sharing stopped. Your position has been removed."
          await self.refreshRide()
          return
        } catch {
          self.rideNotice =
            "Sharing stopped on this iPhone. Waiting to remove the last server position; it expires within two minutes."
          if case APIError.server(401, _) = error {
            self.isRemovingPosition = false
            return
          }
        }
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
      }
      self.isRemovingPosition = false
    }
  }

  @discardableResult
  func checkIn() async -> Bool {
    guard let ride = activeRide else { return false }
    do {
      _ = try await request(
        path: "rides/\(ride.eventID)/check-in", method: "POST", activeService: true)
      rideNotice = "Check-in delivered to the ride."
      await refreshRide()
      return true
    } catch {
      rideNotice = error.localizedDescription
      return false
    }
  }

  func endRide(home: Bool) async {
    guard let ride = activeRide, !isRideBusy else { return }
    location.stop()
    sharingID = nil
    isSharingRequested = false
    locationGeneration += 1
    uploadTask?.cancel()
    stopTask?.cancel()
    latestFix = nil
    isRideBusy = true
    defer { isRideBusy = false }
    await leaveVoice()
    do {
      _ = try await request(
        path: "rides/\(ride.eventID)/end", method: "POST",
        body: JSONEncoder().encode(["state": home ? "home" : "left"]), activeService: true)
      activeRide = nil
      snapshot = nil
      isRemovingPosition = false
      expiryTask?.cancel()
      rideNotice =
        home
        ? "Home check-in delivered. Your position has been removed."
        : "You have left the ride. Your position has been removed."
    } catch {
      rideNotice =
        "Location capture stopped. Your ride check-in was not delivered. Reconnect and try again."
      stopSharing()
    }
  }

  func joinVoice(eventID: String? = nil) async {
    guard !isDemo else {
      voice.showError(
        "Live intercom uses the connected app. This demo offers a spoken briefing preview.")
      return
    }
    guard !voice.isBusy, !isRequestingVoice else { return }
    isRequestingVoice = true
    defer { isRequestingVoice = false }
    await leaveVoice()
    do {
      let body = try JSONEncoder().encode(eventID.map { ["event_id": $0] } ?? [:])
      let grant = try await decoded(VoiceGrant.self, path: "voice", method: "POST", body: body)
      voiceGrant = grant
      let configuration = api.configuration
      try await voice.join(
        grant: grant, baseURL: configuration.baseURL,
        title: eventID == nil ? "Chapter intercom" : activeRide?.title ?? "Ride intercom")
    } catch {
      await leaveVoice()
      if let failure = error as? APIError {
        voice.showError(failure.localizedDescription)
      } else {
        voice.showError("Intercom could not connect. Check your connection and try again.")
      }
    }
  }

  func leaveVoice() async {
    await voice.leave()
    if let grant = voiceGrant, let access {
      _ = try? await api.request(
        path: "voice/\(grant.grantID)", method: "DELETE", token: access.token)
    }
    voiceGrant = nil
  }
}
