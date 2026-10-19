# Development status — 19 October 2026

## Communications priority — native 0.5.0
- The owner prioritised communications, tracking and messaging. The native app now has chapter/direct/ride conversations, server-confirmed text sending, history, unread counts, blocking and reports.
- LiveKit Swift 2.18.0 and self-hosted LiveKit server 1.13.10 provide audio rooms, muted joins, microphone controls and participant state. Private Nginx admission checks and a maintenance sweep enforce voice leases and revoked sign-ins.
- Explicit live-ride join and separate GPS consent provide MapKit positions, fix-age/accuracy labels, check-ins, Stop, Leave and Home. Expired coordinates are removed and delayed uploads cannot restart stopped sharing.
- All 31 server tests and 29 native tests passed. Deployed checks verified native message persistence, private-room isolation, simulated GPS and coordinate removal. Two WebRTC clients exchanged synthetic audio; participant revocation and refused reconnection were verified.
- The WSMBA source search found GPL WordPress projects but no suitable native communications/tracking component. See `communications-build.md` and `wsmba-open-source-research.md` for scope, licence evidence and remaining acceptance work.

## Active native iOS build
- Following the owner's request, the active iOS client is now Swift 6 / SwiftUI in `ios-native/`, using the proposed Heritage & Road design.
- Native URLSession networking, structured refresh tasks, device-only Apple Keychain storage, file-based public caching and online member verification use the existing VM20000 API.
- The MIT-licensed KeychainAccess package is pinned to version 4.2.2 and revision `84e546727d66f1adc5439debad16270d0fdd04e7`; the full licence is bundled and visible in the app. XcodeGen generates the checked-in native Xcode project.
- All 20 native tests passed, including real Keychain persistence, tenant checks, session expiry/revocation, RSVP ownership in client state, public-cache separation, stale-response handling and bundled licence checks. Debug simulator and unsigned Release iPhone hardware builds compiled successfully.
- The running native app was checked against VM20000 for published article reading, invitation activation, membership verification after restart and RSVP saving using a disposable QA identity. Native offline checks confirmed that public content remains readable and member cards require an online check. The bundled open-source acknowledgement was also verified in the app.
- The earlier Flutter app remains in `mobile/` as a reference. Android is a future platform decision following the native iOS switch.

## Running on the dedicated Canada development VM
- Home CT1000 source and the PostgreSQL chapter database have been migrated to VM20000 (`can-widows-sons-dev`), with 8 vCPU, 16 GiB RAM and a 500 GiB disk.
- The original FastAPI read-only prototype and PostgreSQL public chapter feeds run under a dedicated service account.
- A custom WordPress block theme provides the public website, visual page editing, news, rides/events, charity stories, photo albums and private contact enquiries.
- Chapter editors can publish content and edit the design without user, plugin or system administration rights.
- A public CMS events feed exposes published upcoming events.
- A dedicated NPM entry is configured for `wsmba.the-grange.uk`.
- 27 integration checks and all five original backend tests passed.
- The first Flutter iOS review build now reads the live CMS, supports offline public reading, invitation sign-in, online member cards and ride RSVPs.
- `widows-sons-mobile.service` runs under a separate `widowsapp` identity on loopback port 8009. The existing NPM host forwards its API route through VM Nginx.
- The mobile milestone passed 18 Flutter tests, 14 backend regression/integration tests and 15 checks against the deployed HTTP service. An iOS simulator build was installed and exercised with disposable QA membership data.

## Launch dependencies
The owner is handling Cloudflare/public DNS. A covering certificate and enforced trusted HTTPS are pending that step. Editor sign-in must use trusted HTTPS. Search indexing and outbound email are disabled in development. Initial account emails use reserved `.invalid` placeholders.

## Remaining application work
This build is for private chapter review. Membership is provisioned by an operator CLI; member/admin approval screens, renewals, deletion self-service, push notifications, attachments, GPX/calendar export, payments, fundraising, Ride Guardian escalation, music controls and confidential welfare remain unimplemented. Messaging, opt-in tracking and voice rooms are implemented in native 0.5.0. Physical helmet/cellular/locked-screen and battery trials, public media deployment, Android validation and signed iPhone/TestFlight distribution are pending.

See `deploy/VM20000.md` for operations and `cms/EDITOR-GUIDE.md` for chapter editing.
See `docs/mobile-build.md` and `mobile/README.md` for mobile operations and simulator setup.
