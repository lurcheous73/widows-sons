import AVFAudio
import Foundation
import LiveKit
import Observation

struct VoicePerson: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let speaking: Bool
}

@MainActor @Observable
final class VoiceIntercom: NSObject, RoomDelegate {
  private(set) var isConnected = false
  private(set) var isInSession = false
  private(set) var isBusy = false
  private(set) var isMicrophoneOn = false
  private(set) var isChangingMicrophone = false
  private(set) var status = "Intercom off"
  private(set) var title = "Chapter intercom"
  private(set) var expiresAt: Date?
  private(set) var people: [VoicePerson] = []
  private(set) var error: String?
  private(set) var isPushToTalk = false
  private(set) var isPressingToTalk = false

  @ObservationIgnored private var room: Room?
  @ObservationIgnored private var expiryTask: Task<Void, Never>?
  @ObservationIgnored private var previousSpeakerPreference: Bool?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var talkLimitTask: Task<Void, Never>?
  @ObservationIgnored private var previousAdvancedDucking = false
  @ObservationIgnored private var previousDuckingLevel: AudioDuckingLevel = .min
  @ObservationIgnored private var microphoneRequested = false

  func join(grant: VoiceGrant, baseURL: URL, title: String) async throws {
    #if targetEnvironment(simulator)
      try await connectTransport(grant: grant, baseURL: baseURL, title: title)
    #else
      try await IntercomCallCoordinator.shared.begin(voice: self, title: title) { [weak self] in
        guard let self else { throw CancellationError() }
        try await self.connectTransport(grant: grant, baseURL: baseURL, title: title)
      }
    #endif
  }

