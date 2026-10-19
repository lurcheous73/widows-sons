import SwiftUI

struct ClubhouseDirectoryScreen: View {
  let community: CommunityStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var directory: ClubhouseDirectoryStore
  @State private var creating = false
  init(community: CommunityStore) {
    self.community = community
    _directory = State(initialValue: ClubhouseDirectoryStore(community: community))
  }
  var body: some View {
    ChapterScroll(refresh: directory.refresh) {
      ScreenHeading(
        eyebrow: "The clubhouse", title: "Find your people.",
        message:
          "Optional chapter groups. A place for conversation, shared plans and a little banter.")
      if community.isVerified {
        if directory.canCreate {
          Button("Create a section", systemImage: "plus.circle") { creating = true }
            .buttonStyle(BrassButtonStyle(outlined: true)).accessibilityIdentifier(
              "sections.create")
        }
        if let error = directory.error {
          ConnectionNotice(message: error) { Task { await directory.refresh() } }
        }
        if directory.sections.isEmpty && directory.error == nil {
          EmptyChapterCard(
            symbol: "person.3", title: "Room for everyone.",
            message:
              "Chapter sections will appear here when enabled. Invitation-only groups appear after you are invited."
          )
        }
        ForEach(directory.sections) { section in
          NavigationLink(value: ChapterRoute.clubSection(section.id)) {
            ChapterCard {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Eyebrow(section.membership == "invited" ? "You are invited" : section.accessLabel)
                  Spacer()
                  Image(systemName: section.joinPolicy == "invite" ? "lock" : "person.3")
                    .foregroundStyle(Heritage.brass)
                }
                Text(section.title).font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
                if !section.description.isEmpty {
                  Text(section.description).foregroundStyle(Heritage.muted).lineLimit(3)
                }
                Label(
                  section.state == "active" ? section.membershipLabel : section.state.capitalized,
                  systemImage: section.membership == "active"
                    ? "checkmark.circle" : "arrow.right.circle"
                ).font(.subheadline).foregroundStyle(Heritage.brass)
              }
            }
          }.buttonStyle(.plain).accessibilityIdentifier("section.\(section.id)")
        }
        Text(
          "Joining is always your choice. Section membership lists are available only to that section’s moderators. Pull down to check for updates."
        ).font(.footnote).foregroundStyle(Heritage.muted)
      } else {
        EmptyChapterCard(
          symbol: "lock", title: "A private chapter space.",
          message: "Verify membership online to discover and join chapter sections.")
      }
    }.navigationTitle("Community sections").clubNavigation()
      .task(id: "\(scenePhase)-\(community.isVerified)") {
        if scenePhase == .active && community.isVerified {
          await directory.refresh()
        } else {
          directory.clear()
          creating = false
        }
      }
      .sheet(isPresented: $creating, onDismiss: reload) {
        ClubSectionEditor(community: community, original: nil)
      }
  }
  private func reload() {
    guard scenePhase == .active, community.isVerified else { return }
    Task { await directory.refresh() }
  }

}

