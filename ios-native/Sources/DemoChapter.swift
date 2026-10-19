import Foundation

/// Sample identifiers are deliberately unrelated to the live chapter. The demo
/// transport never owns a URLSession and accepts only the reserved .invalid host.
enum DemoChapter {
  static let origin = URL(string: "https://demo.widows-sons.invalid")!
  static let token = "wss_demo_" + String(repeating: "d", count: 43)
  static let invitation = "wsi_demo_" + String(repeating: "d", count: 43)
  static let member = "10000000-0000-4000-8000-000000000001"
  static let captain = "10000000-0000-4000-8000-000000000002"
  static let rider = "10000000-0000-4000-8000-000000000003"
  static let friend = "10000000-0000-4000-8000-000000000004"
  static let conversation = "20000000-0000-4000-8000-000000000001"
  static let direct = "20000000-0000-4000-8000-000000000002"
  static let rideConversation = "20000000-0000-4000-8000-000000000003"
  static let section = "30000000-0000-4000-8000-000000000001"
  static let invitedSection = "30000000-0000-4000-8000-000000000002"
  static let openSection = "30000000-0000-4000-8000-000000000003"
  static let poll = "40000000-0000-4000-8000-000000000001"
  static let announcement = "40000000-0000-4000-8000-000000000002"
  static let discussion = "40000000-0000-4000-8000-000000000003"
  static let optionCoffee = "50000000-0000-4000-8000-000000000001"
  static let optionLunch = "50000000-0000-4000-8000-000000000002"
  static let eventID = "cms-101"
  static let eventTitle = "Sunday roads & a proper coffee"
  static let names = [
    member: "Alex · demo member", captain: "Jamie · demo Road Captain", rider: "Sam · demo rider",
    friend: "Morgan · demo member",
  ]
  static let route: [[String: Double]] = [
    ["latitude": 52.6369, "longitude": -1.1398], ["latitude": 52.6412, "longitude": -1.1270],
    ["latitude": 52.6470, "longitude": -1.1170], ["latitude": 52.6540, "longitude": -1.1090],
    ["latitude": 52.6630, "longitude": -1.0960], ["latitude": 52.6690, "longitude": -1.0840],
  ]
  static func date(_ offset: TimeInterval = 0) -> String {
    Date.now.addingTimeInterval(offset).ISO8601Format()
  }
  static func eventStart(_ second: Bool) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    let date: Date
    if second {
      let day = calendar.date(byAdding: .day, value: 3, to: .now)!
      date = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: day)!
    } else {
      date = calendar.nextDate(
        after: .now, matching: DateComponents(hour: 10, minute: 0, weekday: 1),
        matchingPolicy: .nextTime)!
    }
    return date.ISO8601Format()
  }
  static func event(_ second: Bool = false) -> ChapterEvent {
    ChapterEvent(
      id: second ? "cms-102" : eventID,
      title: second ? "Chapter evening & charity plans" : eventTitle,
      description: second
        ? "A sample chapter evening to plan volunteering, catch up and decide what comes next. Demo event only."
        : "A relaxed sample ride through Leicestershire, with a coffee stop and a regroup before heading home. Read the briefing, meet your Guardians and join with location sharing off. This is a demonstration event, not an organised chapter ride.",
      startsAt: eventStart(second),
      location: second
        ? "Chapter meeting place · sample" : "Leicester meeting point · sample route",
      url: origin.appending(path: "events"), status: "published")
  }
  static func feed() -> ChapterFeed {
    ChapterFeed(
      chapter: Chapter(
        slug: "lr", name: "Leicestershire & Rutland Widows Sons", displayName: "L&R · demo chapter",
        theme: ChapterTheme(accent: "#C49A59", primary: "#1B242D", background: "#111820"),
        tagline: "Brotherhood. Bikes. Giving back.", website: origin,
        features: ChapterFeatures(
          news: true, events: true, membership: true, rsvp: true, guardian: true, intercom: false)),
      news: [
        ChapterArticle(
          id: "demo-1", title: "Good roads. Better company.",
          excerpt: "Your chapter, the next ride and the people who make it worthwhile.",
          body:
            "Welcome to a working preview of the Widows Sons chapter app.\n\nPlan a ride, meet the Road Captain and Sweep, share a message and keep the group together. Every name, ride and conversation in this demo is a sample.\n\nUse Demo tour at the top to walk through the product. You can change RSVPs, send messages, vote in a poll and run a Guardian help scenario. Reset demo starts the story again.",
          publishedAt: .now.addingTimeInterval(-3600), url: origin.appending(path: "news/welcome")),
        ChapterArticle(
          id: "demo-2", title: "A chapter that gives back.",
          excerpt: "A sample look at chapter volunteering and charity plans.",
          body:
            "The chapter can share public charity stories through the editable website and app. This sample story demonstrates the reading experience.\n\nBeneficiaries, fundraising links and totals will be added once approved. This demo takes no payments and makes no donation claims.",
          publishedAt: .now.addingTimeInterval(-86400), url: origin.appending(path: "news/charity")),
      ], events: [event(), event(true)],
      pages: [
        ChapterPage(
          slug: "about", title: "Brotherhood on the road.",
          body:
            "A native Swift chapter app for Widows Sons L&R, using the proposed Heritage & Road design.\n\nThe demonstration chapter uses fictional members, conversations and rides. The live app connects to the dedicated Canada service; this demo keeps its sample state on this device only.",
          url: origin)
      ], updatedAt: .now)
  }
}

