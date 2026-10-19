import Foundation

struct RoutePoint: Codable, Equatable, Sendable {
  let latitude: Double
  let longitude: Double
}

struct RideStop: Codable, Equatable, Identifiable, Sendable {
  var id: String = UUID().uuidString.lowercased()
  var name: String
  var kind: String
  var note: String
  var latitude: Double?
  var longitude: Double?
}

struct GuardianAssignment: Decodable, Identifiable, Sendable {
  let id: String
  let memberID: String
  let displayName: String
  let slot: String
  let state: String
  let available: Bool
  let acceptedAt: Date?
  enum CodingKeys: String, CodingKey {
    case id, displayName, slot, state, available, acceptedAt
    case memberID = "memberId"
  }
  var roleTitle: String { RideRole.title(slot) }
}

enum RideRole {
  static let slots = ["lead", "sweep", "deputy", "responder"]
  static func title(_ slot: String) -> String {
    switch slot {
    case "lead": "Road Captain · Lead Guardian"
    case "sweep": "Sweep · Tail Guardian"
    case "deputy": "Deputy Guardian"
    default: "Designated responder"
    }
  }
}

struct RideCandidate: Decodable, Identifiable, Sendable {
  let id: String
  let displayName: String
}

struct SafetyRider: Decodable, Identifiable, Sendable {
  let id: String
  let displayName: String
  let state: String
  let checkedInAt: Date
  let expiresAt: Date
  let completedAt: Date?
  let needsCheckIn: Bool
  let sessionExpired: Bool
  var status: String {
    switch state {
    case "home": "Home confirmed"
    case "left": "Left ride safely"
    case "assisted": "Being assisted"
    default:
      sessionExpired
        ? "Sharing session ended · arrival unconfirmed"
        : needsCheckIn ? "Check-in needed" : "On the ride"
    }
  }
}

struct RideActivity: Decodable, Identifiable, Sendable {
  let id: Int64
  let actorName: String
  let action: String
  let note: String
  let createdAt: Date
  var title: String {
    switch action {
    case "role.nominated": "Road role offered"
    case "role.accepted": "Road role accepted"
    case "role.declined": "Road role declined"
    case "role.withdrawn": "Guardian stepped down"
    case "ride.home": "Safe arrival confirmed"
    case "ride.left": "Left ride safely"
    case "ride.assisted": "Assistance confirmed by a Guardian"
    case "ride.joined": "Joined the ride"
    case "ride.escalation": "Follow-up recorded"
    case "ride.closed": "Ride closed"
    case "briefing.updated": "Briefing updated"
    case "route.updated": "Route updated"
    case "incident.acknowledged": "Acknowledged"
    case "incident.responding": "Responding"
    case "incident.resolve": "Resolved with a reason"
    case "incident.reopen": "Reopened"
    default: "Request recorded"
    }
  }
}

struct IncidentReceipt: Decodable, Identifiable, Sendable {
  let memberID: String
  let displayName: String
  let state: String
  let updatedAt: Date
  var id: String { memberID }
  enum CodingKeys: String, CodingKey {
    case displayName, state, updatedAt
    case memberID = "memberId"
  }
}

struct RideIncident: Decodable, Identifiable, Sendable {
  let id: String
  let clientID: String
  let eventID: String
  let reporterID: String
  let subjectID: String
  let kind: String
  let note: String
  let reportedAt: Date
  let createdAt: Date
  let resolvedAt: Date?
  let resolution: String?
  let subjectCheckedInAt: Date?
  let receipts: [IncidentReceipt]
  let activity: [RideActivity]
  var title: String {
    kind == "sos"
      ? "SOS · urgent assistance" : kind == "help" ? "Rider needs help" : "Check-in requested"
  }
  enum CodingKeys: String, CodingKey {
    case id, kind, note, reportedAt, createdAt, resolvedAt, resolution, subjectCheckedInAt,
      receipts, activity
    case eventID = "eventId"
    case reporterID = "reporterId"
    case subjectID = "subjectId"
    case clientID = "clientId"
  }
}

struct RideOperations: Decodable, Sendable {
  let eventID: String
  let revision: Int
  let briefing: String
  let meetingPoint: String
  let checkInMinutes: Int
  let stops: [RideStop]
  let routeName: String
  let route: [[RoutePoint]]
  let closedAt: Date?
  let updatedAt: Date
  let serverTime: Date
  let canManage: Bool
  let canEdit: Bool
  let canRespond: Bool
  let ownRole: String?
  let assignments: [GuardianAssignment]
  let candidates: [RideCandidate]
  let roster: [SafetyRider]
  let incidents: [RideIncident]
  let activity: [RideActivity]
  enum CodingKeys: String, CodingKey {
    case revision, briefing, meetingPoint, checkInMinutes, stops, routeName, route
    case closedAt, updatedAt, serverTime, canManage, canEdit, canRespond, ownRole
    case assignments, candidates, roster, incidents, activity
    case eventID = "eventId"
  }
}

struct RideDuty: Decodable, Sendable {
  let events: [String]
  let alerts: [RideAlert]
}

struct RideAlert: Decodable, Identifiable, Sendable {
  let id: String
  let eventID: String
  let kind: String
  enum CodingKeys: String, CodingKey {
    case id, kind
    case eventID = "eventId"
  }
}

struct PendingRideRequest: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let eventID: String
  let kind: String
  let note: String
  let subjectID: String?
  let reportedAt: Date
  var needsReconfirmation: Bool { Date.now.timeIntervalSince(reportedAt) > 900 }
  enum CodingKeys: String, CodingKey {
    case id, kind, note, reportedAt
    case eventID = "eventId"
    case subjectID = "subjectId"
  }
  func body() throws -> Data {
    struct Body: Encodable {
      let clientID: UUID
      let kind: String
      let note: String
      let subjectID: String?
      let reportedAt: Date
    }
    return try APICoding.encoder().encode(
      Body(clientID: id, kind: kind, note: note, subjectID: subjectID, reportedAt: reportedAt))
  }
}
