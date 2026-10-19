import SwiftUI

struct CommunicationsScreen: View {
  let community: CommunityStore
  let signIn: () -> Void
  @Environment(\.scenePhase) private var scenePhase
  @State private var showingPeople = false
  @State private var selectedConversation: ConversationSummary?

  var body: some View {
    ChapterScroll(refresh: community.refreshConversations) {
      ScreenHeading(
        eyebrow: "Keep the chapter close", title: "Stay connected.",
        message: "A conversation before the ride. A familiar voice along the way.")
      if community.isVerified {
        IntercomCard(community: community)
        NavigationLink(value: ChapterRoute.clubSections) {
          ChapterCard {
            HStack(spacing: 16) {
              Image(systemName: "person.3.sequence").font(.title2).foregroundStyle(Heritage.brass)
              VStack(alignment: .leading, spacing: 8) {
                Eyebrow("The clubhouse")
                Text("Community sections").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
                Text("Conversations, announcements & chapter polls.").font(.subheadline)
                  .foregroundStyle(Heritage.muted)
              }
              Spacer(minLength: 0)
              Image(systemName: "chevron.right").foregroundStyle(Heritage.brass)
            }
          }
        }.buttonStyle(.plain).accessibilityIdentifier("comms.sections")
        if let ride = community.activeRide {
          NavigationLink(value: ChapterRoute.liveRide) {
            ChapterCard {
              VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Your live ride")
                Text(ride.title).font(Heritage.cardTitle)
                Label(
                  community.location.isSharing ? "Position sharing on" : "Position sharing off",
                  systemImage: "location.circle")
                Label("Open ride map & check-ins", systemImage: "arrow.up.right")
              }.foregroundStyle(Heritage.brass)
            }
          }.buttonStyle(.plain).accessibilityIdentifier("comms.liveRide")
        }
        SectionHeading(title: "Messages", actionTitle: "New message") { showingPeople = true }
        if let error = community.error {
          ConnectionNotice(message: error) { Task { await community.refreshConversations() } }
        }
        if community.conversations.isEmpty && community.error == nil {
          EmptyChapterCard(
            symbol: "bubble.left.and.bubble.right", title: "Make yourself at home.",
            message: "The chapter conversation will appear here when connected.")
        }
        ForEach(community.conversations) { conversation in
          NavigationLink(value: ChapterRoute.conversation(conversation)) {
            ConversationRow(conversation: conversation)
          }.buttonStyle(.plain).accessibilityIdentifier("conversation.\(conversation.kind)")
        }
        Text(
          "Messages update while this screen is open. Push alerts and attachments are coming in a later build."
        )
        .font(.footnote).foregroundStyle(Heritage.muted)
      } else {
        if community.voice.isInSession {
          Text("Your explicitly started audio session is still open.").foregroundStyle(
            Heritage.brass)
          Button("Leave intercom") { Task { await community.leaveVoice() } }
            .buttonStyle(BrassButtonStyle()).accessibilityIdentifier("voice.leave")
        }
        if community.isSharingRequested {
          Button("Stop sharing my position") { community.stopSharing() }
            .buttonStyle(BrassButtonStyle()).accessibilityIdentifier("ride.sharing")
        }
        if community.isRemovingPosition, let notice = community.rideNotice {
          Text(notice).font(.footnote).foregroundStyle(Heritage.brass)
        }
        EmptyChapterCard(
          symbol: "lock.bubble", title: "Your chapter, privately.",
          message:
            "Verify your membership online to read conversations, speak to the chapter or join a live ride."
        )
        Button("Open membership", action: signIn).buttonStyle(BrassButtonStyle())
      }
      DevelopmentFooter()
    }
    .task(id: "\(scenePhase)-\(community.isVerified)") {
      guard scenePhase == .active, community.isVerified else { return }
      while !Task.isCancelled, community.isVerified {
        await community.refreshConversations()
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
      }
    }
    .sheet(isPresented: $showingPeople) {
      MemberMessagePicker(community: community) { selectedConversation = $0 }
    }
    .navigationDestination(item: $selectedConversation) { conversation in
      ConversationScreen(conversation: conversation, community: community)
    }
  }
}