actor DemoSessionStorage: SessionStorage {
  private var token: String? = DemoChapter.token
  func read() -> String? { token }
  func write(_ token: String) { self.token = token }
  func remove() { token = nil }
}

actor DemoFeedStorage: FeedStorage {
  private var feed: ChapterFeed?
  func read() -> ChapterFeed? { feed }
  func write(_ feed: ChapterFeed) { self.feed = feed }
}

actor DemoHTTPTransport: HTTPTransport {
  private var data = DemoData()
  func send(_ request: URLRequest) throws -> HTTPPayload {
    guard request.url?.host == DemoChapter.origin.host, request.url?.scheme == "https" else {
      throw APIError.configuration
    }
    return try data.respond(request)
  }
}

private struct DemoData {
  private var signedIn = true
  private var rsvps = [DemoChapter.eventID: "going", "cms-102": "interested"]
  private var blocked: Set<String> = []
  private var messages: [String: [[String: Any]]] = [:]
  private var rooms: [String: [String: Any]] = [:]
  private var reads: [String: Int] = [:]
  private var nextID = 50
  private var replies: [(Date, String)] = []
  private var joined = false
  private var sharingID: String?
  private var ownState = "riding"
  private var lastCheck = DemoChapter.date()
  private var incidents: [[String: Any]] = []
  private var activity: [[String: Any]] = []
  private var assignments: [[String: Any]] = []
  private var revision = 0
  private var briefing =
    "Arrive fuelled up, with your phone charged and headset paired. Jamie leads; Alex is the Sweep. Keep the formation comfortable, regroup at each stop and check in if you leave the group. This is a sample briefing for the product demo."
  private var meeting = "Leicester meeting point · depart together"
  private var stops: [[String: Any]] = []
  private var route = [DemoChapter.route]
  private var closed = false
  private var assisted: Set<String> = []
  private var sections: [[String: Any]] = []
  private var posts: [[String: Any]] = []
  private var comments: [String: [[String: Any]]] = [:]
  private var votes: [String: [String: String]] = [:]
  private var sectionPeople: [String: [[String: Any]]] = [:]
  private var reports: [[String: Any]] = []
  private var sectionActivity: [[String: Any]] = []
  private let null = NSNull()

