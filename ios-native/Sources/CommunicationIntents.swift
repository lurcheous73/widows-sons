import CryptoKit
import Intents
import UIKit

@MainActor
final class CommunicationAppDelegate: NSObject, UIApplicationDelegate {
  private let handler = CommunicationIntentHandler()
  func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
    switch intent {
    case is INSendMessageIntent, is INSearchForMessagesIntent, is INSetMessageAttributeIntent,
      is INStartCallIntent:
      handler
    default: nil
    }
  }
  func application(
    _ application: UIApplication, continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    Self.continueCall(userActivity)
  }
  @discardableResult
  static func continueCall(_ userActivity: NSUserActivity) -> Bool {
    guard let intent = userActivity.interaction?.intent as? INStartCallIntent else { return false }
    let destination =
      intent.contacts?.first?.customIdentifier ?? intent.contacts?.first?.displayName
    Task { await startIntercom(destination: destination) }
    return true
  }
  static func startIntercom(destination: String?) async {
    guard let store = AppRuntime.shared.store else { return }
    await store.loadOrRefresh()
    guard let community = store.community, community.isVerified else { return }
    guard !community.isRequestingVoice, !community.voice.isInSession else { return }
    if destination == "ws-ride-intercom"
      || destination?.localizedCaseInsensitiveContains("ride") == true
    {
      guard let ride = community.activeRide else { return }
      await community.joinVoice(eventID: ride.eventID)
    } else {
      await community.joinVoice()
    }
  }
}

final class CommunicationIntentHandler: NSObject, INSendMessageIntentHandling,
  INSearchForMessagesIntentHandling, INSetMessageAttributeIntentHandling, INStartCallIntentHandling
{
  private func service() throws -> SiriMessageService {
    SiriMessageService(configuration: try AppConfiguration.bundled())
  }

  static func person(id: String, name: String) -> INPerson {
    INPerson(
      personHandle: INPersonHandle(value: id, type: .unknown), nameComponents: nil,
      displayName: name, image: nil, contactIdentifier: nil, customIdentifier: id)
  }

  static func clientID(identifier: String?, conversation: String?, content: String) -> UUID {
    guard let identifier else { return UUID() }
    let bytes = Array(
      SHA256.hash(data: Data("\(identifier)|\(conversation ?? "")|\(content)".utf8)).prefix(16))
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
        bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }

  func resolveRecipients(for intent: INSendMessageIntent) async
    -> [INSendMessageRecipientResolutionResult]
  {
    if intent.conversationIdentifier != nil || intent.speakableGroupName != nil {
      return [.notRequired()]
    }
    guard let recipients = intent.recipients, recipients.count == 1,
      let recipient = recipients.first
    else { return [.needsValue()] }
    let value = recipient.customIdentifier ?? recipient.displayName
    do {
      let people = try await service().people(matching: value)
      if people.count == 1, let person = people.first {
        return [.success(with: Self.person(id: person.id, name: person.displayName))]
      }
      if people.count > 1 {
        return [.disambiguation(with: people.map { Self.person(id: $0.id, name: $0.displayName) })]
      }
      return [.unsupported()]
    } catch { return [.unsupported()] }
  }

  func resolveContent(for intent: INSendMessageIntent) async -> INStringResolutionResult {
    guard let content = intent.content, let text = CommunityInput.message(content) else {
      return .needsValue()
    }
    return .success(with: text)
  }

  func handle(intent: INSendMessageIntent) async -> INSendMessageIntentResponse {
    let room = intent.conversationIdentifier
    let group = intent.speakableGroupName?.spokenPhrase
    let recipient = intent.recipients?.count == 1 ? intent.recipients?.first?.customIdentifier : nil
    let content = intent.content ?? ""
    let id = Self.clientID(
      identifier: intent.identifier, conversation: room ?? recipient ?? group, content: content)
    do {
      _ = try await service().send(
        conversationID: room, groupName: group, recipientID: recipient, content: content,
        clientID: id)
      return INSendMessageIntentResponse(code: .success, userActivity: nil)
    } catch { return INSendMessageIntentResponse(code: .failure, userActivity: nil) }
  }

  func handle(intent: INSearchForMessagesIntent) async -> INSearchForMessagesIntentResponse {
    let rooms = intent.conversationIdentifiers ?? []
    let groups = intent.speakableGroupNames?.map(\.spokenPhrase) ?? []
    let ids = intent.identifiers ?? []
    let terms = intent.searchTerms ?? []
    let senders = intent.senders?.compactMap(\.customIdentifier) ?? []
    let unread = intent.attributes.contains(.unread)
    // Unsupported search filters fail explicitly instead of returning unrelated text.
    guard intent.dateTimeRange == nil, (intent.notificationIdentifiers ?? []).isEmpty,
      (intent.recipients ?? []).isEmpty
    else { return INSearchForMessagesIntentResponse(code: .failure, userActivity: nil) }
    do {
      let messages = try await service().search(
        conversationIDs: rooms, groupNames: groups, messageIDs: ids, unreadOnly: unread,
        terms: terms, senderIDs: senders)
      let response = INSearchForMessagesIntentResponse(code: .success, userActivity: nil)
      response.messages = messages.map { message, title in
        INMessage(
          identifier: "\(message.conversationID):\(message.id)",
          conversationIdentifier: message.conversationID, content: message.body,
          dateSent: message.sentAt,
          sender: Self.person(id: message.senderID, name: message.senderName), recipients: nil,
          groupName: INSpeakableString(spokenPhrase: title), messageType: .text,
          serviceName: "Widows Sons", attachmentFiles: nil)
      }
      return response
    } catch { return INSearchForMessagesIntentResponse(code: .failure, userActivity: nil) }
  }

  func handle(intent: INSetMessageAttributeIntent) async -> INSetMessageAttributeIntentResponse {
    let ids = intent.identifiers ?? []
    guard intent.attribute == .read else {
      return INSetMessageAttributeIntentResponse(code: .failure, userActivity: nil)
    }
    do {
      try await service().markRead(ids)
      return INSetMessageAttributeIntentResponse(code: .success, userActivity: nil)
    } catch { return INSetMessageAttributeIntentResponse(code: .failure, userActivity: nil) }
  }

  func resolveContacts(for intent: INStartCallIntent) async -> [INStartCallContactResolutionResult]
  {
    guard let contact = intent.contacts?.first else { return [.needsValue()] }
    let name = contact.customIdentifier ?? contact.displayName.lowercased()
    if name == "ws-chapter-intercom" || name.contains("chapter") {
      return [.success(with: Self.person(id: "ws-chapter-intercom", name: "Chapter intercom"))]
    }
    if name == "ws-ride-intercom" || name.contains("ride") {
      return [.success(with: Self.person(id: "ws-ride-intercom", name: "Ride intercom"))]
    }
    return [.unsupported()]
  }

  func handle(intent: INStartCallIntent) async -> INStartCallIntentResponse {
    guard let destination = intent.contacts?.first?.customIdentifier else {
      return INStartCallIntentResponse(code: .failureContactNotSupportedByApp, userActivity: nil)
    }
    guard intent.callCapability != .videoCall,
      ["ws-chapter-intercom", "ws-ride-intercom"].contains(destination)
    else {
      return INStartCallIntentResponse(code: .failureContactNotSupportedByApp, userActivity: nil)
    }
    // Siri hands this activity to the app; CallKit then owns the audio lifecycle.
    let activity = NSUserActivity(activityType: "INStartCallIntent")
    return INStartCallIntentResponse(code: .continueInApp, userActivity: activity)
  }
}
