import MapKit
import SwiftUI
import UniformTypeIdentifiers

enum RideDetailTab: String, CaseIterable, Identifiable {
  case briefing = "Briefing"
  case guardians = "Guardians"
  case requests = "Requests"
  var id: String { rawValue }
}

struct RideOperationsScreen: View {
  let title: String
  @State private var operations: RideOperationsStore
  @State private var tab = RideDetailTab.briefing
  @State private var editingBriefing = false
  @State private var importingRoute = false
  @State private var exportingRoute = false
  @State private var helpKind: String?
  @Environment(\.scenePhase) private var scenePhase

  init(
    eventID: String, title: String, community: CommunityStore, initialTab: RideDetailTab = .briefing
  ) {
    self.title = title
    // One owned store for this immutable navigation destination.
    self.operations = RideOperationsStore(eventID: eventID, community: community)
    self._tab = State(initialValue: initialTab)
  }

  var body: some View {
    ChapterScroll(refresh: operations.refresh) {
      ScreenHeading(
        eyebrow: "Ride together · arrive together", title: title,
        message: "The plan, the people and a clear way to ask for help.")
      if operations.community.isVerified {
        if let plan = operations.plan {
          if plan.closedAt != nil {
            Label(
              "Ride closed · all recorded arrivals and requests resolved",
              systemImage: "checkmark.seal"
            )
            .foregroundStyle(Heritage.brass)
          }
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { detailButtons }
            VStack(alignment: .leading, spacing: 4) { detailButtons }
          }.padding(4).background(Heritage.panel, in: RoundedRectangle(cornerRadius: 14))
          if let error = operations.error { Text(error).foregroundStyle(Heritage.brass) }
          switch tab {
          case .briefing: briefing(plan)
          case .guardians: GuardianTeamSection(plan: plan, operations: operations)
          case .requests: RideRequestsSection(plan: plan, operations: operations)
          }
          if operations.community.activeRide?.eventID == plan.eventID {
            NavigationLink(value: ChapterRoute.liveRide) {
              Label("Live map & intercom", systemImage: "map")
            }
            .buttonStyle(BrassButtonStyle(outlined: true))
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 12) { helpButtons }
              VStack(alignment: .leading, spacing: 12) { helpButtons }
            }
          }
          if let notice = operations.notice {
            Text(notice).font(.footnote).foregroundStyle(Heritage.brass)
          }
          Text(
            "Signal loss means a check-in may be needed. It never means an accident has been detected. Requests need a connection and a human response."
          )
          .font(.footnote).foregroundStyle(Heritage.muted)
        } else if let error = operations.error {
          ConnectionNotice(message: error) { Task { await operations.refresh() } }
        } else {
          ProgressView("Loading ride briefing…").tint(Heritage.brass)
        }
      } else {
        EmptyChapterCard(
          symbol: "lock.shield", title: "Reconnect to the ride.",
          message: "An online membership check is needed for the private briefing and requests.")
      }
    }
    .navigationTitle("Ride briefing").navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbarBackground(Heritage.ink, for: .navigationBar).toolbarBackground(
      .visible, for: .navigationBar
    )
    .task(id: "\(scenePhase)-\(operations.community.isVerified)") {
      guard scenePhase == .active, operations.community.isVerified else {
        operations.clear()
        return
      }
      while !Task.isCancelled {
        await operations.refresh()
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
      }
    }
    .sheet(isPresented: $editingBriefing) {
      if let plan = operations.plan { BriefingEditor(plan: plan, operations: operations) }
    }
    .sheet(item: Binding(get: { helpKind.map { HelpKind(id: $0) } }, set: { helpKind = $0?.id })) {
      kind in
      RideHelpSheet(kind: kind.id, operations: operations)
    }
    .fileImporter(
      isPresented: $importingRoute,
      allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml]
    ) { result in
      Task {
        do {
          let url = try result.get()
          let granted = url.startAccessingSecurityScopedResource()
          defer { if granted { url.stopAccessingSecurityScopedResource() } }
          guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 262144
          else {
            operations.showError("Choose a GPX file up to 256 KiB.")
            return
          }
          if let revision = operations.plan?.revision {
            _ = await operations.importRoute(try Data(contentsOf: url), revision: revision)
          }
        } catch {
          if (error as NSError).code != NSUserCancelledError {
            operations.showError(
              "The GPX file could not be opened. Choose a UTF-8 GPX file up to 256 KiB.")
          }
        }
      }
    }
    .fileExporter(
      isPresented: $exportingRoute, document: GPXRouteDocument(plan: operations.plan),
      contentType: UTType(filenameExtension: "gpx") ?? .xml, defaultFilename: "Widows-Sons-ride.gpx"
    ) { _ in }
  }

  @ViewBuilder private var detailButtons: some View {
    ForEach(RideDetailTab.allCases) { value in
      Button {
        tab = value
      } label: {
        Text(value.rawValue).font(.subheadline.weight(.semibold)).fixedSize()
          .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10)
          .foregroundStyle(tab == value ? Heritage.brass : Heritage.paper)
          .background(
            tab == value ? Heritage.brass.opacity(0.15) : .clear,
            in: RoundedRectangle(cornerRadius: 11))
      }.buttonStyle(.plain).accessibilityAddTraits(tab == value ? .isSelected : [])
        .accessibilityIdentifier("guardian.tab.\(value.rawValue)")
    }
  }

  @ViewBuilder private var helpButtons: some View {
    Button("I need help") { helpKind = "help" }.buttonStyle(BrassButtonStyle(outlined: true))
      .accessibilityIdentifier("guardian.help")
    Button {
      helpKind = "sos"
    } label: {
      Label("SOS", systemImage: "exclamationmark.triangle.fill")
    }
    .buttonStyle(BrassButtonStyle()).tint(.red).accessibilityIdentifier("guardian.sos")
  }

  @ViewBuilder private func briefing(_ plan: RideOperations) -> some View {
    ChapterCard {
      VStack(alignment: .leading, spacing: 14) {
        Eyebrow("Before setting off")
        Text(plan.meetingPoint.isEmpty ? "Meeting point to be confirmed." : plan.meetingPoint).font(
          Heritage.cardTitle
        ).foregroundStyle(Heritage.paper)
        Text(
          plan.briefing.isEmpty
            ? "The ride organiser will add the departure briefing here." : plan.briefing
        )
        .foregroundStyle(Heritage.muted).lineSpacing(5).textSelection(.enabled)
        Text("Check-in window · \(plan.checkInMinutes) minutes").font(.subheadline).foregroundStyle(
          Heritage.brass)
        Text("Updated \(plan.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(
          .caption
        ).foregroundStyle(Heritage.muted)
        if plan.canEdit && plan.closedAt == nil {
          Button("Edit briefing & stops") { editingBriefing = true }.buttonStyle(
            BrassButtonStyle(outlined: true)
          )
          .accessibilityIdentifier("guardian.editBriefing")
        }
      }
    }
    if !plan.route.isEmpty {
      Text(plan.routeName).font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
      RideRouteMap(eventID: plan.eventID, route: plan.route, stops: plan.stops)
      Button("Export GPX route") { exportingRoute = true }.buttonStyle(
        BrassButtonStyle(outlined: true))
      Text(
        "A planned route, separate from rider positions. This view does not provide turn-by-turn guidance."
      ).font(.footnote).foregroundStyle(Heritage.muted)
    }
    if plan.canEdit && plan.closedAt == nil {
      Button(plan.route.isEmpty ? "Import GPX route" : "Replace GPX route") {
        importingRoute = true
      }
      .buttonStyle(BrassButtonStyle(outlined: true)).disabled(operations.busy)
      if !plan.route.isEmpty {
        Button("Remove shared route", role: .destructive) {
          Task { await operations.removeRoute(revision: plan.revision) }
        }.frame(minHeight: 44)
      }
    }
    ForEach(plan.stops) { stop in
      ChapterCard {
        VStack(alignment: .leading, spacing: 10) {
          Label(
            stop.kind.capitalized,
            systemImage: stop.kind == "fuel"
              ? "fuelpump" : stop.kind == "coffee" ? "cup.and.saucer" : "mappin.and.ellipse"
          ).foregroundStyle(Heritage.brass)
          Text(stop.name).font(.headline).foregroundStyle(Heritage.paper)
          if !stop.note.isEmpty { Text(stop.note).foregroundStyle(Heritage.muted) }
          if let latitude = stop.latitude, let longitude = stop.longitude {
            Button("Directions in Maps") {
              let item: MKMapItem
              if #available(iOS 26.0, *) {
                item = MKMapItem(
                  location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
              } else {
                item = MKMapItem(
                  placemark: MKPlacemark(
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
              }
              item.name = stop.name
              item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
              ])
            }.foregroundStyle(Heritage.brass).frame(minHeight: 44)
          }
        }
      }
    }
  }
}