  init() {
    rooms[DemoChapter.conversation] = [
      "id": DemoChapter.conversation, "kind": "chapter", "title": "Chapter clubhouse",
      "event_id": NSNull(), "other_member_id": NSNull(),
    ]
    rooms[DemoChapter.direct] = [
      "id": DemoChapter.direct, "kind": "direct", "title": DemoChapter.names[DemoChapter.captain]!,
      "event_id": NSNull(), "other_member_id": DemoChapter.captain,
    ]
    rooms[DemoChapter.rideConversation] = [
      "id": DemoChapter.rideConversation, "kind": "ride", "title": DemoChapter.eventTitle,
      "event_id": DemoChapter.eventID, "other_member_id": NSNull(),
    ]
    messages[DemoChapter.conversation] = [
      message(
        id: 10, room: DemoChapter.conversation, sender: DemoChapter.captain,
        text: "Morning all. The Sunday route and briefing are ready. Who’s joining us?"),
      message(
        id: 11, room: DemoChapter.conversation, sender: DemoChapter.friend,
        text: "Count me in. A proper coffee stop is essential!"),
      message(
        id: 12, room: DemoChapter.conversation, sender: DemoChapter.rider,
        text: "Looking forward to it. I’ll bring the camera."),
    ]
    messages[DemoChapter.direct] = [
      message(
        id: 13, room: DemoChapter.direct, sender: DemoChapter.captain,
        text: "Thanks for being Sweep on the sample ride, Alex. The group’s in good hands.")
    ]
    messages[DemoChapter.rideConversation] = [
      message(
        id: 14, room: DemoChapter.rideConversation, sender: DemoChapter.captain,
        text: "Sample ride channel: meet fuelled up. We’ll regroup after the coffee stop.")
    ]
    assignments = [
      assignment("60000000-0000-4000-8000-000000000001", person: DemoChapter.captain, slot: "lead"),
      assignment("60000000-0000-4000-8000-000000000002", person: DemoChapter.member, slot: "sweep"),
    ]
    stops = [
      [
        "id": "70000000-0000-4000-8000-000000000001", "name": "Coffee & regroup", "kind": "coffee",
        "note": "Wait for the full group before setting off.", "latitude": 52.647,
        "longitude": -1.117,
      ],
      [
        "id": "70000000-0000-4000-8000-000000000002", "name": "Fuel stop", "kind": "fuel",
        "note": "A chance to check in before the return leg.", "latitude": 52.663,
        "longitude": -1.096,
      ],
    ]
    sections = [
      section(
        DemoChapter.section, title: "Social & Sunday rides",
        description: "Ride plans, familiar faces and a little chapter banter.", policy: "approval",
        membership: "active", role: "moderator"),
      section(
        DemoChapter.invitedSection, title: "Friends & families",
        description:
          "A sample invitation to a private chapter group. Joining is always your choice.",
        policy: "invite", membership: "invited"),
      section(
        DemoChapter.openSection, title: "The workshop",
        description: "Share mechanical advice, favourite kit and lessons from the road.",
        policy: "open", membership: "none"),
    ]
    posts = [
      post(
        DemoChapter.poll, kind: "poll", title: "Where shall we regroup?",
        body: "Help shape the next Sunday meet-up. Pick the stop you fancy."),
      post(
        DemoChapter.announcement, kind: "announcement", title: "Welcome to the clubhouse",
        body:
          "A space for the chapter to share plans and stay connected. The sample conversations here are yours to explore.",
        pinned: true),
      post(
        DemoChapter.discussion, kind: "discussion", title: "What’s your favourite local loop?",
        body:
          "Quiet lanes, a good view and somewhere to stop. Share a route you’d bring the chapter back to."
      ),
    ]
    votes[DemoChapter.poll] = [
      DemoChapter.captain: DemoChapter.optionCoffee, DemoChapter.friend: DemoChapter.optionLunch,
      DemoChapter.rider: DemoChapter.optionCoffee,
    ]
    comments[DemoChapter.poll] = [
      [
        "id": 21, "author_id": DemoChapter.captain, "client_id": UUID().uuidString,
        "author": DemoChapter.names[DemoChapter.captain]!,
        "body": "Coffee first, then the scenic route gets my vote.",
        "created_at": DemoChapter.date(-900), "removed": false,
      ]
    ]
    sectionPeople[DemoChapter.section] = [
      [
        "id": DemoChapter.member, "display_name": DemoChapter.names[DemoChapter.member]!,
        "state": "active", "role": "moderator",
      ],
      [
        "id": DemoChapter.captain, "display_name": DemoChapter.names[DemoChapter.captain]!,
        "state": "active", "role": "member",
      ],
      [
        "id": DemoChapter.rider, "display_name": DemoChapter.names[DemoChapter.rider]!,
        "state": "requested", "role": "member",
      ],
    ]
  }