struct ClubSectionScreen: View {
  let community: CommunityStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var board: ClubSectionStore
  @State private var composing = false
  @State private var configuring = false
  @State private var leaving = false
  init(id: String, community: CommunityStore) {
    self.community = community
    _board = State(initialValue: ClubSectionStore(id: id, community: community))
  }
  var body: some View {
    ChapterScroll(refresh: board.refresh) {
      if community.isVerified, let section = board.section {
        ScreenHeading(
          eyebrow: section.accessLabel, title: section.title, message: section.description)
        Label(
          section.membershipLabel,
          systemImage: section.role == "moderator"
            ? "person.badge.shield.checkmark" : "person.crop.circle"
        ).foregroundStyle(Heritage.brass)
        if section.state != "active" {
          Text(
            section.state == "paused"
              ? "This section is paused. Content is unavailable until it reopens."
              : "This section is archived. Existing members can read it; new posts and votes are closed."
          ).foregroundStyle(Heritage.muted)
        }
        if let error = board.error {
          ConnectionNotice(message: error) { Task { await board.refresh() } }
        }
        if let notice = board.notice {
          Text(notice).font(.footnote).foregroundStyle(Heritage.brass).accessibilityIdentifier(
            "section.notice")
        }
        if section.canRead {
          if section.canPost {
            Button("Start a conversation", systemImage: "square.and.pencil") { composing = true }
              .buttonStyle(BrassButtonStyle()).accessibilityIdentifier("section.compose")
          }
          if section.canModerate {
            NavigationLink(value: ChapterRoute.clubModeration(section.id)) {
              Label("Members & moderation", systemImage: "person.badge.shield.checkmark")
            }.buttonStyle(BrassButtonStyle(outlined: true)).accessibilityIdentifier(
              "section.moderation")
          }
          if board.posts.isEmpty {
            EmptyChapterCard(
              symbol: "bubble.left.and.bubble.right", title: "Pull up a chair.",
              message: "The first conversation starts with you.")
          }
          ForEach(board.posts.filter(\.pinned)) { item in postLink(item) }
          ForEach(board.posts.filter { !$0.pinned }) { item in postLink(item) }
          if board.hasOlder {
            Button("Earlier posts") { Task { await board.older() } }.frame(minHeight: 48).disabled(
              board.busy)
          }
        } else if section.state == "active" {
          membershipCard(section)
        }
        if section.canConfigure {
          Button("Section settings", systemImage: "slider.horizontal.3") { configuring = true }
            .buttonStyle(BrassButtonStyle(outlined: true)).accessibilityIdentifier(
              "section.settings")
        }
        if ["active", "invited", "requested"].contains(section.membership) {
          Button(
            section.membership == "active" ? "Leave section" : "Decline / withdraw access",
            role: .destructive
          ) { leaving = true }.frame(minHeight: 48)
        }
        Text(
          "Section conversations stay in the clubhouse. Ride controls and intercom remain in Rides and Comms."
        ).font(.footnote).foregroundStyle(Heritage.muted)
      } else {
        EmptyChapterCard(
          symbol: "lock", title: "Connect to this section.",
          message: board.error ?? "Section content requires a current online membership check.")
        Button("Try again") { Task { await board.refresh() } }.buttonStyle(
          BrassButtonStyle(outlined: true))
      }
    }.navigationTitle(board.section?.title ?? "Chapter section").clubNavigation()
      .task(id: "\(scenePhase)-\(community.isVerified)") {
        if scenePhase == .active && community.isVerified {
          await board.refresh()
        } else {
          board.clear()
          composing = false
          configuring = false
          leaving = false
        }
      }
      .sheet(isPresented: $composing, onDismiss: reload) {
        ClubPostComposer(board: board)
      }
      .sheet(isPresented: $configuring, onDismiss: reload) {
        if let section = board.section {
          ClubSectionEditor(community: community, original: section)
        }
      }
      .confirmationDialog("Leave this section?", isPresented: $leaving, titleVisibility: .visible) {
        Button("Leave / decline", role: .destructive) {
          Task {
            _ = await board.mutate(
              "/membership", method: "DELETE", message: "Section access ended.")
          }
        }
      } message: {
        Text(
          "Your earlier posts, comments and poll choice remain on the chapter server. You will lose access to private content. The last moderator must appoint a replacement first."
        )
      }
  }
  private func reload() {
    guard scenePhase == .active, community.isVerified else { return }
    Task { await board.refresh() }
  }
  private func postLink(_ item: ClubPost) -> some View {
    NavigationLink(value: ChapterRoute.clubPost(sectionID: board.id, postID: item.id)) {
      ClubPostCard(post: item)
    }.buttonStyle(.plain).accessibilityIdentifier("section.post.\(item.id)")
  }
  private func membershipCard(_ section: ClubSection) -> some View {
    ChapterCard {
      VStack(alignment: .leading, spacing: 14) {
        Text(
          section.membership == "invited" ? "A place is waiting for you." : "Make yourself at home."
        ).font(Heritage.cardTitle)
        Text(
          section.membership == "requested"
            ? "A section moderator will review your request. Content remains private until approved."
            : "Join explicitly to read and contribute. Only section moderators see the membership list."
        ).foregroundStyle(Heritage.muted)
        if !["requested", "removed"].contains(section.membership) {
          Button(
            section.membership == "invited"
              ? "Accept invitation"
              : section.joinPolicy == "open" ? "Join section" : "Request to join"
          ) {
            Task {
              _ = await board.mutate(
                "/join",
                message: section.joinPolicy == "approval" && section.membership != "invited"
                  ? "Request saved for section review." : "You have joined the section.")
            }
          }.buttonStyle(BrassButtonStyle()).disabled(board.busy).accessibilityIdentifier(
            "section.join")
        }
      }.foregroundStyle(Heritage.paper)
    }
  }
}

