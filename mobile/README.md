# Widows Sons mobile — first review build

Flutter 3.47.7 / Dart 3.13.5, version **0.3.0+1**. Built and exercised on an iOS
27 simulator using Xcode 27. The iOS deployment target is 15.0. The shared Dart
client and Android project are present; Android device validation is still pending.

## This milestone

- Chapter home with server-supplied chapter identity and accent colour.
- WordPress news, search and readable articles inside the app.
- Published upcoming rides/events, chapter-local times and event details.
- Offline public reading with a visible saved timestamp and pull-to-refresh.
- Single-use chapter invitations, device secure storage, online member verification
  and a digital member card.
- Going / Interested / Not going responses and a My rides filter.
- Chapter information, website links and app privacy information.

There is no fabricated ride schedule or membership data. Empty feeds have useful
empty states. Private profiles and responses are never written to the public cache.
The WS monogram is a temporary app identity, not an official chapter badge.

## Run on the Mac before public DNS is ready

Install the pinned Flutter release and use its `flutter` command on your PATH.
This repository's `pubspec.lock` pins the resolved packages. Flutter uses Swift
Package Manager for the native iOS plugins; enable it once:

```sh
flutter config --enable-swift-package-manager
flutter pub get
```

The Mac must be able to reach VM20000 privately and its SSH identity must already
be authorised for `widowsbuild`. In one terminal, from `mobile/`:

```sh
sh tool/dev-tunnel.sh
```

In another, choose the dedicated **Widows Sons QA** iPhone simulator:

```sh
flutter devices
flutter run -d <simulator-id> --dart-define=WIDOWS_SONS_BASE_URL=http://127.0.0.1:19820
```

The SSH tunnel encrypts the connection to Canada and listens only on Mac loopback.
The host key is pinned in `tool/vm20000_known_hosts`. If port 19820 is already in
use, inspect the existing process rather than stopping an unrelated service.

Production builds default to `https://wsmba.the-grange.uk`. Release builds reject
HTTP URLs. The loopback HTTP exceptions exist only in `Info-Debug.plist`; release
and profile configurations use `Info.plist`. Public DNS and trusted HTTPS must
work before a physical-device review build can use that hostname.

## Verification and build

```sh
flutter analyze
flutter test
flutter build ios --simulator --debug --dart-define=WIDOWS_SONS_BASE_URL=http://127.0.0.1:19820
```

The simulator `.app` is for a Mac simulator; it is not an iPhone IPA. TestFlight
needs an approved bundle identifier, Apple signing/provisioning and an upload.
No App Store or TestFlight submission has been made by this milestone.

## Membership operations

See `../docs/mobile-build.md` for API deployment, operator invitation provisioning,
test databases, security boundaries and the remaining production work. Invitations
expire after seven days, can be used once and must be delivered privately by the
chapter. The app's sign-in expires after 30 days. A replacement invitation revokes
the previous device session when redeemed. No outbound invitation email is sent.

## Scope still to build

Member/admin approval screens, account deletion self-service, membership renewals,
push notifications, messaging, GPX/calendar export, payments and charity integrations
remain later milestones. Ride Guardian, SOS, location sharing, helmet intercom,
music control and confidential welfare features are not implemented or presented
as functioning in this build. They require dedicated native and governance work.