  private func message(id: Int, room: String, sender: String, text: String, client: String? = nil)
    -> [String: Any]
  {
    [
      "id": id, "conversation_id": room, "sender_id": sender,
      "sender_name": DemoChapter.names[sender] ?? "Demo member",
      "client_id": client ?? UUID().uuidString, "body": text, "sent_at": DemoChapter.date(-300),
      "deleted": false,
    ]
  }
  private func assignment(_ id: String, person: String, slot: String) -> [String: Any] {
    [
      "id": id, "member_id": person, "display_name": DemoChapter.names[person] ?? "Demo member",
      "slot": slot, "state": "accepted", "available": true, "accepted_at": DemoChapter.date(-1800),
    ]
  }
  private func section(
    _ id: String, title: String, description: String, policy: String, membership: String,
    role: String = "member"
  ) -> [String: Any] {
    [
      "id": id, "title": title, "description": description, "join_policy": policy,
      "state": "active", "revision": 0, "membership": membership, "role": role,
    ]
  }
  private func post(_ id: String, kind: String, title: String, body: String, pinned: Bool = false)
    -> [String: Any]
  {
    [
      "id": id, "section_id": DemoChapter.section, "author_id": DemoChapter.captain,
      "client_id": UUID().uuidString, "kind": kind, "title": title, "body": body,
      "author": DemoChapter.names[DemoChapter.captain]!, "created_at": DemoChapter.date(-600),
      "closes_at": kind == "poll" ? DemoChapter.date(7 * 86400) as Any : NSNull(),
      "closed_at": NSNull(), "pinned": pinned, "removed": false, "comment_count": 0,
      "my_vote": NSNull(),
      "options": kind == "poll"
        ? [
          ["id": DemoChapter.optionCoffee, "title": "Coffee at the meeting point", "votes": 2],
          ["id": DemoChapter.optionLunch, "title": "A short loop, then lunch", "votes": 1],
        ] : [], "poll_open": kind == "poll",
    ]
  }
  private func response(_ value: Any = [:], status: Int = 200) throws -> HTTPPayload {
    HTTPPayload(
      data: status == 204
        ? Data() : try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      status: status)
  }
  private mutating func log(_ action: String, note: String = "") {
    nextID += 1
    activity.insert(
      [
        "id": nextID, "actor_name": DemoChapter.names[DemoChapter.member]!, "action": action,
        "note": note, "created_at": DemoChapter.date(),
      ], at: 0)
  }
  private mutating func flushReplies() {
    let due = replies.filter { $0.0 <= .now }
    replies.removeAll { $0.0 <= .now }
    for (_, room) in due {
      nextID += 1
      var reply = message(
        id: nextID, room: room, sender: DemoChapter.captain,
        text:
          "Demo reply: message received, Alex. We’ll regroup at the coffee stop and keep the ride together."
      )
      reply["sent_at"] = DemoChapter.date()
      messages[room, default: []].append(reply)
    }
  }
  private func roomSummary(_ id: String) -> [String: Any] {
    var room = rooms[id] ?? [:]
    room["last_message"] = messages[id]?.last?["body"] ?? ""
    room["last_at"] = messages[id]?.last?["sent_at"] ?? NSNull()
    room["unread"] =
      messages[id, default: []].filter {
        ($0["id"] as? Int ?? 0) > (reads[id] ?? 0)
          && $0["sender_id"] as? String != DemoChapter.member
      }.count
    return room
  }
  private func sectionSummary(_ row: [String: Any]) -> [String: Any] {
    var result = row
    let active = row["membership"] as? String == "active"
    let available = row["state"] as? String == "active"
    let moderator = active && row["role"] as? String == "moderator"
    result["can_read"] = active && row["state"] as? String != "paused"
    result["can_post"] = active && available
    result["can_moderate"] = moderator && available
    result["can_configure"] = moderator
    return result
  }
  private func presentedPost(_ row: [String: Any]) -> [String: Any] {
    var result = row
    let id = row["id"] as? String ?? ""
    result["comment_count"] = comments[id]?.count ?? 0
    let choices = votes[id] ?? [:]
    result["my_vote"] = choices[DemoChapter.member] ?? NSNull() as Any
    result["options"] = (row["options"] as? [[String: Any]] ?? []).map { option in
      var updated = option
      updated["votes"] = choices.values.filter { $0 == option["id"] as? String }.count
      return updated
    }
    return result
  }

  mutating func respond(_ request: URLRequest) throws -> HTTPPayload {
    let prefix = "/api/v1/mobile/lr/"
    guard let url = request.url, url.path.hasPrefix(prefix) else {
      throw APIError.server(404, "Demo chapter route not found.")
    }
    let suffix = String(url.path.dropFirst(prefix.count))
    let parts = suffix.split(separator: "/").map(String.init)
    let method = request.httpMethod ?? "GET"
    let body =
      request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      ?? [:]
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    if suffix == "feed" {
      return HTTPPayload(data: try APICoding.encoder().encode(DemoChapter.feed()), status: 200)
    }
    if suffix == "activate" && method == "POST" {
      guard body["code"] as? String == DemoChapter.invitation else {
        throw APIError.server(401, "Use Enter demo membership, or reset the demo.")
      }
      signedIn = true
      return try response(["token": DemoChapter.token, "expires_at": DemoChapter.date(30 * 86400)])
    }
    guard signedIn,
      request.value(forHTTPHeaderField: "Authorization") == "Bearer " + DemoChapter.token
    else { throw APIError.server(401, "Demo membership is signed out.") }
    flushReplies()
    if suffix == "me" {
      return try response([
        "id": DemoChapter.member, "display_name": DemoChapter.names[DemoChapter.member]!,
        "membership_type": "member", "status": "active", "chapter": "Widows Sons L&R · demo",
        "session_expires_at": DemoChapter.date(30 * 86400), "verified_at": DemoChapter.date(),
        "rsvps": rsvps,
      ])
    }
    if suffix == "session" && method == "DELETE" {
      signedIn = false
      return try response(status: 204)
    }
    if suffix == "members" {
      return try response([
        "members": DemoChapter.names.filter { $0.key != DemoChapter.member }.sorted {
          $0.key < $1.key
        }.map {
          ["id": $0.key, "display_name": $0.value, "blocked": blocked.contains($0.key)]
            as [String: Any]
        }
      ])
    }
    if parts.first == "members" && parts.count == 3 && parts[2] == "block" {
      if method == "PUT" { blocked.insert(parts[1]) } else { blocked.remove(parts[1]) }
      return try response(status: 204)
    }
    if parts.first == "events" && parts.count == 3 && parts[2] == "rsvp" {
      guard let value = body["response"] as? String,
        ["going", "interested", "not_going"].contains(value)
      else { throw APIError.invalidResponse }
      rsvps[parts[1]] = value
      return try response(["event_id": parts[1], "response": value])
    }
    if suffix == "conversations" {
      return try response(["conversations": rooms.keys.sorted().map(roomSummary)])
    }
    if suffix == "conversations/direct" {
      guard let person = body["member_id"] as? String, DemoChapter.names[person] != nil,
        !blocked.contains(person)
      else { throw APIError.server(403, "Unblock this demo member before messaging.") }
      if let existing = rooms.first(where: { $0.value["other_member_id"] as? String == person }) {
        return try response(["id": existing.key])
      }
      let id = UUID().uuidString.lowercased()
      rooms[id] = [
        "id": id, "kind": "direct", "title": DemoChapter.names[person]!, "event_id": null,
        "other_member_id": person,
      ]
      return try response(["id": id])
    }
    if parts.first == "conversations" && parts.count >= 3 {
      return try conversation(parts, method: method, body: body, query: query)
    }
    if suffix == "ride-duty" {
      return try response([
        "events": [DemoChapter.eventID],
        "alerts": incidents.filter { $0["resolved_at"] is NSNull }.map {
          ["id": $0["id"]!, "event_id": DemoChapter.eventID, "kind": $0["kind"]!]
        },
      ])
    }
    if suffix == "demo/scenario/help" {
      if incidents.isEmpty {
        incidents.append(
          incident(
            kind: "help",
            note:
              "Demo scenario: Sam has stopped with a puncture at the coffee stop. The Road Captain has seen the request; acknowledge it as Sweep.",
            person: DemoChapter.rider))
      }
      return try response(status: 204)
    }
    if parts.first == "rides" && parts.count >= 3 {
      return try ride(parts, method: method, body: body)
    }
    if parts.first == "sections" {
      return try clubhouse(parts, method: method, body: body, query: query)
    }
    if suffix == "voice" {
      throw APIError.server(
        409,
        "Use the spoken briefing preview in this demo. Live intercom needs the connected app and two phones."
      )
    }
    throw APIError.server(
      404,
      "This action belongs to the connected app. Use Demo tour to explore the working sample journeys."
    )
  }