private struct HelpKind: Identifiable { let id: String }

struct GuardianTeamSection: View {
  let plan: RideOperations
  let operations: RideOperationsStore
  @State private var slot = "lead"
  @State private var member = ""
  @State private var withdrawing: GuardianAssignment?
  @State private var reason = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Road roles belong to this ride. They do not grant chapter admin access.")
        .foregroundStyle(Heritage.muted)
      ForEach(RideRole.slots, id: \.self) { role in
        ChapterCard {
          VStack(alignment: .leading, spacing: 12) {
            Eyebrow(RideRole.title(role))
            let assignments = plan.assignments.filter { $0.slot == role }
            if assignments.isEmpty { Text("Awaiting nomination").foregroundStyle(Heritage.muted) }
            ForEach(assignments) { assignment in
              Text(assignment.displayName).font(.headline).foregroundStyle(Heritage.paper)
              Label(
                assignment.state == "pending"
                  ? "Invitation awaiting acceptance"
                  : assignment.available
                    ? "Accepted for this ride" : "Unavailable · check with organiser",
                systemImage: assignment.state == "pending" ? "envelope" : "checkmark.shield"
              )
              .font(.subheadline).foregroundStyle(Heritage.brass)
              if assignment.memberID == operations.community.memberID, assignment.state == "pending"
              {
                Button("Accept this road role") {
                  Task { await operations.accept(assignment, accepted: true) }
                }
                .buttonStyle(BrassButtonStyle()).disabled(operations.busy).accessibilityIdentifier(
                  "guardian.accept.\(role)")
                Button("Decline") { Task { await operations.accept(assignment, accepted: false) } }
                  .frame(minHeight: 44)
              } else if assignment.memberID == operations.community.memberID,
                assignment.state == "accepted", plan.closedAt == nil
              {
                Button("Step down from this role") {
                  withdrawing = assignment
                  reason = ""
                }.frame(minHeight: 44)
              }
            }
          }
        }
      }
      if plan.canManage && plan.closedAt == nil {
        ChapterCard {
          VStack(alignment: .leading, spacing: 16) {
            Text("Nominate a Guardian").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
            Text(
              "Current Guardians remain in place until their replacement accepts. A deputy can be offered a lead or sweep handover."
            ).font(.subheadline).foregroundStyle(Heritage.muted)
            Picker("Road role", selection: $slot) {
              ForEach(RideRole.slots, id: \.self) { Text(RideRole.title($0)).tag($0) }
            }
            Picker("Member", selection: $member) {
              Text("Choose a rider who is Going").tag("")
              ForEach(plan.candidates) { Text($0.displayName).tag($0.id) }
            }
            Button("Send role invitation") {
              Task { await operations.nominate(memberID: member, slot: slot) }
            }
            .buttonStyle(BrassButtonStyle()).disabled(member.isEmpty || operations.busy)
          }
        }
      }
      if !plan.activity.isEmpty { RideActivityList(activity: plan.activity) }
    }
    .alert(
      "Step down from this road role?",
      isPresented: Binding(get: { withdrawing != nil }, set: { if !$0 { withdrawing = nil } })
    ) {
      TextField("Reason for the ride log", text: $reason)
      Button("Cancel", role: .cancel) { withdrawing = nil }
      Button("Record and step down", role: .destructive) {
        if let assignment = withdrawing {
          Task {
            _ = await operations.mutate(
              path: "assignments/\(assignment.id)/withdraw",
              body: try? JSONEncoder().encode(["note": reason]))
          }
        }
        withdrawing = nil
      }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
    } message: {
      Text("The other Guardians and organiser will see your reason in the shared ride log.")
    }
  }
}