struct ClubPostCard: View {
  let post: ClubPost
  var body: some View {
    ChapterCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Eyebrow(post.kindLabel)
          Spacer()
          if post.pinned {
            Image(systemName: "pin.fill").foregroundStyle(Heritage.brass).accessibilityLabel(
              "Pinned")
          }
        }
        Text(post.title).font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
        if !post.body.isEmpty { Text(post.body).foregroundStyle(Heritage.muted).lineLimit(3) }
        HStack {
          Text(post.author)
          Spacer()
          Label("\(post.commentCount)", systemImage: "bubble.right")
        }.font(.caption).foregroundStyle(Heritage.muted)
        Text(post.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
          .foregroundStyle(Heritage.muted)
        if post.kind == "poll" && !post.removed {
          Text(post.pollOpen ? "Have your say" : "Poll closed").font(.subheadline.weight(.semibold))
            .foregroundStyle(Heritage.brass)
        }
      }
    }
  }
}

struct ClubSectionEditor: View {
  let community: CommunityStore
  let original: ClubSection?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var title: String
  @State private var description: String
  @State private var policy: String
  @State private var status: String
  @State private var busy = false
  @State private var error: String?
  @State private var confirmChange = false
  @State private var clientID = UUID()
  init(community: CommunityStore, original: ClubSection?) {
    self.community = community
    self.original = original
    // These fields intentionally begin as a one-time editable snapshot.
    _title = State(initialValue: original?.title ?? "")
    _description = State(initialValue: original?.description ?? "")
    _policy = State(initialValue: original?.joinPolicy ?? "approval")
    _status = State(initialValue: original?.state ?? "active")
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Section identity") {
          TextField("Section name", text: $title).accessibilityIdentifier("section.edit.title")
          TextField("What brings this group together?", text: $description, axis: .vertical)
            .lineLimit(3...8)
        }
        Section("Access") {
          Picker("Joining", selection: $policy) {
            Text("Chapter members may join").tag("open")
            Text("Moderator approval").tag("approval")
            Text("Invitation only").tag("invite")
          }
          Picker("Availability", selection: $status) {
            Text("Active").tag("active")
            Text("Paused — hide content").tag("paused")
            Text("Archived — read only").tag("archived")
          }
          Text(
            original == nil
              ? "Creating this section explicitly joins you as its first moderator. No one else is added automatically."
              : "Changing access can allow more chapter members to discover or join this section. The change is recorded in the section activity log."
          ).font(.footnote)
          Text(
            "These are ordinary community groups. Confidential Almoner support needs its own protected service."
          ).font(.footnote)
        }
        if let error { Section { Text(error).foregroundStyle(Heritage.brass) } }
      }.navigationTitle(original == nil ? "New section" : "Section settings")
        .safeAreaInset(edge: .bottom) {
          ClubEditorActions(
            title: busy ? "Saving…" : "Save",
            enabled: !busy && ClubInput.text(title, limit: 100) != nil
              && ClubInput.text(description, limit: 2000, allowEmpty: true) != nil,
            busy: busy, identifier: "section.edit.save", cancel: { dismiss() }
          ) {
            if original != nil && (policy != original?.joinPolicy || status != original?.state) {
              confirmChange = true
            } else {
              Task { await save() }
            }
          }
        }
        .confirmationDialog(
          "Change section access?", isPresented: $confirmChange, titleVisibility: .visible
        ) {
          Button("Save access change") { Task { await save() } }
        } message: {
          Text(
            "Members may gain or lose access according to the new joining policy and availability. Existing memberships remain in place. This change will be audited."
          )
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { dismiss() } }
        .onChange(of: community.isVerified) { _, verified in if !verified { dismiss() } }
    }.preferredColorScheme(.dark).tint(Heritage.brass)
  }
  private func save() async {
    busy = true
    defer { busy = false }
    struct Body: Encodable {
      let clientID: UUID
      let title: String
      let description: String
      let joinPolicy: String
      let state: String
      let revision: Int
    }
    do {
      let suffix = try original.map { "/" + (try CommunityInput.pathID($0.id)) } ?? ""
      _ = try await community.request(
        path: "sections" + suffix, method: original == nil ? "POST" : "PUT",
        body: APICoding.encoder().encode(
          Body(
            clientID: clientID, title: title, description: description, joinPolicy: policy,
            state: status,
            revision: original?.revision ?? 0)))
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

private struct ClubDraftOption: Identifiable {
  let id = UUID()
  var title = ""
}

struct ClubPostComposer: View {
  let board: ClubSectionStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var draft = ClubPostDraft()
  @State private var options = [ClubDraftOption(), ClubDraftOption()]
  @State private var closing = Date.now.addingTimeInterval(7 * 86400)
  private var payload: ClubPostDraft {
    var result = draft
    if draft.kind == "poll" {
      result.options = options.map(\.title)
      result.closesAt = closing
    }
    return result
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Post type") {
          Picker("Type", selection: $draft.kind) {
            Text("Discussion").tag("discussion")
            Text("Poll").tag("poll")
            if board.section?.canModerate == true { Text("Announcement").tag("announcement") }
          }
        }
        Section("Start the conversation") {
          TextField(draft.kind == "poll" ? "Poll question" : "Title", text: $draft.title)
            .accessibilityIdentifier("section.post.title")
          TextField("Your post", text: $draft.body, axis: .vertical).lineLimit(5...12)
            .accessibilityIdentifier("section.post.body")
        }
        if draft.kind == "poll" {
          Section("Choices") {
            ForEach($options) { $option in TextField("Poll option", text: $option.title) }
            if options.count < 8 { Button("Add option") { options.append(ClubDraftOption()) } }
            if options.count > 2 { Button("Remove last option") { options.removeLast() } }
            DatePicker(
              "Closes", selection: $closing, in: Date.now...Date.now.addingTimeInterval(89 * 86400))
            Text(
              "One choice per member. Members can change or withdraw it before closing. Totals are visible; identities are held on the server. This is an informal poll, not a secret or binding ballot."
            ).font(.footnote)
          }
        }
        if let error = board.error { Section { Text(error).foregroundStyle(Heritage.brass) } }
      }.navigationTitle("New chapter post")
        .safeAreaInset(edge: .bottom) {
          ClubEditorActions(
            title: board.busy ? "Sending…" : "Publish", enabled: !board.busy && payload.isValid,
            busy: board.busy, identifier: "section.post.publish", cancel: { dismiss() }
          ) {
            Task { if await board.publish(payload) { dismiss() } }
          }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { dismiss() } }
        .onChange(of: board.community.isVerified) { _, verified in if !verified { dismiss() } }
    }.preferredColorScheme(.dark).tint(Heritage.brass)
  }
}

extension View {
  func clubNavigation() -> some View {
    self.navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
      .toolbarBackground(Heritage.ink, for: .navigationBar).toolbarBackground(
        .visible, for: .navigationBar)
  }
}

struct ClubEditorActions: View {
  let title: String
  let enabled: Bool
  let busy: Bool
  let identifier: String
  let cancel: () -> Void
  let save: () -> Void
  var body: some View {
    HStack(spacing: 16) {
      Button("Cancel", action: cancel).buttonStyle(BrassButtonStyle(outlined: true)).disabled(busy)
      Spacer(minLength: 0)
      Button(title, action: save).buttonStyle(BrassButtonStyle()).disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }.padding(.horizontal, 20).padding(.vertical, 12).background(Heritage.ink)
  }
}