  private mutating func conversation(
    _ p: [String], method: String, body: [String: Any], query: [URLQueryItem]
  ) throws -> HTTPPayload {
    let id = p[1]
    guard rooms[id] != nil else { throw APIError.server(404, "Demo conversation not found.") }
    if let person = rooms[id]?["other_member_id"] as? String, blocked.contains(person) {
      throw APIError.server(403, "This demo direct conversation is blocked.")
    }
    if p[2] == "read" {
      reads[id] = body["message_id"] as? Int ?? 0
      return try response(status: 204)
    }
    guard p[2] == "messages" else { throw APIError.invalidResponse }
    if p.count > 3 {
      if method == "DELETE",
        let index = messages[id]?.firstIndex(where: { String($0["id"] as? Int ?? 0) == p[3] })
      {
        messages[id]?[index]["deleted"] = true
        messages[id]?[index]["body"] = "Message removed"
      }
      return try response(status: 204)
    }
    if method == "POST" {
      guard let text = body["body"] as? String, let client = body["client_id"] as? String else {
        throw APIError.invalidResponse
      }
      if let existing = messages[id]?.first(where: { $0["client_id"] as? String == client }) {
        return try response(existing)
      }
      nextID += 1
      var saved = message(
        id: nextID, room: id, sender: DemoChapter.member, text: text, client: client)
      saved["sent_at"] = DemoChapter.date()
      messages[id, default: []].append(saved)
      replies.append((.now.addingTimeInterval(1.5), id))
      return try response(saved)
    }
    let before = query.first { $0.name == "before" }.flatMap { Int($0.value ?? "") } ?? Int.max
    return try response([
      "messages": Array(
        messages[id, default: []].filter { ($0["id"] as? Int ?? 0) < before }.suffix(50)),
      "has_older": false,
    ])
  }

