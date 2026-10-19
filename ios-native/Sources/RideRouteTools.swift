import EventKit
import EventKitUI
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct IdentifiedRouteSegment: Identifiable {
  let id: String
  let points: [RoutePoint]
}

struct RideRouteMap: View {
  let eventID: String
  let route: [[RoutePoint]]
  let stops: [RideStop]
  private var segments: [IdentifiedRouteSegment] {
    // A segment is a fixed slot in a published event route. Polling the same
    // route keeps the same identity; replacing its geometry updates that slot.
    zip(0..., route).map { IdentifiedRouteSegment(id: "\(eventID)-segment-\($0.0)", points: $0.1) }
  }
  var body: some View {
    Map {
      ForEach(segments) { segment in
        MapPolyline(
          coordinates: segment.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
          }
        )
        .stroke(Heritage.brass, lineWidth: 5)
      }
      ForEach(stops) { stop in
        if let latitude = stop.latitude, let longitude = stop.longitude {
          Marker(
            stop.name, systemImage: stop.kind == "fuel" ? "fuelpump" : "mappin",
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
          ).tint(Heritage.brass)
        }
      }
    }.mapStyle(.standard(elevation: .flat)).frame(height: 300).clipShape(
      RoundedRectangle(cornerRadius: 20)
    )
    .accessibilityIdentifier("guardian.routeMap")
  }
}

struct GPXRouteDocument: FileDocument {
  static var readableContentTypes: [UTType] { [UTType(filenameExtension: "gpx") ?? .xml] }
  let data: Data
  init(plan: RideOperations?) {
    let name = Self.escape(plan?.routeName ?? "Chapter ride")
    let segments = (plan?.route ?? []).map { segment in
      "<trkseg>"
        + segment.map { "<trkpt lat=\"\($0.latitude)\" lon=\"\($0.longitude)\"/>" }.joined()
        + "</trkseg>"
    }.joined()
    data = Data(
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"Widows Sons\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>\(name)</name>\(segments)</trk></gpx>"
        .utf8)
  }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
  static func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}

struct RideCalendarEditor: UIViewControllerRepresentable {
  let event: ChapterEvent
  let finished: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
  func makeUIViewController(context: Context) -> EKEventEditViewController {
    let editor = EKEventEditViewController()
    let store = EKEventStore()
    let entry = EKEvent(eventStore: store)
    entry.title = event.title
    entry.location = event.location
    entry.notes = event.description
    entry.url = ApprovedWebsite.link(event.url)
    entry.startDate = APICoding.parseDate(event.startsAt) ?? .now
    // The feed has no finish time. The rider can correct this editable placeholder.
    entry.endDate = entry.startDate.addingTimeInterval(3600)
    editor.eventStore = store
    editor.event = entry
    editor.editViewDelegate = context.coordinator
    return editor
  }
  func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}
  final class Coordinator: NSObject, EKEventEditViewDelegate {
    let finished: () -> Void
    init(finished: @escaping () -> Void) { self.finished = finished }
    func eventEditViewController(
      _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
    ) { finished() }
  }
}

struct BriefingEditor: View {
  let plan: RideOperations
  let operations: RideOperationsStore
  @State private var briefing: String
  @State private var meetingPoint: String
  @State private var minutes: Int
  @State private var stops: [RideStop]
  @Environment(\.dismiss) private var dismiss

  init(plan: RideOperations, operations: RideOperationsStore) {
    self.plan = plan
    self.operations = operations
    // A deliberate edit snapshot; remote updates never overwrite unsaved text.
    self.briefing = plan.briefing
    self.meetingPoint = plan.meetingPoint
    self.minutes = plan.checkInMinutes
    self.stops = plan.stops
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Departure briefing") {
          TextField("Meeting point", text: $meetingPoint)
          TextField("Ride briefing", text: $briefing, axis: .vertical).lineLimit(5...12)
          Stepper("Check-in window: \(minutes) minutes", value: $minutes, in: 5...120, step: 5)
        }
        ForEach($stops) { $stop in
          Section("Ride stop") {
            TextField("Stop name", text: $stop.name)
            Picker("Type", selection: $stop.kind) {
              ForEach(["meeting", "fuel", "coffee", "rest", "finish"], id: \.self) {
                Text($0.capitalized).tag($0)
              }
            }
            TextField("Instructions", text: $stop.note, axis: .vertical).lineLimit(2...4)
            TextField("Latitude (optional)", value: $stop.latitude, format: .number).keyboardType(
              .numbersAndPunctuation)
            TextField("Longitude (optional)", value: $stop.longitude, format: .number).keyboardType(
              .numbersAndPunctuation)
            Button("Remove stop", role: .destructive) { stops.removeAll { $0.id == stop.id } }
          }
        }
        if stops.count < 20 {
          Button("Add fuel, coffee or meeting stop") {
            stops.append(RideStop(name: "", kind: "coffee", note: ""))
          }
        }
        if let error = operations.error { Text(error).foregroundStyle(.red) }
        Text(
          "This edit uses briefing revision \(plan.revision). If someone saves first, refresh the briefing before trying again."
        ).font(.footnote)
      }
      .navigationTitle("Edit ride briefing").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              if await operations.saveBriefing(
                revision: plan.revision, briefing: briefing, meetingPoint: meetingPoint,
                minutes: minutes, stops: stops)
              {
                dismiss()
              }
            }
          }
          .disabled(
            operations.busy || briefing.unicodeScalars.count > 6000
              || meetingPoint.unicodeScalars.count > 250
              || stops.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
      }
    }.tint(Heritage.brass).preferredColorScheme(.dark)
  }
}