struct ConversationRow: View {
  let conversation: ConversationSummary
  var body: some View {
    ChapterCard {
      HStack(alignment: .top, spacing: 14) {
        Image(
          systemName: conversation.kind == "direct"
            ? "person.crop.circle" : "bubble.left.and.bubble.right"
        )
        .font(.title2).foregroundStyle(Heritage.brass).frame(width: 32).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 8) {
          Text(conversation.title).font(.headline).foregroundStyle(Heritage.paper)
          Text(
            conversation.lastMessage.isEmpty ? "Start the conversation" : conversation.lastMessage
          )
          .font(.subheadline).foregroundStyle(Heritage.muted).lineLimit(2)
          if let date = conversation.lastAt {
            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
              .foregroundStyle(Heritage.muted)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
        if conversation.unread > 0 {
          Text("\(conversation.unread)").font(.caption.bold()).foregroundStyle(Heritage.ink)
            .padding(8).background(Heritage.brass, in: Circle()).accessibilityLabel(
              "\(conversation.unread) unread messages")
        }
      }
    }
  }
}

struct MemberMessagePicker: View {
  let community: CommunityStore
  let selected: (ConversationSummary) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var busy = false
  @State private var notice: String?
  private var people: [ChapterPerson] {
    community.people.filter {
      query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Message a member").font(Heritage.title)
          TextField("Find a chapter member", text: $query).textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("message.memberSearch")
          if let notice = notice ?? community.error {
            Text(notice).font(.footnote).foregroundStyle(Heritage.brass)
          }
          if people.isEmpty {
            Text("No matching active chapter members.").foregroundStyle(Heritage.muted)
          }
          ForEach(people) { person in
            HStack {
              Button {
                busy = true
                Task {
                  defer { busy = false }
                  do {
                    let conversation = try await community.direct(to: person)
                    dismiss()
                    selected(conversation)
                  } catch { notice = error.localizedDescription }
                }
              } label: {
                Label(
                  person.displayName,
                  systemImage: person.blocked ? "hand.raised" : "person.crop.circle"
                )
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
              }.disabled(busy || person.blocked).accessibilityIdentifier(
                "message.person.\(person.id)")
              if person.blocked {
                Button("Unblock") {
                  Task {
                    do { try await community.block(person.id, blocked: false) } catch {
                      notice = error.localizedDescription
                    }
                  }
                }.frame(minHeight: 44)
              }
            }.padding(.horizontal, 16).background(
              Heritage.panel, in: RoundedRectangle(cornerRadius: 12))
          }
        }.padding(24)
      }.background(Heritage.ink).foregroundStyle(Heritage.paper)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task { await community.refreshPeople() }
    }.preferredColorScheme(.dark).tint(Heritage.brass)
  }
}

struct ConversationScreen: View {
  let community: CommunityStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var thread: ChatThread
  @State private var reporting: ChapterMessage?
  @State private var reason = ""
  @State private var notice: String?

  init(conversation: ConversationSummary, community: CommunityStore) {
    self.community = community
    _thread = State(initialValue: ChatThread(conversation: conversation, community: community))
  }

