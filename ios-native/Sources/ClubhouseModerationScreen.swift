import SwiftUI

struct ClubModerationScreen: View {
  let community: CommunityStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var board: ClubSectionStore
  @State private var inviting = false
  @State private var resolving: ClubReport?
  @State private var changingMember: ClubMember?
  @State private var memberAction = ""
  init(id: String, community: CommunityStore) {
    self.community = community
    _board = State(initialValue: ClubSectionStore(id: id, community: community))
  }
  var body: some View {
    ChapterScroll(refresh: refresh) {
      if community.isVerified, board.section?.canModerate == true {
        ScreenHeading(
          eyebrow: "Section moderators", title: "Look after your corner.",
          message: "Membership decisions and reported content for this section only.")
        if let error = board.error { Text(error).foregroundStyle(Heritage.brass) }
        if let notice = board.notice { Text(notice).foregroundStyle(Heritage.brass) }
        Button("Invite a chapter member", systemImage: "person.badge.plus") { inviting = true }
          .buttonStyle(BrassButtonStyle()).accessibilityIdentifier("section.invite")
        Text("Members & requests").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
        ForEach(board.members) { member in memberCard(member) }
        Text("Reports to review").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
        if board.moderation?.reports.isEmpty == true {
          Text("No open reports.").foregroundStyle(Heritage.muted)
        }
        ForEach(board.moderation?.reports ?? []) { report in
          ChapterCard {
            VStack(alignment: .leading, spacing: 12) {
              Text(report.reason).foregroundStyle(Heritage.paper)
              if report.commentID != nil {
                Text("Reported comment").font(.caption).foregroundStyle(Heritage.muted)
              }
              NavigationLink(
                "Read the conversation",
                value: ChapterRoute.clubPost(sectionID: board.id, postID: report.postID)
              ).frame(minHeight: 44)
              Button("Record review outcome") { resolving = report }.frame(minHeight: 44)
            }
          }
        }
        Text("Section activity").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
        ForEach(board.moderation?.activity ?? []) { item in
          VStack(alignment: .leading, spacing: 6) {
            Text(item.action.replacingOccurrences(of: ".", with: " · ")).font(.subheadline.bold())
              .foregroundStyle(Heritage.paper)
            if !item.note.isEmpty {
              Text(item.note).font(.subheadline).foregroundStyle(Heritage.muted)
            }
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
              .foregroundStyle(Heritage.muted)
            if let actor = item.actorID {
              Text("Actor reference · \(actor)").font(.caption2).foregroundStyle(Heritage.muted)
                .textSelection(.enabled)
            }
            Divider().overlay(Heritage.line)
          }
        }
        Text(
          "The latest 100 activity entries and pending reports are shown. A report is a saved request for review; it does not dispatch an urgent alert."
        ).font(.footnote).foregroundStyle(Heritage.muted)
      } else {
        EmptyChapterCard(
          symbol: "lock.shield", title: "Section moderator access.",
          message: board.error
            ?? "Only active moderators of this section can review membership and reports.")
      }
    }.navigationTitle("Members & moderation").clubNavigation()
      .task(id: "\(scenePhase)-\(community.isVerified)") {
        if scenePhase == .active && community.isVerified {
          await refresh()
        } else {
          board.clear()
          inviting = false
          resolving = nil
          changingMember = nil
        }
      }
      .sheet(isPresented: $inviting, onDismiss: reload) {
        ClubInvitePicker(board: board)
      }
      .sheet(item: $resolving) { report in
        ClubReasonSheet(
          title: "Review outcome",
          explanation:
            "Record what you checked and the outcome. Resolve a report after any necessary content or membership action. This does not remove the reported content by itself.",
          failure: { board.error }
        ) { reason in
          let saved = await board.mutate(
            "/reports/\(report.id)/resolve", body: try? JSONEncoder().encode(["reason": reason]))
          if saved { await board.loadModeration() }
          return saved
        }
      }
      .confirmationDialog(
        "Change this section membership?",
        isPresented: Binding(
          get: { changingMember != nil }, set: { if !$0 { changingMember = nil } }),
        titleVisibility: .visible
      ) {
        if let target = changingMember {
          Button(
            "\(memberAction.capitalized) · \(target.displayName)",
            role: memberAction == "remove" ? .destructive : nil
          ) {
            Task { await board.memberAction(target.id, action: memberAction) }
          }
        }
      } message: {
        Text(
          "This changes access or moderation rights in this section only. The decision is recorded in the section activity log."
        )
      }
  }
  private func reload() {
    guard scenePhase == .active, community.isVerified else { return }
    Task { await refresh() }
  }
  private func refresh() async {
    await board.refresh()
    if board.section?.canModerate == true { await board.loadModeration() }
  }
  private func memberCard(_ member: ClubMember) -> some View {
    ChapterCard {
      HStack {
        VStack(alignment: .leading, spacing: 8) {
          Text(member.displayName).font(.headline).foregroundStyle(Heritage.paper)
          Text("\(member.state.capitalized) · \(member.role.capitalized)").font(.caption)
            .foregroundStyle(Heritage.muted)
        }
        Spacer()
        Menu {
          if member.state == "requested" {
            action("Approve request", member: member, action: "approve")
            action("Decline request", member: member, action: "decline")
          }
          if member.state == "active" {
            action(
              member.role == "moderator" ? "Step down as moderator" : "Appoint section moderator",
              member: member, action: member.role == "moderator" ? "demote" : "promote")
          }
          action("Remove section access", member: member, action: "remove")
        } label: {
          Image(systemName: "ellipsis.circle").frame(width: 48, height: 48)
        }
        .disabled(board.busy).accessibilityLabel("Manage \(member.displayName)")
      }
    }
  }
  private func action(_ title: String, member: ClubMember, action: String) -> some View {
    Button(title) {
      changingMember = member
      memberAction = action
    }
  }
}

struct ClubInvitePicker: View {
  let board: ClubSectionStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var query = ""
  private var people: [ChapterPerson] {
    let already = Set(
      board.members.filter { ["active", "requested", "invited"].contains($0.state) }.map(\.id))
    return board.community.people.filter {
      !already.contains($0.id)
        && (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query))
    }
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            "An invitation offers access; the member must accept before reading section content. No email or push is sent in this build."
          )
          TextField("Find a chapter member", text: $query)
        }
        if let error = board.error ?? board.community.error {
          Section { Text(error).foregroundStyle(Heritage.brass) }
        }
        Section("Available chapter members") {
          ForEach(people) { person in
            Button(person.displayName) {
              Task {
                await board.memberAction(person.id, action: "invite")
                if board.members.contains(where: { $0.id == person.id && $0.state == "invited" }) {
                  dismiss()
                }
              }
            }.frame(minHeight: 44).disabled(board.busy)
          }
          if people.isEmpty { Text("No matching members available to invite.") }
        }
      }.navigationTitle("Invite to section")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task { await board.community.refreshPeople() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { dismiss() } }
        .onChange(of: board.community.isVerified) { _, verified in if !verified { dismiss() } }
    }.preferredColorScheme(.dark).tint(Heritage.brass)
  }
}
