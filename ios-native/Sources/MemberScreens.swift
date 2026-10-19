import SwiftUI

struct MemberScreen: View {
  let store: ChapterStore
  @State private var signOutNotice: String?
  var body: some View {
    ChapterScroll(refresh: store.refresh) {
      ScreenHeading(
        eyebrow: "The clubhouse", title: store.isSignedIn ? "Your membership." : "You belong here.",
        message: store.isSignedIn
          ? "Your chapter card, connected to your membership."
          : "A little closer to the chapter. Activate your membership to carry your card and join the next ride."
      )
      if let member = store.member {
        MembershipCard(member: member).privacySensitive()
        Text(
          "Verified online \(member.verifiedAt.formatted(date: .abbreviated, time: .shortened)). This card shows your chapter record; it is not a payment receipt."
        )
        .font(.caption).foregroundStyle(Heritage.muted)
        ChapterCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Your ride plans").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
            Text(
              "\(member.rsvps.values.filter { $0 == .going }.count) going · \(member.rsvps.values.filter { $0 == .interested }.count) interested"
            )
            Text("You can update your response from any ride’s details.")
          }.foregroundStyle(Heritage.muted)
        }
      } else if store.isSignedIn {
        ConnectionNotice(
          message: store.memberError ?? "Connect to the chapter to verify your membership."
        ) {
          Task { await store.refreshMember() }
        }
        Text("Your member card is shown only after your membership is checked online.").font(
          .footnote
        ).foregroundStyle(Heritage.muted)
      } else {
        InvitationForm(store: store)
        if let url = ApprovedWebsite.link(URL(string: "https://wsmba.the-grange.uk/contact/")) {
          Link(destination: url) {
            Label("Speak to the chapter", systemImage: "arrow.up.right.square")
          }
          .buttonStyle(BrassButtonStyle(outlined: true))
        }
        Text(
          "Invitations expire after seven days. Your sign-in lasts up to 30 days. Ask the chapter for a new invitation when it ends. Activating a replacement invitation ends the previous device sign-in."
        )
        .font(.footnote).foregroundStyle(Heritage.muted).lineSpacing(4)
      }
      if store.isSignedIn {
        Button {
          Task { signOutNotice = await store.signOut() }
        } label: {
          Label("Sign out of this device", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .buttonStyle(BrassButtonStyle(outlined: true)).disabled(store.isBusy)
        if let signOutNotice { Text(signOutNotice).font(.footnote).foregroundStyle(.red) }
      }
      NavigationLink(value: ChapterRoute.privacy) {
        Label("Your privacy & app information", systemImage: "checkmark.shield")
      }
      .font(.subheadline).foregroundStyle(Heritage.brass).frame(minHeight: 44)
      NavigationLink(value: ChapterRoute.licences) {
        Label(
          "Open-source acknowledgements", systemImage: "chevron.left.forwardslash.chevron.right")
      }
      .font(.subheadline).foregroundStyle(Heritage.brass).frame(minHeight: 44)
      DevelopmentFooter()
    }.id(store.member != nil)
  }
}

struct InvitationForm: View {
  let store: ChapterStore
  @State private var code = ""
  @State private var isRevealed = false
  @State private var validationMessage: String?
  @FocusState private var isFocused: Bool

  var body: some View {
    ChapterCard {
      VStack(alignment: .leading, spacing: 20) {
        Image(systemName: "envelope.badge.shield.half.filled").font(.title).foregroundStyle(
          Heritage.brass
        ).accessibilityHidden(true)
        Text("Your invitation starts it.").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
        Text(
          "Paste the single-use invitation supplied privately by your chapter. New to the chapter? Get in touch first."
        )
        .foregroundStyle(Heritage.muted).lineSpacing(4)
        HStack {
          Group {
            if isRevealed {
              TextField("Chapter invitation", text: $code)
            } else {
              SecureField("Chapter invitation", text: $code)
            }
          }
          .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
          .textContentType(.oneTimeCode).submitLabel(.go).focused($isFocused)
          .onSubmit { activate() }.accessibilityIdentifier("member.invitation")
          .privacySensitive()
          Button {
            isRevealed.toggle()
          } label: {
            Image(systemName: isRevealed ? "eye.slash" : "eye").frame(width: 44, height: 44)
          }.accessibilityLabel(isRevealed ? "Hide invitation" : "Show invitation")
        }.padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 6)
          .background(Heritage.ink, in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(Heritage.line, lineWidth: 1))
        if let message = validationMessage ?? store.memberError {
          Text(message).font(.footnote).foregroundStyle(.red).accessibilityIdentifier(
            "member.error")
        }
        Button(action: activate) {
          HStack(spacing: 10) {
            if store.isBusy { ProgressView().tint(Heritage.ink) }
            Text(store.isBusy ? "Checking invitation…" : "Activate my membership")
          }.frame(maxWidth: .infinity)
        }.buttonStyle(BrassButtonStyle()).disabled(store.isBusy).accessibilityIdentifier(
          "member.activate")
      }
    }
  }

  private func activate() {
    guard ChapterStore.isValidInvitation(code) else {
      validationMessage = "Paste the complete invitation from your chapter."
      return
    }
    validationMessage = nil
    isFocused = false
    Task {
      await store.activate(code: code)
      if store.isSignedIn { code = "" }
    }
  }
}