  private func connectTransport(grant: VoiceGrant, baseURL: URL, title: String) async throws {
    guard !isBusy else { return }
    generation += 1
    let version = generation
    isBusy = true
    status = "Connecting…"
    error = nil
    self.title = title
    defer { if version == generation { isBusy = false } }
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
    guard let url = components?.url else { throw APIError.configuration }
    previousSpeakerPreference = AudioManager.shared.isSpeakerOutputPreferred
    previousAdvancedDucking = AudioManager.shared.isAdvancedDuckingEnabled
    previousDuckingLevel = AudioManager.shared.duckingLevel
    AudioManager.shared.isAdvancedDuckingEnabled = true
    AudioManager.shared.duckingLevel = .mid
    AudioManager.shared.isSpeakerOutputPreferred = false
    let room = Room(
      delegate: self,
      roomOptions: RoomOptions(
        defaultAudioPublishOptions: AudioPublishOptions(dtx: true, red: true)))
    self.room = room
    isInSession = true
    // No local track is created until the rider explicitly enables the mic.
    try await room.connect(url: url.absoluteString, token: grant.token)
    guard version == generation, self.room === room else {
      await room.disconnect()
      throw CancellationError()
    }
    expiresAt = grant.expiresAt
    isConnected = room.connectionState == .connected
    status = isConnected ? "Connected · microphone off" : "Connecting…"
    updatePeople(room)
    expiryTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(max(0, grant.expiresAt.timeIntervalSinceNow))) } catch
      { return }
      await self?.leave()
      self?.status = "Intercom session ended. Join again to continue."
    }
  }

  func setMicrophone(_ enabled: Bool) async {
    microphoneRequested = enabled
    if !enabled {
      talkLimitTask?.cancel()
      isPressingToTalk = false
    }
    guard enabled ? isConnected : isInSession, !isChangingMicrophone, let room else { return }
    let version = generation
    isChangingMicrophone = true
    defer { isChangingMicrophone = false }
    do {
      if enabled {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
          error =
            "Microphone access is off. You can keep listening, or enable it in iPhone Settings."
          return
        }
      }
      guard version == generation, self.room === room,
        !enabled || room.connectionState == .connected
      else { return }
      let desired = enabled && microphoneRequested && (!isPushToTalk || isPressingToTalk)
      #if !targetEnvironment(simulator)
        try IntercomCallCoordinator.shared.allowMicrophone(desired)
      #endif
      try await room.localParticipant.setMicrophone(enabled: desired)
      guard version == generation, self.room === room else { return }
      isMicrophoneOn = desired
      if desired && (!microphoneRequested || (isPushToTalk && !isPressingToTalk)) {
        try await room.localParticipant.setMicrophone(enabled: false)
        isMicrophoneOn = false
      }
      if isConnected {
        status = isMicrophoneOn ? "Connected · microphone on" : "Connected · microphone off"
      }
      error = nil
    } catch {
      guard version == generation else { return }
      self.error = "Microphone could not change. Check your headset and try again."
      isMicrophoneOn = room.localParticipant.isMicrophoneEnabled()
    }
  }

  func leave() async {
    #if targetEnvironment(simulator)
      await disconnectTransport()
    #else
      await IntercomCallCoordinator.shared.end(voice: self)
    #endif
  }

  func disconnectTransport() async {
    generation += 1
    expiryTask?.cancel()
    expiryTask = nil
    talkLimitTask?.cancel()
    talkLimitTask = nil
    isPressingToTalk = false
    microphoneRequested = false
    let previous = room
    room = nil
    isConnected = false
    isInSession = false
    isMicrophoneOn = false
    isBusy = false
    people = []
    expiresAt = nil
    status = "Intercom off"
    await previous?.disconnect()
    AudioManager.shared.isAdvancedDuckingEnabled = previousAdvancedDucking
    AudioManager.shared.duckingLevel = previousDuckingLevel
    if let preference = previousSpeakerPreference {
      AudioManager.shared.isSpeakerOutputPreferred = preference
      previousSpeakerPreference = nil
    }
  }

  func showError(_ message: String) { error = message }

  func audioInterrupted() async {
    await setMicrophone(false)
    if isInSession { status = "Call audio interrupted · microphone off" }
  }

  func setPushToTalk(_ enabled: Bool) async {
    isPushToTalk = enabled
    isPressingToTalk = false
    await setMicrophone(false)
  }

  func pressToTalk(_ pressed: Bool) {
    isPressingToTalk = pressed
    Task { await setMicrophone(pressed) }
  }

  func speakBriefly() async {
    guard isConnected else { return }
    isPressingToTalk = true
    await setMicrophone(true)
    talkLimitTask?.cancel()
    talkLimitTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(30)) } catch { return }
      self?.isPressingToTalk = false
      await self?.setMicrophone(false)
    }
  }

  private func updatePeople(_ room: Room) {
    guard self.room === room else { return }
    people = room.remoteParticipants.values.map {
      VoicePerson(
        id: $0.identity?.stringValue ?? "unknown", name: $0.name ?? "Rider", speaking: $0.isSpeaking
      )
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  nonisolated func room(
    _ room: Room, didUpdateConnectionState connectionState: ConnectionState,
    from oldConnectionState: ConnectionState
  ) {
    Task { @MainActor [weak self] in
      guard let self, self.room === room else { return }
      self.isConnected = connectionState == .connected
      switch connectionState {
      case .connected:
        self.status =
          self.isMicrophoneOn ? "Connected · microphone on" : "Connected · microphone off"
      case .connecting: self.status = "Connecting…"
      case .reconnecting: self.status = "Reconnecting · audio may be unavailable"
      case .disconnecting: self.status = "Leaving intercom…"
      case .disconnected:
        self.status = "Disconnected · intercom unavailable"
        self.isMicrophoneOn = false
      @unknown default: self.status = "Intercom unavailable"
      }
      self.updatePeople(room)
    }
  }

  nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
    Task { @MainActor [weak self] in self?.updatePeople(room) }
  }
  nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
    Task { @MainActor [weak self] in self?.updatePeople(room) }
  }
  nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
    Task { @MainActor [weak self] in self?.updatePeople(room) }
  }
}
