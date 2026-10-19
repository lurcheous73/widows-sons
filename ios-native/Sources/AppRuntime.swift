import Foundation
import Observation

@MainActor
final class AppRuntime {
  static let shared = AppRuntime()
  let store: ChapterStore?
  private init() {
    store = (try? AppConfiguration.bundled()).map { ChapterStore.live(configuration: $0) }
  }
}

@MainActor @Observable
final class VehicleConnection {
  static let shared = VehicleConnection()
  private(set) var connected = false
  func setConnected(_ connected: Bool) { self.connected = connected }
}
