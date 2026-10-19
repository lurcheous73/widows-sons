import CoreLocation
import Foundation
import Observation

/// Created on the main actor so Core Location owns the main run loop. Delegate
/// methods copy immutable fix values before hopping into observable UI state.
@MainActor @Observable
final class RideLocationDriver: NSObject, CLLocationManagerDelegate {
  private(set) var isSharing = false
  private(set) var isAwaitingPermission = false
  private(set) var error: String?
  @ObservationIgnored var onFix: (@MainActor (LocationFix) -> Void)?
  @ObservationIgnored private let manager = CLLocationManager()
  @ObservationIgnored private var wantsSharing = false

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
    manager.activityType = .automotiveNavigation
    manager.pausesLocationUpdatesAutomatically = false
    manager.showsBackgroundLocationIndicator = true
  }

  func start() {
    wantsSharing = true
    error = nil
    continueStarting()
  }

  private func continueStarting() {
    guard wantsSharing else { return }
    switch manager.authorizationStatus {
    case .notDetermined:
      isAwaitingPermission = true
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      isAwaitingPermission = false
      manager.allowsBackgroundLocationUpdates = true
      manager.startUpdatingLocation()
      isSharing = true
    case .denied, .restricted:
      isAwaitingPermission = false
      isSharing = false
      wantsSharing = false
      error =
        "Location access is off. Enable it for Widows Sons in iPhone Settings to share on this ride."
    @unknown default:
      stop()
      error = "Location access is unavailable."
    }
  }

  func stop() {
    wantsSharing = false
    manager.stopUpdatingLocation()
    manager.allowsBackgroundLocationUpdates = false
    isSharing = false
    isAwaitingPermission = false
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      if self.wantsSharing { self.continueStarting() }
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    guard let location = locations.last else { return }
    let fix = LocationFix(
      latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
      accuracy: location.horizontalAccuracy, capturedAt: location.timestamp)
    Task { @MainActor [weak self] in
      guard let self, self.isSharing, fix.isUsable(at: .now) else { return }
      self.error = nil
      self.onFix?(fix)
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error)
  {
    let message = error.localizedDescription
    Task { @MainActor [weak self] in
      guard let self, self.wantsSharing else { return }
      self.error = "A fresh position is unavailable. \(message)"
    }
  }
}