struct MembershipCard: View {
  let member: MemberProfile
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(alignment: .top) {
        Image(systemName: "motorcycle").font(.title2).accessibilityHidden(true)
        Spacer(minLength: 16)
        Eyebrow("Member card")
      }.foregroundStyle(Heritage.brass)
      VStack(alignment: .leading, spacing: 9) {
        Text(member.displayName).font(Heritage.title).foregroundStyle(Heritage.paper)
        Text(member.chapter).foregroundStyle(Heritage.muted)
      }
      Label("Active \(member.membershipType)", systemImage: "checkmark.seal")
        .font(.subheadline.weight(.semibold)).foregroundStyle(Heritage.brass)
      Text("Member ID  \(member.id.prefix(8).uppercased())")
        .font(.system(.caption, design: .monospaced)).foregroundStyle(Heritage.muted)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
      .background(
        LinearGradient(
          colors: [Color(hex: "30363b"), Heritage.panel], startPoint: .topLeading,
          endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24)
      )
      .overlay(RoundedRectangle(cornerRadius: 24).stroke(Heritage.brass, lineWidth: 1))
      .accessibilityElement(children: .combine).accessibilityIdentifier("member.card")
  }
}

struct EventScreen: View {
  let event: ChapterEvent
  let store: ChapterStore
  @State private var notice: String?
  @State private var conversation: ConversationSummary?
  var body: some View {
    ChapterScroll(refresh: store.refresh) {
      Eyebrow("Ride together")
      Text(event.title).font(Heritage.hero).foregroundStyle(Heritage.paper).accessibilityAddTraits(
        .isHeader)
      Label(event.dateLabel, systemImage: "calendar").foregroundStyle(Heritage.paper)
      if !event.location.isEmpty {
        Label(event.location, systemImage: "mappin.and.ellipse").foregroundStyle(Heritage.muted)
      }
      Text(event.description).foregroundStyle(Heritage.paper).lineSpacing(6).textSelection(.enabled)
      ChapterCard {
        VStack(alignment: .leading, spacing: 16) {
          Text("Coming along?").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
          if store.member != nil && store.feed?.chapter.features.rsvp == true {
            Text(
              store.member?.rsvps[event.id].map { "Your response: \($0.title)" }
                ?? "Let the chapter know your plans."
            )
            .foregroundStyle(Heritage.muted)
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 8) { responseButtons }
              VStack(alignment: .leading, spacing: 10) { responseButtons }
            }
            if store.isBusy { ProgressView().tint(Heritage.brass) }
            if let notice {
              Text(notice).font(.footnote).foregroundStyle(Heritage.brass).accessibilityIdentifier(
                "rsvp.notice")
            }
          } else {
            Text(
              "Activate your membership in the Member tab to RSVP. Your sign-in must be verified online."
            )
            .foregroundStyle(Heritage.muted)
          }
        }
      }
      if let community = store.community, community.isVerified {
        ChapterCard {
          VStack(alignment: .leading, spacing: 16) {
            Text("Keep the ride together.").font(Heritage.cardTitle).foregroundStyle(Heritage.paper)
            Text(
              "RSVP Going or Interested for ride messages. Choose Going to join the live map and ride intercom."
            )
            .foregroundStyle(Heritage.muted)
            Button("Open ride conversation") {
              Task {
                do { conversation = try await community.rideConversation(event: event) } catch {
                  notice = error.localizedDescription
                }
              }
            }.buttonStyle(BrassButtonStyle(outlined: true)).accessibilityIdentifier(
              "ride.conversation")
            if community.activeRide?.eventID == event.id {
              NavigationLink(value: ChapterRoute.liveRide) {
                Label("Open live ride", systemImage: "map")
              }
              .buttonStyle(BrassButtonStyle()).accessibilityIdentifier("ride.openLive")
            } else {
              Button(community.isRideBusy ? "Joining…" : "Join live ride · sharing off") {
                Task { await community.join(event: event) }
              }.buttonStyle(BrassButtonStyle()).disabled(community.isRideBusy)
                .accessibilityIdentifier("ride.join")
            }
            if let rideNotice = community.rideNotice {
              Text(rideNotice).font(.footnote).foregroundStyle(Heritage.brass)
            }
          }
        }
      }
      if let url = ApprovedWebsite.link(event.url) {
        Link(destination: url) {
          Label("View on the chapter website", systemImage: "arrow.up.right.square")
        }
        .buttonStyle(BrassButtonStyle(outlined: true))
      }
    }.navigationTitle("Ride details").navigationBarTitleDisplayMode(.inline)
      .navigationDestination(item: $conversation) { value in
        if let community = store.community {
          ConversationScreen(conversation: value, community: community)
        }
      }
      .toolbarBackground(Heritage.ink, for: .navigationBar).toolbarBackground(
        .visible, for: .navigationBar)
  }

  private var responseButtons: some View {
    ForEach(RSVPResponse.allCases, id: \.self) { response in
      Button {
        Task {
          notice = await store.respond(to: event, with: response) ?? "Your RSVP has been saved."
        }
      } label: {
        Text(response.title)
      }
      .buttonStyle(BrassButtonStyle(outlined: store.member?.rsvps[event.id] != response))
      .disabled(store.isBusy).accessibilityIdentifier("rsvp.\(response.rawValue)")
      .accessibilityAddTraits(store.member?.rsvps[event.id] == response ? .isSelected : [])
    }
  }
}

