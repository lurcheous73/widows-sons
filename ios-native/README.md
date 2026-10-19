# Widows Sons — native SwiftUI iOS app

**Active iOS implementation: Swift 6 + SwiftUI.** Version 0.4.0, minimum iOS 17.
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
No Swift UI is implemented as a web wrapper.

Member/admin approval screens, renewals, deletion self-service, notifications,
chat, GPX/calendar features, payments, Ride Guardian, SOS, headset intercom and
confidential welfare services remain later milestones. Existing service/API
operations and production requirements are in `../docs/mobile-build.md`.
Android is a separate future platform decision following this native iOS switch.