  var body: some View {
    VStack(spacing: 0) {
      if community.isVerified {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
              if thread.hasOlder {
                Button(thread.isLoadingOlder ? "Loading…" : "Earlier messages") {
                  Task { await thread.older() }
                }
                .frame(maxWidth: .infinity, minHeight: 44).disabled(thread.isLoadingOlder)
              }
              if thread.messages.isEmpty {
                EmptyChapterCard(
                  symbol: "bubble.left", title: "Pull up a chair.",
                  message: thread.conversation.kind == "direct"
                    ? "Send a message to \(thread.conversation.title)."
                    : "Start the conversation with the chapter.")
              }
              ForEach(thread.messages) { message in
                MessageBubble(message: message, isOwn: message.senderID == community.memberID)
                  .id(message.id)
                  .contextMenu {
                    if message.senderID == community.memberID && !message.deleted {
                      Button("Remove my message", role: .destructive) {
                        Task { await thread.remove(message) }
                      }
                    } else if !message.deleted {
                      Button("Report message") {
                        reporting = message
                        reason = ""
                      }
                    }
                  }
              }
              Color.clear.frame(height: 1).id("latest")
            }.padding(24)
          }
          .onChange(of: thread.messages.last?.id, initial: true) { _, _ in
            proxy.scrollTo("latest", anchor: .bottom)
          }
        }
        if let error = notice ?? thread.error {
          Text(error).font(.footnote).foregroundStyle(Heritage.brass).padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        HStack(alignment: .bottom, spacing: 12) {
          TextField("Write a message", text: $thread.draft, axis: .vertical)
            .lineLimit(1...5).padding(12).background(
              Heritage.panel, in: RoundedRectangle(cornerRadius: 12)
            )
            .accessibilityIdentifier("message.composer")
          Button {
            Task { await thread.send() }
          } label: {
            Image(systemName: thread.isSending ? "hourglass" : "arrow.up").font(.headline).frame(
              width: 48, height: 48
            )
            .foregroundStyle(Heritage.ink).background(Heritage.brass, in: Circle())
          }.buttonStyle(.plain).disabled(
            thread.isSending || CommunityInput.message(thread.draft) == nil
          )
          .accessibilityLabel(thread.isSending ? "Sending message" : "Send message")
          .accessibilityIdentifier("message.send")
        }.padding(.horizontal, 20).padding(.vertical, 14).background(Heritage.ink)
      } else {
        ContentUnavailableView(
          "Connect to your chapter", systemImage: "lock.bubble",
          description: Text("Messages require an online membership check."))
      }
    }.background(Heritage.ink).foregroundStyle(Heritage.paper)
      .navigationTitle(thread.conversation.title).navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .toolbarBackground(Heritage.ink, for: .navigationBar).toolbarBackground(
        .visible, for: .navigationBar
      )
      .toolbar {
        if let other = thread.conversation.otherMemberID {
          ToolbarItem(placement: .primaryAction) {
            Menu {
              Button("Block direct messages", role: .destructive) {
                Task {
                  do {
                    try await community.block(other, blocked: true)
                    notice =
                      "Direct messages blocked. You can unblock this member from New message."
                  } catch { notice = error.localizedDescription }
                }
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }.accessibilityLabel("Conversation options")
          }
        }
      }
      .task(id: "\(scenePhase)-\(community.isVerified)") {
        guard scenePhase == .active, community.isVerified else {
          thread.clear()
          return
        }
        await thread.run()
      }
      .onChange(of: thread.draft) { _, text in
        community.saveDraft(text, for: thread.conversation.id)
      }
      .alert(
        "Report message",
        isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })
      ) {
        TextField("Reason for chapter review", text: $reason)
        Button("Cancel", role: .cancel) { reporting = nil }
        Button("Save report") {
          if let message = reporting {
            Task {
              await thread.report(message, reason: reason.isEmpty ? "Reported by member" : reason)
            }
          }
          reporting = nil
        }
      } message: {
        Text("The chapter can review this report. This does not send an urgent alert.")
      }
  }
}

struct MessageBubble: View {
  let message: ChapterMessage
  let isOwn: Bool
  var body: some View {
    HStack {
      if isOwn { Spacer(minLength: 38) }
      VStack(alignment: .leading, spacing: 8) {
        if !isOwn {
          Text(message.senderName).font(.caption.weight(.semibold)).foregroundStyle(Heritage.brass)
        }
        Text(message.deleted ? "Message removed" : message.body).foregroundStyle(
          message.deleted ? Heritage.muted : Heritage.paper
        )
        .textSelection(.enabled)
        Text(message.sentAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2)
          .foregroundStyle(Heritage.muted)
      }.padding(16).background(
        isOwn ? Color(hex: "323128") : Heritage.panel, in: RoundedRectangle(cornerRadius: 17))
      if !isOwn { Spacer(minLength: 38) }
    }.accessibilityElement(children: .combine)
  }
}

