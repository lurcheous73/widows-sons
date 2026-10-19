import AVFAudio
import CallKit
import Foundation
import LiveKit

/// CallKit owns activation on physical iPhones. The SDK engine stays disabled
/// until didActivate; microphone publication still needs a separate user action.
@MainActor
final class IntercomCallCoordinator: NSObject, @MainActor CXProviderDelegate {
  static let shared = IntercomCallCoordinator()
  private let provider: CXProvider
  private let controller = CXCallController()
  private var callID: UUID?
  private weak var voice: VoiceIntercom?
  private var connect: (@MainActor () async throws -> Void)?
  private var completion: CheckedContinuation<Void, Error>?
  private var previousAutoConfiguration = true
  private var previousAutoDeactivation = true

  private override init() {
    let configuration = CXProviderConfiguration()
    configuration.supportsVideo = false
    configuration.supportedHandleTypes = [.generic]
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.includesCallsInRecents = false
    provider = CXProvider(configuration: configuration)
    super.init()
    provider.setDelegate(self, queue: .main)
  }

  func begin(
    voice: VoiceIntercom, title: String, connect: @escaping @MainActor () async throws -> Void
  ) async throws {
    guard callID == nil else {
      throw APIError.server(409, "Leave the current intercom before joining another.")
    }
    let id = UUID()
    callID = id
    self.voice = voice
    self.connect = connect
    try await withCheckedThrowingContinuation { continuation in
      completion = continuation
      let action = CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: title))
      action.isVideo = false
      Task {
        do { try await controller.request(CXTransaction(action: action)) } catch {
          guard callID == id else { return }
          finish(
            error: APIError.server(
              503, "Intercom audio could not start. Check call availability and try again."))
        }
      }
    }
  }

  func end(voice: VoiceIntercom) async {
    guard self.voice === voice, let id = callID else {
      await voice.disconnectTransport()
      return
    }
    try? await controller.request(CXTransaction(action: CXEndCallAction(call: id)))
    await voice.disconnectTransport()
    guard callID == id else { return }
    provider.reportCall(with: id, endedAt: .now, reason: .remoteEnded)
    finish(error: CancellationError())
  }

  private func finish(error: Error?) {
    let pending = completion
    completion = nil
    connect = nil
    voice = nil
    callID = nil
    // No audio engine is left running after the call closes.
    try? AudioManager.shared.setEngineAvailability(.none)
    AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = previousAutoConfiguration
    AudioManager.shared.audioSession.isAutomaticDeactivationEnabled = previousAutoDeactivation
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    if let error { pending?.resume(throwing: error) } else { pending?.resume() }
  }

  // This isolated conformance is backed by setDelegate(queue: .main) above.
  // Actions remain on MainActor throughout their asynchronous work.
  func providerDidReset(_ provider: CXProvider) {
    Task { @MainActor in
      await self.voice?.disconnectTransport()
      self.finish(error: APIError.unavailable)
    }
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    Task { @MainActor in
      guard self.callID == action.callUUID, let connect = self.connect else {
        action.fail()
        return
      }
      do {
        self.previousAutoConfiguration =
          AudioManager.shared.audioSession.isAutomaticConfigurationEnabled
        self.previousAutoDeactivation =
          AudioManager.shared.audioSession.isAutomaticDeactivationEnabled
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        AudioManager.shared.audioSession.isAutomaticDeactivationEnabled = false
        try AudioManager.shared.setEngineAvailability(.none)
        try AVAudioSession.sharedInstance().setCategory(
          .playAndRecord, mode: .voiceChat,
          options: [.allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers])
        self.provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: .now)
        action.fulfill()
        try await connect()
        guard self.callID == action.callUUID else { return }
        self.provider.reportOutgoingCall(with: action.callUUID, connectedAt: .now)
        let pending = self.completion
        self.completion = nil
        self.connect = nil
        pending?.resume()
      } catch {
        guard self.callID == action.callUUID else { return }
        let failedVoice = self.voice
        await failedVoice?.disconnectTransport()
        guard self.callID == action.callUUID else { return }
        self.provider.reportCall(with: action.callUUID, endedAt: .now, reason: .failed)
        self.finish(error: error)
      }
    }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    Task { @MainActor in
      if self.callID == action.callUUID {
        await self.voice?.disconnectTransport()
        self.finish(error: CancellationError())
      }
      action.fulfill()
    }
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    Task { @MainActor in
      guard self.callID == action.callUUID, let voice = self.voice else {
        action.fail()
        return
      }
      await voice.setMicrophone(!action.isMuted)
      if voice.isMicrophoneOn == !action.isMuted { action.fulfill() } else { action.fail() }
    }
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    Task { @MainActor in
      guard self.callID != nil else { return }
      // A listen-only start never needs microphone permission.
      try? AudioManager.shared.setEngineAvailability(
        AudioEngineAvailability(
          isInputAvailable: self.voice?.isMicrophoneOn == true, isOutputAvailable: true))
    }
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    Task { @MainActor in
      try? AudioManager.shared.setEngineAvailability(.none)
      await self.voice?.audioInterrupted()
    }
  }

  func allowMicrophone(_ enabled: Bool) throws {
    guard callID != nil else { return }
    let current = AudioManager.shared.engineAvailability
    if enabled && !current.isOutputAvailable {
      throw APIError.server(409, "Call audio is interrupted. Try again after the call resumes.")
    }
    try AudioManager.shared.setEngineAvailability(
      AudioEngineAvailability(
        isInputAvailable: enabled && current.isOutputAvailable,
        isOutputAvailable: current.isOutputAvailable))
  }
}
