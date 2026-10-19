import SwiftUI

private enum ClubPostPrompt: Identifiable {
  case removePost, reportPost
  case removeComment(Int)
  case reportComment(Int)
  var id: String {
    switch self {
    case .removePost: "remove-post"
    case .reportPost: "report-post"
    case .removeComment(let id): "remove-comment-\(id)"
    case .reportComment(let id): "report-comment-\(id)"
    }
  }
  var isRemoval: Bool {
    switch self {
    case .removePost, .removeComment: true
    default: false
    }
  }
}

struct ClubPostScreen: View {
  let community: CommunityStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var thread: ClubPostStore
  @State private var prompt: ClubPostPrompt?
  @State private var closingPoll = false
  init(sectionID: String, postID: String, community: CommunityStore) {
    self.community = community
    _thread = State(
      initialValue: ClubPostStore(sectionID: sectionID, postID: postID, community: community))
  }
  var body: some View {
    ChapterScroll(refresh: thread.refresh) {
      if community.isVerified, let post = thread.post {
        ScreenHeading(
          eyebrow: post.kindLabel, title: post.title,
          message:
            "\(post.author) · \(post.createdAt.formatted(date: .abbreviated, time: .shortened))")
        if let notice = thread.notice {
          Text(notice).font(.footnote).foregroundStyle(Heritage.brass).accessibilityIdentifier(
            "section.post.notice")
        }
        if let error = thread.error { Text(error).foregroundStyle(Heritage.brass) }
        if !post.body.isEmpty {
          Text(post.body).font(.body).lineSpacing(6).foregroundStyle(Heritage.paper).textSelection(
            .enabled)
        }
        if post.kind == "poll", !post.removed { poll(post) }
        if !post.removed {
          Text("Conversation").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
          if thread.hasOlder {
            Button("Earlier comments") { Task { await thread.older() } }.disabled(thread.busy)
              .frame(minHeight: 48)
          }
          if thread.comments.isEmpty {
            Text("Add the first comment.").foregroundStyle(Heritage.muted)
          }
          ForEach(thread.comments) { comment in
            ChapterCard {
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Text(comment.author).font(.subheadline.bold())
                  Spacer()
                  Text(comment.createdAt.formatted(date: .omitted, time: .shortened)).font(.caption)
                    .foregroundStyle(Heritage.muted)
                }
                Text(comment.removed ? "Comment removed" : comment.body).foregroundStyle(
                  comment.removed ? Heritage.muted : Heritage.paper
                ).textSelection(.enabled)
              }
            }.contextMenu {
              if !comment.removed {
                if comment.authorID == community.memberID || thread.section?.canModerate == true {
                  Button("Remove comment", role: .destructive) {
                    prompt = .removeComment(comment.id)
                  }
                }
                Button("Report to section moderators") { prompt = .reportComment(comment.id) }
              }
            }
          }
          if thread.section?.canPost == true { composer }
        }
      } else {
        EmptyChapterCard(
          symbol: "lock.bubble", title: "Connect to this conversation.",
          message: thread.error ?? "Section content needs a current online membership check.")
        Button("Try again") { Task { await thread.refresh() } }.buttonStyle(
          BrassButtonStyle(outlined: true))
      }
    }.navigationTitle("Clubhouse conversation").clubNavigation()
      .toolbar {
        if let post = thread.post, !post.removed, thread.section?.canPost == true {
          ToolbarItem(placement: .primaryAction) {
            Menu {
              if thread.section?.canModerate == true {
                Button(post.pinned ? "Unpin post" : "Pin post") {
                  Task {
                    _ = await thread.mutate(
                      "/actions",
                      body: try? JSONEncoder().encode(["action": post.pinned ? "unpin" : "pin"]))
                  }
                }
                if post.kind == "poll" && post.pollOpen {
                  Button("Close poll") { closingPoll = true }
                }
              }
              if post.authorID == community.memberID || thread.section?.canModerate == true {
                Button("Remove post", role: .destructive) { prompt = .removePost }
              }
              Button("Report to section moderators") { prompt = .reportPost }
            } label: {
              Image(systemName: "ellipsis.circle")
            }.accessibilityLabel("Post options")
          }
        }
      }
      .task(id: "\(scenePhase)-\(community.isVerified)") {
        if scenePhase == .active && community.isVerified {
          await thread.refresh()
        } else {
          thread.clear()
          prompt = nil
          closingPoll = false
        }
      }
      .sheet(item: $prompt) { item in
        ClubReasonSheet(
          title: item.isRemoval ? "Remove content" : "Report to moderators",
          explanation: item.isRemoval
            ? "The text will be erased from live records and a removal marker left in the conversation. A reason is recorded in the section activity log."
            : "This report is saved for this section’s moderators. It does not send an urgent alert. Contact the chapter directly about urgent concerns.",
          failure: { thread.error }
        ) { reason in
          switch item {
          case .removePost:
            return await thread.mutate(
              "/actions", body: try? JSONEncoder().encode(["action": "remove", "reason": reason]))
          case .removeComment(let id):
            return await thread.mutate(
              "/comments/\(id)/remove", body: try? JSONEncoder().encode(["reason": reason]))
          case .reportPost, .reportComment:
            struct Body: Encodable {
              let reason: String
              let commentID: Int?
            }
            let commentID: Int? = if case .reportComment(let id) = item { id } else { nil }
            return await thread.mutate(
              "/reports",
              body: try? APICoding.encoder().encode(Body(reason: reason, commentID: commentID)),
              message: "Report saved for section moderators. It has not yet been reviewed.")
          }
        }
      }
      .confirmationDialog("Close this poll?", isPresented: $closingPoll, titleVisibility: .visible)
    {
      Button("Close poll") {
        Task {
          _ = await thread.mutate("/actions", body: try? JSONEncoder().encode(["action": "close"]))
        }
      }
    } message: {
      Text(
        "The final totals remain visible. Members will no longer be able to vote, change or withdraw their choice."
      )
    }
  }
  private var composer: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("Add a comment", text: $thread.draft, axis: .vertical).lineLimit(2...6).padding(14)
        .background(Heritage.panel, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier(
          "section.comment.body")
      Button(thread.busy ? "Sending…" : "Post comment", systemImage: "arrow.up.bubble") {
        Task { await thread.comment() }
      }
      .buttonStyle(BrassButtonStyle()).disabled(
        thread.busy || ClubInput.text(thread.draft, limit: 2000) == nil
      ).accessibilityIdentifier("section.comment.send")
    }
  }
  private func poll(_ post: ClubPost) -> some View {
    ChapterCard {
      VStack(alignment: .leading, spacing: 16) {
        Eyebrow(post.pollOpen ? "Have your say" : "Final totals")
        ForEach(post.options) { option in
          Button {
            Task {
              _ = await thread.mutate(
                "/vote", method: "PUT", body: try? JSONEncoder().encode(["option_id": option.id]),
                message: "Your choice is confirmed by the section.")
            }
          } label: {
            HStack(spacing: 12) {
              Image(systemName: post.myVote == option.id ? "checkmark.circle.fill" : "circle")
              Text(option.title).frame(maxWidth: .infinity, alignment: .leading)
              Text("\(option.votes)").monospacedDigit()
            }.foregroundStyle(post.myVote == option.id ? Heritage.brass : Heritage.paper).padding(
              14
            ).frame(minHeight: 50).background(Heritage.ink, in: RoundedRectangle(cornerRadius: 12))
          }.buttonStyle(.plain).disabled(
            thread.busy || !post.pollOpen || thread.section?.canPost != true
          )
          .accessibilityLabel(
            "\(option.title), \(option.votes) votes\(post.myVote == option.id ? ", your choice" : "")"
          )
          .accessibilityIdentifier("section.vote.\(option.id)")
        }
        if post.myVote != nil && post.pollOpen && thread.section?.canPost == true {
          Button("Withdraw my choice") {
            Task {
              _ = await thread.mutate(
                "/vote", method: "DELETE", message: "Your choice has been withdrawn.")
            }
          }.frame(minHeight: 44).disabled(thread.busy)
        }
        if let closes = post.closesAt {
          Text(
            "\(post.pollOpen ? "Closes" : "Closing time") · \(closes.formatted(date: .abbreviated, time: .shortened))"
          ).font(.footnote).foregroundStyle(Heritage.muted)
        }
        Text(
          "One choice per member. Totals are visible; vote identities are held on the server. This is an informal chapter poll, not a secret or binding ballot."
        ).font(.footnote).foregroundStyle(Heritage.muted)
      }
    }
  }
}

struct ClubReasonSheet: View {
  let title: String
  let explanation: String
  let failure: () -> String?
  let submit: (String) async -> Bool
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var reason = ""
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Form {
        Section { Text(explanation) }
        Section("Reason / outcome") {
          TextField("Describe the reason", text: $reason, axis: .vertical).lineLimit(4...8)
        }
        if let error { Section { Text(error).foregroundStyle(Heritage.brass) } }
      }.navigationTitle(title)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button(busy ? "Saving…" : "Save") {
              busy = true
              Task {
                defer { busy = false }
                if await submit(reason) {
                  dismiss()
                } else {
                  error =
                    failure() ?? "The chapter could not confirm this action. Please try again."
                }
              }
            }.disabled(busy || ClubInput.text(reason, limit: 500).map { $0.count >= 5 } != true)
          }
        }.onChange(of: scenePhase) { _, phase in if phase != .active { dismiss() } }
    }.preferredColorScheme(.dark).tint(Heritage.brass)
  }
}