struct PrivacyScreen: View {
  var body: some View {
    ReadingScreen(
      title: "Your chapter. Your privacy.", eyebrow: "App information",
      bodyText: """
        Public news and ride details are saved on this device for offline reading. Saved information can be out of date; pull down to refresh it.

        Your sign-in secret is kept in Apple Keychain, on this device, while it is unlocked. Your member card and RSVP record are checked with the chapter server and are not stored in the public offline cache.

        The chapter holds the name, email and membership details used to issue your invitation, your ride responses and an audit of account actions. This app provides access to your own membership and responses.

        Member conversations and direct messages are held on the chapter server. Only the participants can open direct messages through the app. Messages use transport encryption on the production HTTPS service; this build does not claim end-to-end encrypted messaging. You can remove your own messages, block direct messages and save a report for chapter review. There are no push alerts or attachments yet.

        Joining a live ride leaves location sharing off. You can opt in for that ride, with an iPhone permission prompt and a visible sharing control. Sharing can continue with the screen locked after you start it. Only active members who explicitly join the same ride can see positions. The server keeps one current fix, removes it on Stop, Home or Leave, and hides and purges fixes older than two minutes. No route history or home address is saved. A live ride session lasts up to four hours in this build.

        The LiveKit intercom runs on our chapter server. Joining starts with your microphone off. Permission and a separate microphone action are required to speak. Leaving closes the audio session. Audio is not recorded by this installation. Voice leases last at most one hour and active membership is rechecked by the server. Headset, locked-screen and cellular behaviour require physical-device trials.

        Ride Guardian escalation, SOS dispatch, automatic accident detection and confidential welfare services are not available in this build.

        Contact the chapter to correct your details, request deletion or discuss record retention. A server-verified sign-out revokes this device’s session.

        Native SwiftUI review build 0.5.0. This build has not been released through the App Store.
        """, website: URL(string: "https://wsmba.the-grange.uk/contact/"))
  }
}

struct LicencesScreen: View {
  private let notice: String = {
    guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return "Open-source notices are available in the project’s ThirdPartyNotices.txt file." }
    return text
  }()
  var body: some View {
    ReadingScreen(
      title: "Built with open source.", eyebrow: "Acknowledgements", bodyText: notice, website: nil)
  }
}