struct RideRequestsSection: View {
  let plan: RideOperations
  let operations: RideOperationsStore
  @State private var actionIncident: RideIncident?
  @State private var action = "resolve"
  @State private var reason = ""
  @State private var escalating = false
  @State private var confirmingClose = false
  @State private var assisting: SafetyRider?
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let notice = operations.community.rideOutbox.notice {
        Text(notice).font(.subheadline).foregroundStyle(Heritage.brass).accessibilityIdentifier(
          "guardian.delivery")
      }
      ForEach(operations.community.rideOutbox.pending.filter { $0.eventID == plan.eventID }) {
        request in
        ChapterCard {
          VStack(alignment: .leading, spacing: 12) {
            Label(
              "\(request.kind.uppercased()) · not delivered", systemImage: "wifi.exclamationmark"
            ).foregroundStyle(Heritage.brass)
            Text(
              request.needsReconfirmation
                ? "Check the situation and send a fresh request. This one is over 15 minutes old."
                : "Saved on this iPhone. It will retry when the app reconnects."
            ).foregroundStyle(Heritage.muted)
            Button("Remove unsent request") {
              Task { await operations.community.rideOutbox.remove(request.id) }
            }.frame(minHeight: 44)
          }
        }
      }
      if plan.incidents.isEmpty {
        EmptyChapterCard(
          symbol: "checkmark.bubble", title: "No requests to show.",
          message: plan.canRespond
            ? "Your shared Guardian log will show help requests and individual acknowledgements here."
            : "Your requests and check-in invitations appear here. Other riders’ requests remain private to their Guardians."
        )
      }
      ForEach(plan.incidents) { incident in
        ChapterCard {
          VStack(alignment: .leading, spacing: 12) {
            Label(
              incident.title,
              systemImage: incident.kind == "sos" ? "exclamationmark.triangle.fill" : "hand.raised"
            ).font(.headline).foregroundStyle(
              incident.kind == "sos" && incident.resolvedAt == nil ? .red : Heritage.brass)
            Text("Received \(incident.createdAt.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption).foregroundStyle(Heritage.muted)
            if !incident.note.isEmpty { Text(incident.note).foregroundStyle(Heritage.paper) }
            if let checkIn = incident.subjectCheckedInAt, incident.kind == "check_in" {
              Label(
                "Rider checked in \(checkIn.formatted(date: .omitted, time: .shortened))",
                systemImage: "checkmark.bubble"
              ).foregroundStyle(Heritage.brass)
            }
            if incident.kind == "check_in", incident.subjectID == operations.community.memberID,
              operations.community.activeRide?.eventID == plan.eventID, incident.resolvedAt == nil
            {
              Button("I’m OK · check in") {
                Task {
                  await operations.community.checkIn()
                  await operations.refresh()
                }
              }.buttonStyle(BrassButtonStyle())
            }
            if let resolution = incident.resolution {
              Label(resolution, systemImage: "checkmark.seal").foregroundStyle(Heritage.brass)
            }
            if incident.receipts.isEmpty && incident.resolvedAt == nil {
              Text("No Guardian has acknowledged yet.").foregroundStyle(Heritage.brass)
            }
            ForEach(incident.receipts) { receipt in
              Text(
                "\(receipt.displayName) · \(receipt.state == "responding" ? "responding" : "acknowledged") · \(receipt.updatedAt.formatted(date: .omitted, time: .shortened))"
              ).font(.subheadline).foregroundStyle(Heritage.muted)
            }
            if plan.canRespond && incident.resolvedAt == nil {
              Button("Acknowledge") {
                Task { await operations.act(on: incident, action: "acknowledged") }
              }.buttonStyle(BrassButtonStyle(outlined: true)).disabled(operations.busy)
              Button("I’m responding") {
                Task { await operations.act(on: incident, action: "responding") }
              }.buttonStyle(BrassButtonStyle()).disabled(operations.busy)
              Button("Resolve with a reason") {
                action = "resolve"
                reason = ""
                actionIncident = incident
              }.frame(minHeight: 44)
            }
            if incident.resolvedAt != nil
              && (plan.canRespond || incident.reporterID == operations.community.memberID)
              && plan.closedAt == nil
            {
              Button("Reopen request") {
                action = "reopen"
                reason = ""
                actionIncident = incident
              }.frame(minHeight: 44)
            }
            DisclosureGroup("Request history") { RideActivityList(activity: incident.activity) }
              .foregroundStyle(Heritage.brass)
          }
        }
      }
      if plan.canRespond {
        Text("Safe arrivals").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
        ForEach(plan.roster) { rider in
          ChapterCard {
            VStack(alignment: .leading, spacing: 10) {
              Text(rider.displayName).font(.headline).foregroundStyle(Heritage.paper)
              Text(rider.status).foregroundStyle(Heritage.brass)
              Text(
                "Last check-in \(rider.checkedInAt.formatted(date: .abbreviated, time: .shortened))"
              ).font(.caption).foregroundStyle(Heritage.muted)
              if rider.state == "riding" {
                Button("Request a check-in") {
                  Task {
                    await operations.requestHelp(
                      kind: "check_in", note: "Please check in with your ride Guardians.",
                      subjectID: rider.id)
                  }
                }.buttonStyle(BrassButtonStyle(outlined: true))
                Button("Confirm rider is being assisted") {
                  assisting = rider
                  reason = ""
                }.frame(minHeight: 44)
              }
            }
          }
        }
        if plan.closedAt == nil {
          Button("Record follow-up / escalation") {
            reason = ""
            escalating = true
          }.buttonStyle(BrassButtonStyle(outlined: true))
          Button("Close this ride") { confirmingClose = true }.buttonStyle(BrassButtonStyle())
            .disabled(operations.busy)
          Text(
            "Closure requires every joined rider to have finished and every request to be resolved. A lost connection never counts as a safe arrival."
          ).font(.footnote).foregroundStyle(Heritage.muted)
        }
      }
    }
    .alert(
      action == "resolve" ? "Resolve request" : "Reopen request",
      isPresented: Binding(get: { actionIncident != nil }, set: { if !$0 { actionIncident = nil } })
    ) {
      TextField("Reason for both Guardians", text: $reason)
      Button("Cancel", role: .cancel) { actionIncident = nil }
      Button("Save reason") {
        if let incident = actionIncident {
          Task { await operations.act(on: incident, action: action, note: reason) }
        }
        actionIncident = nil
      }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
    } message: {
      Text("This action and your name remain in the shared incident history.")
    }
    .alert("Record follow-up", isPresented: $escalating) {
      TextField("What action is being taken?", text: $reason)
      Button("Cancel", role: .cancel) {}
      Button("Save follow-up") {
        Task {
          _ = await operations.mutate(
            path: "escalations", body: try? JSONEncoder().encode(["note": reason]))
        }
      }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
    } message: {
      Text(
        "Record who is making contact and the next action. Saving this entry does not contact anyone or dispatch assistance."
      )
    }
    .alert(
      "Confirm assistance",
      isPresented: Binding(get: { assisting != nil }, set: { if !$0 { assisting = nil } })
    ) {
      TextField("Who is helping and what is arranged?", text: $reason)
      Button("Cancel", role: .cancel) { assisting = nil }
      Button("Record assistance") {
        if let rider = assisting {
          Task {
            _ = await operations.mutate(
              path: "riders/\(rider.id)/assistance",
              body: try? JSONEncoder().encode(["note": reason]))
          }
        }
        assisting = nil
      }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
    } message: {
      Text(
        "Record confirmed assistance, without marking the rider as home. Your name and reason are kept in the ride log."
      )
    }
    .confirmationDialog("Close the ride?", isPresented: $confirmingClose, titleVisibility: .visible)
    {
      Button("Close after checking arrivals") {
        Task { _ = await operations.mutate(path: "close") }
      }
    } message: {
      Text("The server checks for unresolved riders and requests before closing.")
    }
  }
}

