# Native Swift iOS app — 0.7.0

The current build adds ordinary Community Sections under Comms: explicit joining,
approval/invitations, discussions, announcements, comments, informal polls and
section-scoped moderation. Read `../docs/community-sections-build.md` and the
updated `../docs/design-brief.md`. The existing ride/intercom/CarPlay companion is
retained. There are no additional third-party packages in this milestone.

## Native platform and build

**Active iOS implementation: Swift 6 + SwiftUI.** Version 0.7.0, minimum iOS 17.
The owner requested native Swift on 19 October 2026. This supersedes the Flutter
iOS prototype while retaining the same VM20000 API, database and WordPress CMS.
The proposed Heritage & Road design supplies the charcoal, brass, off-white,
Georgia headings and road motif. No official insignia have been invented.

## Build and run

Open `WidowsSons.xcodeproj`, select the **WidowsSons** scheme and an iPhone
simulator, then Run. Xcode 27 and XcodeGen 2.46.0 were used for this build.
The checked-in project opens directly; XcodeGen is needed only after changing
`project.yml` or adding/removing files:

```sh
xcodegen generate
xcodebuild -project WidowsSons.xcodeproj -scheme WidowsSons \
  -configuration Debug -destination 'platform=iOS Simulator,name=Widows Sons QA' \
  -derivedDataPath build/review build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
```

Debug uses `http://localhost:19820`, through the existing Mac-to-VM20000 SSH
tunnel. Start `sh tool/dev-tunnel.sh` if it is not already running.
Do not stop another process if that port is occupied. Release defaults to
`https://wsmba.the-grange.uk` and has no insecure transport exceptions. The
production configuration rejects HTTP. Physical iPhone distribution requires
trusted public HTTPS, an Apple signing team/profile and a TestFlight upload.

```sh
xcodebuild -project WidowsSons.xcodeproj -scheme WidowsSons \
  -configuration Debug -destination 'platform=iOS Simulator,name=Widows Sons QA' \
  -derivedDataPath build test CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
```

## Native implementation

Communications, messaging and opt-in ride tracking are the current priority.
`CommunicationsScreens.swift`, `ChatThread.swift` and `CommunityStore.swift` provide
chapter/direct/ride text messages, history, unread counts, retries, blocking and
reports. `VoiceIntercom.swift` uses LiveKit for native chapter/ride audio rooms.
`RideLocationDriver.swift` and `LiveRideScreen.swift` provide opt-in GPS, MapKit,
fix ages, check-ins, Stop and Home.

- `Sources/WidowsSonsApp.swift`: SwiftUI application, native navigation and chapter tabs.
- `DesignSystem.swift`: Heritage & Road styling, Dynamic Type and reusable view components.
- `PublicScreens.swift`: live news/search/articles, chapter information and ride lists.
- `MemberScreens.swift`: invitations, member cards, RSVPs, privacy information and licences.
- `ChapterStore.swift`: main-actor observable UI state with structured refresh tasks and
  guards against stale responses restoring a signed-out or backgrounded member card.
- `ChapterAPI.swift`: actor-isolated URLSession networking, no redirects/cookie storage,
  bearer headers, tenant checks and typed errors.
- `Storage.swift`: Apple Keychain sessions and a separate file cache of public content.

Only public editorial data is cached. Member profiles and responses stay in memory
and require online verification. Session secrets are device-only and accessible
while unlocked. Backgrounding hides private information and invalidates the
membership display until rechecked. The existing invitation, expiry, revocation,
suspension and RSVP permission checks remain enforced by the server.

## GitHub open source used

[LiveKit Swift](https://github.com/livekit/client-sdk-swift), **2.18.0**,
Apache-2.0, is pinned at revision `93a7251057bdb6a80a7b1f6d11464d578ebdc09b`.
Its server runs on the dedicated VM. Complete SDK and binary-component notices
are bundled. See `../docs/wsmba-open-source-research.md` for the WSMBA search and
`../docs/communications-build.md` for deployment, validation and device trials.

[KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess), MIT licence,
version **4.2.2**, is linked through Swift Package Manager. `Package.resolved` pins
revision `84e546727d66f1adc5439debad16270d0fdd04e7`. Its copyright and full licence
are bundled in `ThirdPartyNotices.txt` and viewable from the Member screen. Tests
exercise actual Keychain persistence and confirm that the licence is bundled.

[XcodeGen](https://github.com/yonaskolb/XcodeGen), MIT licence, is the development
tool that generates the project. It is not linked into the app. The rest of the
client uses Apple frameworks. Future open-source additions should solve an
implemented feature, have a suitable licence, and be pinned and acknowledged.

## Current scope

Chapter home, live searchable news, article reading, public offline content,
upcoming rides and details, invitation sign-in, online membership cards, RSVP
responses and chapter information. WordPress updates feed both website and app.
No Swift UI is implemented as a web wrapper. The app now also includes member
messaging, self-hosted voice intercom and opt-in live ride maps.

Member/admin approval screens, renewals, deletion self-service, background push,
message attachments, payments, external safety-contact escalation, owned-media
transport controls and confidential welfare services remain later milestones.
Physical helmet/cellular/locked-screen and battery trials remain acceptance work.
Existing service/API
operations and production requirements are in `../docs/mobile-build.md`.
Android is a separate future platform decision following this native iOS switch.

## Ride operations and CarPlay — 0.6.0

The native app now includes per-event Guardian nominations/acceptance/handovers,
briefings and stops, GPX route preview/import/export, a native Calendar editor,
private help/SOS/check-in requests, independent Guardian receipts, resolution
history, safe-arrival records, confirmed assistance and closure checks. See
`../docs/ride-operations-build.md` for permissions and deployment.

`RideRequestOutbox.swift` stores only pending requests, separately from public
editorial caching, with protected backup-excluded files and stable retry IDs.
Sign-out clears this queue; an unsent request over 15 minutes old must be reviewed
and sent afresh. A server receipt never implies a Guardian response.

The `WidowsSons-CarPlay` scheme adds `CarPlay-Debug`/`CarPlay-Release` with the
communication entitlement. `CarPlaySceneDelegate.swift` uses system Intercom and
Messages lists, with Siri reading/composing through `CommunicationIntents.swift`
and permission-checked `SiriMessageService.swift`. Physical-phone audio uses
`IntercomCallCoordinator.swift`/CallKit; Simulator uses the existing transport.
The SDK supplies system voice ducking. Push-to-talk and a 30-second vehicle
speech burst are explicit microphone actions.

Apple must approve the communication category and the signing profile must carry
that managed capability. No Apple request has been submitted. Custom CarPlay
maps/turn-by-turn navigation are outside this communication-category build.
`../docs/design-brief.md` is the completed current interface brief, including
CarPlay constraints and the subsequent two-iPhone/head-unit acceptance matrix.

The session Keychain item is device-only and accessible after first unlock since
reboot for locked-phone Siri/CarPlay. The request queue requests equivalent file
protection. Private message text and locations are never cached for Siri.