  private func incident(
    kind: String, note: String, person: String = DemoChapter.member, client: String? = nil
  ) -> [String: Any] {
    [
      "id": UUID().uuidString.lowercased(), "client_id": client ?? UUID().uuidString,
      "event_id": DemoChapter.eventID, "reporter_id": person, "subject_id": person, "kind": kind,
      "note": note, "reported_at": DemoChapter.date(), "created_at": DemoChapter.date(),
      "resolved_at": null, "resolution": null, "subject_checked_in_at": null,
      "receipts": person == DemoChapter.rider
        ? [
          [
            "member_id": DemoChapter.captain,
            "display_name": DemoChapter.names[DemoChapter.captain]!, "state": "responding",
            "updated_at": DemoChapter.date(),
          ]
        ] : [], "activity": [],
    ]
  }
  private func operations(event: String) -> [String: Any] {
    [
      "event_id": event, "revision": revision, "briefing": briefing, "meeting_point": meeting,
      "check_in_minutes": 15, "stops": stops,
      "route_name": "Leicestershire coffee loop · sample route", "route": route,
      "closed_at": closed ? DemoChapter.date() as Any : null, "updated_at": DemoChapter.date(),
      "server_time": DemoChapter.date(), "can_manage": true, "can_edit": true, "can_respond": true,
      "own_role": "sweep", "assignments": assignments,
      "candidates": DemoChapter.names.sorted { $0.key < $1.key }.map {
        ["id": $0.key, "display_name": $0.value]
      },
      "roster": DemoChapter.names.filter { $0.key != DemoChapter.friend }.sorted { $0.key < $1.key }
        .map { person in
          [
            "id": person.key, "display_name": person.value,
            "state": person.key == DemoChapter.member
              ? ownState : assisted.contains(person.key) ? "assisted" : "riding",
            "checked_in_at": lastCheck, "expires_at": DemoChapter.date(14400),
            "completed_at": person.key == DemoChapter.member && ownState == "home"
              ? DemoChapter.date() as Any : null, "needs_check_in": false, "session_expired": false,
          ]
        }, "incidents": incidents, "activity": activity,
    ]
  }
  private mutating func ride(_ p: [String], method: String, body: [String: Any]) throws
    -> HTTPPayload
  {
    let event = p[1]
    let action = p[2]
    if action == "conversation" { return try response(["id": DemoChapter.rideConversation]) }
    if action == "operations" { return try response(operations(event: event)) }
    if action == "join" {
      guard rsvps[event] == "going", !closed else {
        throw APIError.server(409, "Choose Going before joining this demo ride.")
      }
      joined = true
      ownState = "riding"
      log("ride.joined")
      return try response(["expires_at": DemoChapter.date(14400)])
    }
    if action == "live" {
      guard joined else { throw APIError.server(403, "Join the demo ride first.") }
      let step = sin(Date.now.timeIntervalSince1970 / 30) * 0.001
      let riders = DemoChapter.names.filter { $0.key != DemoChapter.friend }.sorted {
        $0.key < $1.key
      }.map { person -> [String: Any] in
        let own = person.key == DemoChapter.member
        let sharing = !own || sharingID != nil
        let latitude = own ? 52.6369 : (person.key == DemoChapter.captain ? 52.6470 : 52.6412)
        let longitude = own ? -1.1398 : (person.key == DemoChapter.captain ? -1.1170 : -1.1270)
        return [
          "id": person.key, "display_name": person.value, "state": own ? ownState : "riding",
          "sharing": sharing,
          "latitude": sharing ? latitude + (own ? 0 : step) as Any : null,
          "longitude": sharing ? longitude + (own ? 0 : step) as Any : null,
          "accuracy": sharing ? 8 as Any : null,
          "captured_at": sharing ? DemoChapter.date() as Any : null,
          "received_at": sharing ? DemoChapter.date() as Any : null, "checked_in_at": lastCheck,
        ]
      }
      return try response([
        "event_id": event, "expires_at": DemoChapter.date(14400), "riders": riders,
        "server_time": DemoChapter.date(),
      ])
    }
    if action == "sharing" {
      sharingID = UUID().uuidString
      return try response(["sharing_id": sharingID!])
    }
    if action == "position" {
      if method == "DELETE" { sharingID = nil }
      return try response(status: 204)
    }
    if action == "check-in" {
      lastCheck = DemoChapter.date()
      return try response(status: 204)
    }
    if action == "end" {
      ownState = body["state"] as? String ?? "left"
      sharingID = nil
      joined = false
      log("ride." + ownState)
      return try response(status: 204)
    }
    if action == "briefing" {
      guard body["revision"] as? Int == revision else {
        throw APIError.server(409, "Refresh the sample briefing before saving.")
      }
      briefing = body["briefing"] as? String ?? briefing
      meeting = body["meeting_point"] as? String ?? meeting
      stops = body["stops"] as? [[String: Any]] ?? stops
      revision += 1
      log("briefing.updated")
      return try response(status: 204)
    }
    if action == "route" {
      throw APIError.server(
        409,
        "The offline demo includes a sample GPX route. Import a real route in the connected app.")
    }
    if action == "assignments" {
      if p.count == 3 {
        var offered = assignment(
          UUID().uuidString.lowercased(),
          person: body["member_id"] as? String ?? DemoChapter.member,
          slot: body["slot"] as? String ?? "deputy")
        offered["state"] = "pending"
        offered["accepted_at"] = null
        assignments.append(offered)
        log("role.nominated")
      } else if let index = assignments.firstIndex(where: { $0["id"] as? String == p[3] }) {
        if p.count == 5 {
          assignments[index]["state"] = "withdrawn"
          log("role.withdrawn", note: body["note"] as? String ?? "")
        } else {
          assignments[index]["state"] = body["accept"] as? Bool == true ? "accepted" : "declined"
          assignments[index]["accepted_at"] = DemoChapter.date()
          log("role.accepted")
        }
      }
      return try response(status: 204)
    }
    if action == "incidents" {
      if p.count == 3 {
        if let client = body["client_id"] as? String,
          let old = incidents.first(where: { $0["client_id"] as? String == client })
        {
          return try response(old)
        }
        var saved = incident(
          kind: body["kind"] as? String ?? "help", note: body["note"] as? String ?? "",
          client: body["client_id"] as? String)
        saved["subject_id"] = body["subject_id"] ?? DemoChapter.member
        incidents.append(saved)
        log("incident.created")
        return try response(saved)
      }
      if let index = incidents.firstIndex(where: { $0["id"] as? String == p[3] }) {
        let act = body["action"] as? String ?? "acknowledged"
        if ["resolve", "reopen"].contains(act) {
          guard (body["note"] as? String ?? "").count >= 5 else {
            throw APIError.server(422, "Add a reason of at least five characters.")
          }
          incidents[index]["resolved_at"] = act == "resolve" ? DemoChapter.date() as Any : null
          incidents[index]["resolution"] = act == "resolve" ? body["note"] : null
        } else {
          var receipts = incidents[index]["receipts"] as? [[String: Any]] ?? []
          receipts.removeAll { $0["member_id"] as? String == DemoChapter.member }
          receipts.append([
            "member_id": DemoChapter.member, "display_name": DemoChapter.names[DemoChapter.member]!,
            "state": act, "updated_at": DemoChapter.date(),
          ])
          incidents[index]["receipts"] = receipts
        }
        log("incident." + act, note: body["note"] as? String ?? "")
      }
      return try response(status: 204)
    }
    if action == "riders" && p.count == 5 {
      assisted.insert(p[3])
      log("ride.assisted", note: body["note"] as? String ?? "")
      return try response(status: 204)
    }
    if action == "escalations" {
      log("ride.escalation", note: body["note"] as? String ?? "")
      return try response(status: 204)
    }
    if action == "close" {
      guard ownState == "home", incidents.allSatisfy({ !($0["resolved_at"] is NSNull) }) else {
        throw APIError.server(
          409, "Finish the sample requests and use I’m home before closing the demo ride.")
      }
      closed = true
      log("ride.closed")
      return try response(status: 204)
    }
    throw APIError.server(404, "Demo ride action not found.")
  }