struct RideActivityList: View {
  let activity: [RideActivity]
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(activity) { entry in
        VStack(alignment: .leading, spacing: 5) {
          Text("\(entry.title) · \(entry.actorName)").font(.subheadline.weight(.medium))
            .foregroundStyle(Heritage.paper)
          if !entry.note.isEmpty {
            Text(entry.note).font(.subheadline).foregroundStyle(Heritage.muted)
          }
          Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            .foregroundStyle(Heritage.muted)
        }
      }
    }
  }
}

struct RideHelpSheet: View {
  let kind: String
  let operations: RideOperationsStore
  @State private var note = ""
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ChapterScroll(refresh: {}) {
        ScreenHeading(
          eyebrow: "Contact your ride Guardians",
          title: kind == "sos" ? "SOS · ask for help." : "We’re here to help.",
          message:
            "Your Road Captain and Sweep can see this request and acknowledge separately. A connection is needed to deliver it."
        )
        TextField("Briefly explain what you need (optional)", text: $note, axis: .vertical)
          .lineLimit(3...6).padding(16).background(
            Heritage.panel, in: RoundedRectangle(cornerRadius: 12)
          ).foregroundStyle(Heritage.paper)
        Text(
          "This does not call emergency services. If immediate emergency help is needed, use the phone’s emergency call controls."
        ).font(.subheadline).foregroundStyle(Heritage.muted)
        Button(kind == "sos" ? "Confirm SOS request" : "Send help request") {
          Task {
            await operations.requestHelp(kind: kind, note: note)
            dismiss()
          }
        }.buttonStyle(BrassButtonStyle()).disabled(note.unicodeScalars.count > 1000)
          .accessibilityIdentifier("guardian.confirmHelp")
      }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .background(Heritage.ink)
    }.preferredColorScheme(.dark).tint(Heritage.brass)
  }
}
