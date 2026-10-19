import AVFAudio
import CarPlay
import Foundation
import UIKit

/// Communication-category templates only. No message bodies, private notes,
/// custom map, settings forms or account setup appear on the vehicle display.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private weak var interfaceController: CPInterfaceController?
  private var refreshTask: Task<Void, Never>?
  private let intercom = CPListTemplate(title: "Intercom", sections: [])
  private let messages = CPListTemplate(title: "Messages", sections: [])
  private var store: ChapterStore? { AppRuntime.shared.store }
  private var community: CommunityStore? { store?.community }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    CommunicationAppDelegate.continueCall(userActivity)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    VehicleConnection.shared.setConnected(true)
    intercom.tabTitle = "Intercom"
    intercom.tabImage = UIImage(systemName: "waveform")
    messages.tabTitle = "Messages"
    messages.tabImage = UIImage(systemName: "bubble.left.and.bubble.right")
    let root = CPTabBarTemplate(templates: [intercom, messages])
    interfaceController.setRootTemplate(root, animated: false, completion: nil)
    render()
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      guard let self else { return }
      await self.store?.loadOrRefresh()
      while !Task.isCancelled, self.interfaceController != nil {
        await self.store?.refreshMember()
        if self.community?.isVerified == true {
          await self.community?.refreshConversations()
          await self.community?.refreshDuty()
        }
        self.render()
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
      }
    }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    refreshTask?.cancel()
    refreshTask = nil
    self.interfaceController = nil
    VehicleConnection.shared.setConnected(false)
    if let voice = community?.voice { Task { await voice.setMicrophone(false) } }
    if UIApplication.shared.applicationState != .active { store?.invalidateVerification() }
    // Disconnecting the display does not silently end a deliberately started
    // intercom or sharing lease. Both keep their visible stop/expiry controls.
  }

  private func item(
    _ text: String, detail: String? = nil, enabled: Bool = true,
    action: (@MainActor () async -> Void)? = nil
  ) -> CPListItem {
    let row = CPListItem(text: text, detailText: detail)
    row.isEnabled = enabled && action != nil
    if let action {
      row.handler = { [weak self] _, complete in
        Task { @MainActor in
          await action()
          self?.render()
          complete()
        }
      }
    }
    return row
  }

  private func render() {
    guard let community, community.isVerified else {
      intercom.updateSections([
        CPListSection(items: [
          item("Membership check required", detail: "Sign in when it is safe to do so.")
        ])
      ])
      messages.updateSections([
        CPListSection(items: [
          item("Messages unavailable", detail: "A current chapter connection is required.")
        ])
      ])
      if let community {
        var stopControls: [CPListItem] = [
          item("Membership check required", detail: "Sign in when it is safe to do so.")
        ]
        if community.voice.isInSession {
          stopControls.append(item("Leave intercom") { await community.leaveVoice() })
        }
        if community.isSharingRequested {
          stopControls.append(item("Stop position sharing") { community.stopSharing() })
        }
        intercom.updateSections([CPListSection(items: stopControls)])
      }
      return
    }
    let voice = community.voice
    var audio: [CPListItem] = []
    if voice.isInSession {
      audio.append(
        item(
          voice.isConnected
            ? "\(voice.people.count + 1) connected" : "Connection lost · audio unavailable",
          detail: voice.title))
      if voice.isMicrophoneOn {
        audio.append(
          item("Mute microphone", detail: "Microphone is on") { await voice.setMicrophone(false) })
      } else {
        audio.append(
          item(
            "Speak for up to 30 seconds", detail: "Microphone is off",
            enabled: voice.isConnected && !voice.isChangingMicrophone
          ) { [weak self] in
            guard AVAudioApplication.shared.recordPermission == .granted else {
              self?.alert("Microphone permission is required when safe. Listening can continue.")
              return
            }
            await voice.speakBriefly()
          })
      }
      audio.append(item("Leave intercom") { await community.leaveVoice() })
    } else {
      audio.append(
        item(
          "Join chapter intercom", detail: "Start listening · microphone off",
          enabled: !community.isRequestingVoice
        ) { await community.joinVoice() })
      if let ride = community.activeRide {
        audio.append(
          item("Join ride intercom", detail: ride.title, enabled: !community.isRequestingVoice) {
            await community.joinVoice(eventID: ride.eventID)
          })
      }
    }
    var sections = [
      CPListSection(items: audio, header: "Chapter communications", sectionIndexTitle: nil)
    ]
    if let ride = community.activeRide {
      var rideRows = [
        item("Check in · I’m OK", detail: ride.title) { [weak self] in
          let delivered = await community.checkIn()
          self?.alert(
            delivered
              ? "Check-in received by the ride."
              : "Check-in not delivered. Connection is unavailable.")
        },
        item("Ask ride Guardians for help") { [weak self] in
          self?.confirmHelp(eventID: ride.eventID, community: community, kind: "help")
        },
        item("Urgent SOS to ride Guardians") { [weak self] in
          self?.confirmHelp(eventID: ride.eventID, community: community, kind: "sos")
        },
        item("Confirm safe arrival · I’m home") { [weak self] in
          self?.confirmHome(community: community)
        },
      ]
      if community.isSharingRequested {
        rideRows.append(
          item("Stop position sharing") { [weak self] in
            community.stopSharing()
            self?.alert(
              "Location capture stopped. Removing the last server position; it expires within two minutes."
            )
          })
      }
      sections.append(
        CPListSection(items: rideRows, header: "Ride check-in", sectionIndexTitle: nil))
    }
    intercom.updateSections(sections)
    let rows: [any CPListTemplateItem] = community.conversations.prefix(20).map { conversation in
      // Apple invokes Siri to read/compose; the message preview is never displayed.
      CPMessageListItem(
        conversationIdentifier: conversation.id, text: conversation.title,
        leadingConfiguration: CPMessageListItemLeadingConfiguration(
          leadingItem: .none, leadingImage: nil, unread: conversation.unread > 0),
        trailingConfiguration: nil,
        detailText: conversation.kind == "direct"
          ? "Member conversation"
          : conversation.kind == "ride" ? "Ride conversation" : "Chapter conversation",
        trailingText: conversation.unread > 0 ? "\(conversation.unread) new" : nil)
    }
    messages.updateSections([
      CPListSection(items: rows.isEmpty ? [item("No conversations available")] : rows)
    ])
  }

  private func alert(_ message: String) {
    let alert = CPAlertTemplate(
      titleVariants: [message],
      actions: [
        CPAlertAction(title: "OK", style: .cancel) { [weak self] _ in
          self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
      ])
    interfaceController?.presentTemplate(alert, animated: true, completion: nil)
  }

  private func confirmHelp(eventID: String, community: CommunityStore, kind: String) {
    let alert = CPAlertTemplate(
      titleVariants: [
        "Send \(kind == "sos" ? "an urgent SOS" : "a help request") to the ride Guardians? This does not call emergency services."
      ],
      actions: [
        CPAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
          self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        },
        CPAlertAction(title: kind == "sos" ? "Confirm SOS" : "Request help", style: .default) {
          [weak self] _ in
          self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
          Task { @MainActor in
            do {
              try await community.rideOutbox.enqueue(
                eventID: eventID, kind: kind, note: "Assistance requested from CarPlay.")
              let pending = community.rideOutbox.pending.contains { $0.eventID == eventID }
              self?.alert(
                pending
                  ? "Request saved · not delivered. Waiting for connection."
                  : "Request received by the server. Guardian response is still pending.")
            } catch {
              self?.alert("Help request was not delivered. A chapter connection is required.")
            }
          }
        },
      ])
    interfaceController?.presentTemplate(alert, animated: true, completion: nil)
  }

  private func confirmHome(community: CommunityStore) {
    let alert = CPAlertTemplate(
      titleVariants: [
        "Confirm you have arrived safely? Position sharing and ride intercom will end."
      ],
      actions: [
        CPAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
          self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        },
        CPAlertAction(title: "I’m home", style: .default) { [weak self] _ in
          self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
          Task { @MainActor in
            await community.endRide(home: true)
            self?.render()
            self?.alert(
              community.activeRide == nil
                ? "Safe arrival received. Position sharing has ended."
                : "Arrival not delivered. Location capture has stopped; try again when connected.")
          }
        },
      ])
    interfaceController?.presentTemplate(alert, animated: true, completion: nil)
  }
}
