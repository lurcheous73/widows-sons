import Foundation
import Observation

@MainActor @Observable
final class AppRuntime {
  static let shared = AppRuntime()
  private(set) var store: ChapterStore?
  private(set) var instanceID = UUID()
  private init() {
    if let configuration = try? AppConfiguration.bundled() {
      store =
        configuration.isDemo
        ? Self.demoStore(configuration) : ChapterStore.live(configuration: configuration)
    } else {
      store = nil
    }
  }
  static func demoStore(_ configuration: AppConfiguration) -> ChapterStore {
    let api = NativeChapterAPI(configuration: configuration, transport: DemoHTTPTransport())
    return ChapterStore(
      api: api, sessions: DemoSessionStorage(), cache: DemoFeedStorage(),
      community: CommunityStore(api: api, isDemo: true))
  }
  func resetDemo() async {
    guard let store, store.isDemo, let config = try? AppConfiguration.bundled(), config.isDemo
    else { return }
    _ = await store.signOut()
    self.store = Self.demoStore(config)
    instanceID = UUID()
  }
}

@MainActor @Observable
final class VehicleConnection {
  static let shared = VehicleConnection()
  private(set) var connected = false
  func setConnected(_ connected: Bool) { self.connected = connected }
}
