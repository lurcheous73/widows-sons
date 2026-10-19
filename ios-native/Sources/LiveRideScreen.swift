import MapKit
import SwiftUI

struct LiveRideScreen: View {
  let community: CommunityStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var confirmingEnd = false

  var body: some View {
    ChapterScroll(refresh: community.refreshRide) {
      ScreenHeading(
        eyebrow: "Together on the road", title: community.activeRide?.title ?? "Ride complete.",
        message: "Check in with your group. You decide when your position is shared.")
      if let ride = community.activeRide {
        if community.isVerified {
          RideMap(riders: community.snapshot?.riders ?? [])
          ChapterCard {
            VStack(alignment: .leading, spacing: 16) {
              Label(
                community.isSharingRequested ? "Position sharing is on" : "Position sharing is off",
                systemImage: community.isSharingRequested ? "location.fill" : "location.slash"
              )
              .font(.headline).foregroundStyle(Heritage.brass)
              Text(
                "Only members who have joined this ride can see shared positions. Sharing expires at \(ride.expiresAt.formatted(date: .omitted, time: .shortened))."
              )
              .font(.subheadline).foregroundStyle(Heritage.muted)
              Button(
                community.isSharingRequested
                  ? "Stop sharing my position" : "Share my position for this ride"
              ) {
                if community.isSharingRequested {
                  community.stopSharing()
                } else {
                  Task { await community.startSharing() }
                }
              }.buttonStyle(BrassButtonStyle(outlined: community.isSharingRequested))
                .disabled(community.isRemovingPosition || community.location.isAwaitingPermission)
                .accessibilityIdentifier("ride.sharing")
              if let error = community.location.error {
                Text(error).font(.footnote).foregroundStyle(Heritage.brass)
              }
            }
          }
          if let notice = community.rideNotice {
            Text(notice).font(.footnote).foregroundStyle(Heritage.brass).accessibilityIdentifier(
              "ride.notice")
          }
          Text("Riders & check-ins").font(.title3.weight(.semibold)).foregroundStyle(Heritage.paper)
            .accessibilityAddTraits(.isHeader)
          if community.snapshot == nil {
            Text(
              "Ride positions are unavailable. Pull down to reconnect; old map positions are hidden."
            ).foregroundStyle(Heritage.muted)
          }
          TimelineView(.periodic(from: .now, by: 5)) { context in
            VStack(spacing: 12) {
              ForEach(community.snapshot?.riders ?? []) { rider in
                ChapterCard {
                  VStack(alignment: .leading, spacing: 8) {
                    Text(rider.displayName + (rider.id == community.memberID ? " · you" : "")).font(
                      .headline
                    ).foregroundStyle(Heritage.paper)
                    Text(rider.status(at: context.date)).foregroundStyle(Heritage.brass).font(
                      .subheadline)
                    Text(
                      "Checked in \(rider.checkedInAt.formatted(date: .omitted, time: .shortened))"
                    )
                    .font(.caption).foregroundStyle(Heritage.muted)
                    if let accuracy = rider.accuracy {
                      Text("Accuracy ±\(Int(accuracy)) m").font(.caption).foregroundStyle(
                        Heritage.muted)
                    }
                  }
                }
              }
            }
          }
          Button("Check in with the ride") { Task { await community.checkIn() } }
            .buttonStyle(BrassButtonStyle(outlined: true)).accessibilityIdentifier("ride.checkIn")
          IntercomCard(community: community, eventID: ride.eventID)
          Button("I’m home · finish sharing") { Task { await community.endRide(home: true) } }
            .buttonStyle(BrassButtonStyle()).disabled(community.isRideBusy).accessibilityIdentifier(
              "ride.home")
          Button("Leave ride safely") { confirmingEnd = true }
            .buttonStyle(BrassButtonStyle(outlined: true)).disabled(community.isRideBusy)
          Text(
            "Positions depend on phone signal and GPS. This build has no SOS dispatch or automatic incident detection. Set controls while stopped."
          )
          .font(.footnote).foregroundStyle(Heritage.muted)
        } else {
          Text(
            "Verify your membership online to view the ride. An explicitly started sharing or audio session continues until you stop it or it expires."
          ).foregroundStyle(Heritage.muted)
          Button("Stop sharing my position") { community.stopSharing() }.buttonStyle(
            BrassButtonStyle())
          Button("Leave intercom") { Task { await community.leaveVoice() } }.buttonStyle(
            BrassButtonStyle(outlined: true))
        }
      } else if let notice = community.rideNotice {
        Text(notice).foregroundStyle(Heritage.brass)
      }
    }.navigationTitle("Live ride").navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .toolbarBackground(Heritage.ink, for: .navigationBar).toolbarBackground(
        .visible, for: .navigationBar
      )
      .task(id: "\(scenePhase)-\(community.activeRide?.eventID ?? "none")-\(community.isVerified)")
    {
      guard scenePhase == .active, community.isVerified else { return }
      while !Task.isCancelled, community.activeRide != nil {
        await community.refreshRide()
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
      }
    }
      .confirmationDialog(
        "Leave this live ride?", isPresented: $confirmingEnd, titleVisibility: .visible
      ) {
        Button("Leave ride and stop sharing", role: .destructive) {
          Task { await community.endRide(home: false) }
        }
      } message: {
        Text(
          "The ride sees that you have left safely. Your position is removed and your intercom ends."
        )
      }
  }
}

struct RideMap: View {
  let riders: [LiveRider]
  var body: some View {
    TimelineView(.periodic(from: .now, by: 5)) { context in
      let located = riders.filter {
        $0.sharing && $0.state == "riding" && $0.latitude != nil && $0.longitude != nil
          && $0.capturedAt.map { context.date.timeIntervalSince($0) < 120 } == true
      }
      if located.isEmpty {
        EmptyChapterCard(
          symbol: "map", title: "Room for the whole ride.",
          message:
            "Shared positions appear on the map after riders opt in. No one is tracked automatically."
        )
      } else {
        Map {
          ForEach(located) { rider in
            if let latitude = rider.latitude, let longitude = rider.longitude {
              Annotation(
                rider.displayName,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
              ) {
                Image(systemName: "motorcycle").font(.title3).foregroundStyle(Heritage.ink)
                  .padding(11).background(
                    context.date.timeIntervalSince(rider.capturedAt ?? .distantPast) < 30
                      ? Heritage.brass : Heritage.muted, in: Circle()
                  )
                  .accessibilityLabel("\(rider.displayName), \(rider.status(at: context.date))")
              }
            }
          }
        }.mapStyle(.standard(elevation: .flat)).frame(height: 300)
          .clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityIdentifier("ride.map")
      }
    }
  }
}
