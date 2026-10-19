# Development status — 19 October 2026

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
The first app milestone is for private chapter review. Membership is provisioned by an operator CLI; member/admin approval screens, renewal workflows, deletion self-service, push notifications, messaging, GPX/calendar export, payments, fundraising integrations, location tracking, Ride Guardian, helmet intercom, music control and confidential welfare services remain unimplemented. Android platform validation and signed iPhone/TestFlight distribution are still pending. The invitation/session foundation does not establish that the rest of the specification functions.

See `deploy/VM20000.md` for operations and `cms/EDITOR-GUIDE.md` for chapter editing.
See `docs/mobile-build.md` and `mobile/README.md` for mobile operations and simulator setup.
