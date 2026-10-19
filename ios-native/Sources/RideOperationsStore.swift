import Foundation
import Observation

@MainActor @Observable
final class RideOperationsStore {
  let eventID: String
  private(set) var plan: RideOperations?
  private(set) var error: String?
  private(set) var notice: String?
  private(set) var busy = false
  @ObservationIgnored let community: CommunityStore

  init(eventID: String, community: CommunityStore) {
    self.eventID = eventID
    self.community = community
  }

  func refresh() async {
    guard community.isVerified else {
      plan = nil
      return
    }
    do {
      _ = try CommunityInput.rideID(eventID)
      let updated = try await community.decoded(
        RideOperations.self, path: "rides/\(eventID)/operations")
      guard updated.eventID == eventID, community.isVerified else { throw APIError.invalidResponse }
      plan = updated
      error = nil
    } catch is CancellationError { return } catch {
      plan = nil
      self.error = error.localizedDescription
    }
  }

  func clear() {
    plan = nil
    error = nil
    notice = nil
  }
  func showError(_ message: String) { error = message }

  @discardableResult
  func mutate(path: String, method: String = "POST", body: Data? = nil) async -> Bool {
    guard !busy else { return false }
    busy = true
    defer { busy = false }
    do {
      _ = try await community.request(path: "rides/\(eventID)/\(path)", method: method, body: body)
      notice = "Saved with the ride."
      error = nil
      await refresh()
      await community.refreshDuty()
      return true
    } catch is CancellationError { return false } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  func nominate(memberID: String, slot: String) async {
    guard (try? CommunityInput.pathID(memberID)) != nil, RideRole.slots.contains(slot) else {
      return
    }
    _ = await mutate(
      path: "assignments", body: try? JSONEncoder().encode(["member_id": memberID, "slot": slot]))
  }

  func accept(_ assignment: GuardianAssignment, accepted: Bool) async {
    guard (try? CommunityInput.pathID(assignment.id)) != nil else { return }
    _ = await mutate(
      path: "assignments/\(assignment.id)", method: "PUT",
      body: try? JSONEncoder().encode(["accept": accepted]))
  }

  func act(on incident: RideIncident, action: String, note: String = "") async {
    guard (try? CommunityInput.pathID(incident.id)) != nil else { return }
    _ = await mutate(
      path: "incidents/\(incident.id)/actions",
      body: try? JSONEncoder().encode(["action": action, "note": note]))
  }

  func requestHelp(kind: String, note: String, subjectID: String? = nil) async {
    do {
      try await community.rideOutbox.enqueue(
        eventID: eventID, kind: kind, note: note, subjectID: subjectID)
      await refresh()
      await community.refreshDuty()
    } catch { self.error = error.localizedDescription }
  }

  func saveBriefing(
    revision: Int, briefing: String, meetingPoint: String, minutes: Int, stops: [RideStop]
  ) async -> Bool {
    struct Body: Encodable {
      let revision: Int
      let briefing: String
      let meetingPoint: String
      let checkInMinutes: Int
      let stops: [RideStop]
    }
    return await mutate(
      path: "briefing", method: "PUT",
      body: try? APICoding.encoder().encode(
        Body(
          revision: revision, briefing: briefing, meetingPoint: meetingPoint,
          checkInMinutes: minutes, stops: stops)))
  }

  func importRoute(_ data: Data, revision: Int) async -> Bool {
    guard !data.isEmpty, data.count <= 262144, let gpx = String(data: data, encoding: .utf8),
      !gpx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      error = "Choose a UTF-8 GPX file up to 256 KiB."
      return false
    }
    struct Body: Encodable {
      let revision: Int
      let gpx: String
    }
    return await mutate(
      path: "route", method: "PUT",
      body: try? JSONEncoder().encode(Body(revision: revision, gpx: gpx)))
  }

  func removeRoute(revision: Int) async {
    struct Body: Encodable {
      let revision: Int
      let gpx = ""
    }
    _ = await mutate(
      path: "route", method: "PUT", body: try? JSONEncoder().encode(Body(revision: revision)))
  }
}