  private mutating func clubhouse(
    _ p: [String], method: String, body: [String: Any], query: [URLQueryItem]
  ) throws -> HTTPPayload {
    if p.count == 1 {
      if method == "POST" {
        let id = UUID().uuidString.lowercased()
        sections.append(
          section(
            id, title: body["title"] as? String ?? "New demo section",
            description: body["description"] as? String ?? "",
            policy: body["join_policy"] as? String ?? "approval", membership: "active",
            role: "moderator"))
        return try response(["id": id])
      }
      return try response(["can_create": true, "sections": sections.map(sectionSummary)])
    }
    let sid = p[1]
    guard let si = sections.firstIndex(where: { $0["id"] as? String == sid }) else {
      throw APIError.server(404, "Demo section not found.")
    }
    if p.count == 2 {
      if method == "PUT" {
        guard body["revision"] as? Int == sections[si]["revision"] as? Int else {
          throw APIError.server(409, "Refresh the demo section settings first.")
        }
        for key in ["title", "description", "join_policy", "state"] {
          sections[si][key] = body[key] ?? sections[si][key]
        }
        sections[si]["revision"] = (sections[si]["revision"] as? Int ?? 0) + 1
        return try response(status: 204)
      }
      return try response(sectionSummary(sections[si]))
    }
    if p[2] == "join" {
      sections[si]["membership"] =
        sections[si]["join_policy"] as? String == "approval"
          && sections[si]["membership"] as? String != "invited" ? "requested" : "active"
      return try response(status: 204)
    }
    if p[2] == "membership" && method == "DELETE" {
      sections[si]["membership"] = "left"
      sections[si]["role"] = "member"
      return try response(status: 204)
    }
    guard sections[si]["membership"] as? String == "active",
      sections[si]["state"] as? String != "paused"
    else { throw APIError.server(403, "Join this demo section before opening its content.") }
    if method != "GET", sections[si]["state"] as? String != "active" {
      throw APIError.server(409, "This demo section is archived and read-only.")
    }
    if p[2] == "members" {
      guard sections[si]["role"] as? String == "moderator" else {
        throw APIError.server(403, "This is the section moderator workspace.")
      }
      if p.count == 4 {
        let person = p[3]
        let action = body["action"] as? String ?? "invite"
        var people = sectionPeople[sid] ?? []
        if let index = people.firstIndex(where: { $0["id"] as? String == person }) {
          if action == "promote" || action == "demote" {
            people[index]["role"] = action == "promote" ? "moderator" : "member"
          } else {
            people[index]["state"] =
              action == "approve"
              ? "active"
              : action == "remove" ? "removed" : action == "decline" ? "declined" : "invited"
          }
        } else {
          people.append([
            "id": person, "display_name": DemoChapter.names[person] ?? "Demo member",
            "state": "invited", "role": "member",
          ])
        }
        sectionPeople[sid] = people
        nextID += 1
        sectionActivity.insert(
          [
            "id": nextID, "section_id": sid, "actor_id": DemoChapter.member, "target_id": person,
            "action": "membership." + action, "note": "Demo membership decision",
            "created_at": DemoChapter.date(),
          ], at: 0)
        return try response(status: 204)
      }
      return try response([
        "members": sectionPeople[sid, default: []].filter {
          ["active", "requested", "invited"].contains($0["state"] as? String ?? "")
        }
      ])
    }
    if p[2] == "moderation" {
      return try response([
        "reports": reports.filter { $0["section_id"] as? String == sid },
        "activity": sectionActivity.filter { $0["section_id"] as? String == sid },
      ])
    }
    if p[2] == "reports" && p.count == 5 {
      reports.removeAll { $0["id"] as? String == p[3] }
      return try response(status: 204)
    }
    guard p[2] == "posts" else { throw APIError.invalidResponse }
    if p.count == 3 {
      if method == "POST" {
        if let old = posts.first(where: {
          $0["client_id"] as? String == body["client_id"] as? String
        }) {
          return try response(presentedPost(old))
        }
        let id = UUID().uuidString.lowercased()
        let kind = body["kind"] as? String ?? "discussion"
        var saved = post(
          id, kind: kind, title: body["title"] as? String ?? "Demo discussion",
          body: body["body"] as? String ?? "")
        for key in ["client_id", "closes_at"] { saved[key] = body[key] ?? saved[key] }
        saved["section_id"] = sid
        saved["author_id"] = DemoChapter.member
        saved["author"] = DemoChapter.names[DemoChapter.member]!
        saved["created_at"] = DemoChapter.date()
        saved["options"] = (body["options"] as? [String] ?? []).map {
          ["id": UUID().uuidString.lowercased(), "title": $0, "votes": 0] as [String: Any]
        }
        posts.insert(saved, at: 0)
        return try response(presentedPost(saved))
      }
      return try response([
        "posts": posts.filter { $0["section_id"] as? String == sid }.map(presentedPost),
        "has_older": false,
      ])
    }
    let pid = p[3]
    guard
      let pi = posts.firstIndex(where: {
        $0["id"] as? String == pid && $0["section_id"] as? String == sid
      })
    else { throw APIError.server(404, "Demo post not found.") }
    if p.count == 4 { return try response(presentedPost(posts[pi])) }
    if p[4] == "vote" {
      guard posts[pi]["poll_open"] as? Bool == true else {
        throw APIError.server(409, "This demo poll is closed.")
      }
      if method == "DELETE" {
        votes[pid]?[DemoChapter.member] = nil
      } else if let option = body["option_id"] as? String {
        votes[pid, default: [:]][DemoChapter.member] = option
      }
      return try response(status: 204)
    }
    if p[4] == "actions" {
      let action = body["action"] as? String ?? "pin"
      if action == "close" {
        posts[pi]["poll_open"] = false
        posts[pi]["closed_at"] = DemoChapter.date()
      } else if action == "remove" {
        posts[pi]["removed"] = true
        posts[pi]["title"] = "Removed post"
        posts[pi]["body"] = ""
        posts[pi]["options"] = []
        posts[pi]["poll_open"] = false
      } else {
        posts[pi]["pinned"] = action == "pin"
      }
      return try response(status: 204)
    }
    if p[4] == "reports" {
      reports.append([
        "id": UUID().uuidString.lowercased(), "section_id": sid, "post_id": pid,
        "comment_id": body["comment_id"] ?? null, "reason": body["reason"] ?? "Demo report",
        "created_at": DemoChapter.date(),
      ])
      return try response(status: 204)
    }
    if p[4] == "comments" {
      if p.count > 5 {
        if let index = comments[pid]?.firstIndex(where: { String($0["id"] as? Int ?? 0) == p[5] }) {
          comments[pid]?[index]["removed"] = true
          comments[pid]?[index]["body"] = ""
        }
        return try response(status: 204)
      }
      if method == "POST" {
        if let old = comments[pid]?.first(where: {
          $0["client_id"] as? String == body["client_id"] as? String
        }) {
          return try response([
            "id": old["id"]!, "post_id": pid, "author_id": DemoChapter.member,
            "client_id": old["client_id"]!,
          ])
        }
        nextID += 1
        let saved: [String: Any] = [
          "id": nextID, "author_id": DemoChapter.member,
          "client_id": body["client_id"] ?? UUID().uuidString,
          "author": DemoChapter.names[DemoChapter.member]!, "body": body["body"] ?? "",
          "created_at": DemoChapter.date(), "removed": false,
        ]
        comments[pid, default: []].append(saved)
        return try response([
          "id": nextID, "post_id": pid, "author_id": DemoChapter.member,
          "client_id": saved["client_id"]!,
        ])
      }
      return try response(["comments": comments[pid, default: []], "has_older": false])
    }
    throw APIError.server(404, "Demo section action not found.")
  }
}