struct IntercomCard: View {
  let community: CommunityStore
  var eventID: String? = nil
  var body: some View {
    if community.isDemo { DemoIntercomPreviewCard() } else { liveBody }
  }
  @ViewBuilder private var liveBody: some View {
    let voice = community.voice
    ChapterCard {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Eyebrow("A voice on the road")
          Spacer()
          Image(systemName: voice.isConnected ? "waveform" : "headphones").foregroundStyle(
            Heritage.brass
          ).accessibilityHidden(true)
        }
        Text(
          voice.isInSession || voice.isBusy
            ? voice.title : eventID == nil ? "Chapter intercom." : "Ride intercom."
        )
        .font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
        Text(voice.status).foregroundStyle(Heritage.brass).accessibilityIdentifier("voice.status")
        if voice.isInSession {
          Text(
            voice.isConnected
              ? "\(voice.people.count + 1) connected · Use your paired headset or receiver."
              : "Audio is unavailable while the connection recovers. You can leave at any time."
          )
          .font(.subheadline).foregroundStyle(Heritage.muted)
          ForEach(voice.people) { person in
            Label(
              person.name + (person.speaking ? " · speaking" : ""),
              systemImage: person.speaking ? "waveform" : "person.circle"
            )
            .font(.subheadline).foregroundStyle(person.speaking ? Heritage.brass : Heritage.muted)
          }
          Toggle(
            "Push-to-talk",
            isOn: Binding(
              get: { voice.isPushToTalk },
              set: { enabled in Task { await voice.setPushToTalk(enabled) } })
          )
          .tint(Heritage.brass).foregroundStyle(Heritage.paper)
          if voice.isPushToTalk {
            Button {
            } label: {
              Text(voice.isPressingToTalk ? "Speaking · release to mute" : "Hold to speak").font(
                .headline
              ).foregroundStyle(Heritage.ink)
                .frame(maxWidth: .infinity, minHeight: 64).background(
                  Heritage.brass, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
              .onLongPressGesture(minimumDuration: .infinity, pressing: voice.pressToTalk) {}
              .accessibilityAddTraits(.isButton).accessibilityLabel("Push-to-talk")
              .accessibilityAction { Task { await voice.speakBriefly() } }
              .accessibilityIdentifier("voice.pushToTalk")
              .onDisappear { voice.pressToTalk(false) }
          } else {
            Button {
              Task { await voice.setMicrophone(!voice.isMicrophoneOn) }
            } label: {
              Label(
                voice.isMicrophoneOn ? "Mute microphone" : "Turn microphone on",
                systemImage: voice.isMicrophoneOn ? "mic.slash" : "mic")
            }.buttonStyle(BrassButtonStyle(outlined: !voice.isMicrophoneOn)).disabled(
              voice.isChangingMicrophone || (!voice.isConnected && !voice.isMicrophoneOn)
            )
            .accessibilityIdentifier("voice.microphone")
          }
          Text(
            "Your iPhone and headset manage audio routing and music levels. Set controls before moving."
          )
          .font(.caption).foregroundStyle(Heritage.muted)
          Button("Leave intercom") { Task { await community.leaveVoice() } }
            .buttonStyle(BrassButtonStyle(outlined: true)).accessibilityIdentifier("voice.leave")
          if let expiry = voice.expiresAt {
            Text(
              "Session ends at \(expiry.formatted(date: .omitted, time: .shortened)). Join again to continue."
            )
            .font(.caption).foregroundStyle(Heritage.muted)
          }
        } else {
          Text(
            "Join with your microphone off. Enable it when you choose to speak; leave to end the audio session."
          )
          .foregroundStyle(Heritage.muted).font(.subheadline)
          Button(voice.isBusy || community.isRequestingVoice ? "Connecting…" : "Join intercom") {
            Task { await community.joinVoice(eventID: eventID) }
          }
          .buttonStyle(BrassButtonStyle()).disabled(voice.isBusy || community.isRequestingVoice)
          .accessibilityIdentifier("voice.join")
        }
        if let error = voice.error { Text(error).font(.footnote).foregroundStyle(Heritage.brass) }
      }
    }
  }
}
