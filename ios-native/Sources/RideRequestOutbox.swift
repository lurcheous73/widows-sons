import CryptoKit
import Foundation
import Observation

actor RideRequestStorage {
  private let directory: URL
  init(namespace: String, directory: URL? = nil) {
    let root =
      directory
      ?? URL.applicationSupportDirectory.appending(
        path: "WidowsSons/PrivateRideRequests", directoryHint: .isDirectory)
    let hash = SHA256.hash(data: Data(namespace.utf8)).map { String(format: "%02x", $0) }.joined()
    self.directory = root.appending(path: hash, directoryHint: .isDirectory)
  }
  private func file(_ memberID: String) throws -> URL {
    let id = try CommunityInput.pathID(memberID)
    return directory.appending(path: id.lowercased() + ".json")
  }
  func read(memberID: String) throws -> [PendingRideRequest] {
    let url = try file(memberID)
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    guard data.count <= 131072 else { throw APIError.invalidResponse }
    let requests = try APICoding.decoder().decode([PendingRideRequest].self, from: data)
    guard requests.count <= 20, Set(requests.map(\.id)).count == requests.count,
      requests.allSatisfy({
        (try? CommunityInput.rideID($0.eventID)) != nil
          && ["sos", "help", "check_in"].contains($0.kind) && $0.note.unicodeScalars.count <= 1000
      })
    else { throw APIError.invalidResponse }
    return requests
  }
  func write(_ requests: [PendingRideRequest], memberID: String) throws {
    let url = try file(memberID)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var protectedDirectory = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try protectedDirectory.setResourceValues(values)
    // Requests can be made from CarPlay while locked, after the first unlock.
    try APICoding.encoder().encode(requests).write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  func remove(memberID: String) throws {
    let url = try file(memberID)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}

@MainActor @Observable
final class RideRequestOutbox {
  private(set) var pending: [PendingRideRequest] = []
  private(set) var notice: String?
  private(set) var isSending = false
  @ObservationIgnored private let api: NativeChapterAPI
  @ObservationIgnored private let storage: RideRequestStorage
  @ObservationIgnored private var access: MemberAccess?
  @ObservationIgnored private var verified = false
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var isSaving = false

  init(api: NativeChapterAPI, storage: RideRequestStorage) {
    self.api = api
    self.storage = storage
  }

  func authenticate(_ access: MemberAccess) async {
    let wasVerified = verified
    verified = true
    guard self.access != access || !wasVerified else { return }
    generation += 1
    let version = generation
    self.access = access
    pending = []
    do {
      let restored = try await storage.read(memberID: access.memberID)
      guard version == generation, self.access == access else { return }
      pending = restored.filter { Date.now.timeIntervalSince($0.reportedAt) < 86400 }
      try await storage.write(pending, memberID: access.memberID)
    } catch { notice = "Unlock this iPhone to read pending ride requests." }
  }

  func suspend() {
    generation += 1
    verified = false
    pending = []
  }

  func close() async {
    generation += 1
    verified = false
    let previous = access
    access = nil
    pending = []
    notice = nil
    if let previous { try? await storage.remove(memberID: previous.memberID) }
  }

  func enqueue(eventID: String, kind: String, note: String, subjectID: String? = nil) async throws {
    guard verified, let access, pending.count < 20, !isSaving else { throw APIError.unavailable }
    isSaving = true
    defer { isSaving = false }
    _ = try CommunityInput.rideID(eventID)
    if let subjectID { _ = try CommunityInput.pathID(subjectID) }
    guard ["sos", "help", "check_in"].contains(kind), note.unicodeScalars.count <= 1000 else {
      throw APIError.invalidResponse
    }
    let version = generation
    let request = PendingRideRequest(
      id: UUID(), eventID: eventID, kind: kind,
      note: note.trimmingCharacters(in: .whitespacesAndNewlines), subjectID: subjectID,
      reportedAt: .now)
    let updated = pending + [request]
    // Persist before reporting the request as queued. No coordinates or bearer token are stored here.
    try await storage.write(updated, memberID: access.memberID)
    guard version == generation, self.access == access else { throw CancellationError() }
    pending = updated
    notice = "Saved on this iPhone · not received by the chapter yet."
    await flush()
  }

  func flush() async {
    guard verified, let access, !isSending else { return }
    isSending = true
    defer { isSending = false }
    let version = generation
    for request in pending {
      guard version == generation, verified, !Task.isCancelled else { return }
      guard !request.needsReconfirmation else {
        notice =
          "An unsent request is over 15 minutes old. Check the situation, remove it and send a fresh request."
        continue
      }
      do {
        let data = try await api.request(
          path: "rides/\(request.eventID)/incidents", method: "POST", token: access.token,
          body: request.body())
        let receipt = try APICoding.decoder().decode(RideIncident.self, from: data)
        guard receipt.eventID == request.eventID, receipt.reporterID == access.memberID,
          receipt.clientID.lowercased() == request.id.uuidString.lowercased()
        else {
          throw APIError.invalidResponse
        }
        guard version == generation, self.access == access else { return }
        pending.removeAll { $0.id == request.id }
        try await storage.write(pending, memberID: access.memberID)
        notice = "Received by the chapter server. Guardian acknowledgement is shown separately."
      } catch is CancellationError { return } catch {
        guard version == generation else { return }
        notice = "Not delivered · \(error.localizedDescription)"
        return
      }
    }
  }

  func remove(_ id: UUID) async {
    guard let access else { return }
    let updated = pending.filter { $0.id != id }
    do {
      try await storage.write(updated, memberID: access.memberID)
      pending = updated
      notice = "Unsent request removed from this iPhone."
    } catch {
      notice = "The pending request could not be removed. Unlock your iPhone and try again."
    }
  }
}
