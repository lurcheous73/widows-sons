# Development status — 19 October 2026

## Presentation product — native 0.8.0

- Following the owner's request for a product to demonstrate before polishing,
  added a separate **WS L&R Demo** app using the existing native SwiftUI screens.
- Seven guided journeys cover chapter/news, ride planning and RSVPs, messaging,
  simulated rider positions, a Guardian help scenario, community sections/polls
  and a sample member card. Reset restores the fictional chapter.
- A stateful in-process transport supplies sample records. The demo rejects a
  live-service origin, uses no real location or microphone, and requires no
  invitation, Cloudflare or VM connection. Calendar saving is a preview.
- A spoken briefing demonstrates on-device audio. Live intercom and the CarPlay
  companion remain in the connected build and still need the requested two-phone,
  headset and head-unit acceptance trials. The demo makes no live-call claim.
- The dedicated Demo configurations have a separate bundle identifier and omit
  Siri/CarPlay/background entitlements. No backend, DNS or CMS changes were made
  for this milestone. Broader membership/commerce/welfare work remains later.
- See `product-demo.md` for presentation steps and validation. This milestone
  delivers the demo product; it does not mark the consultation platform complete.

## Community sections — native 0.7.0

- Added optional, named Community Sections to Comms with explicit open joining, approval requests or invitation acceptance. No default Ladies/Family/Associate section or eligibility policy is inferred.
- Native discussion/announcement/poll publishing, comments, server-confirmed retries, choice changes/withdrawal, pinning and reasoned content removal are implemented. Polls are informal, with aggregate totals and server-held vote identities; they are not secret or binding ballots.
- Section moderators can invite/approve/remove access, delegate their section role, review reports and record outcomes. The last active moderator cannot abandon an active section without a replacement. Chapter section.manage delegates can create/configure sections, but must already be active section moderators to reconfigure existing groups.
- Ordinary clubhouse tables are separate from the reserved welfare tables. General administration has no implicit access to private section content or rosters. Section text is never included in public offline reading, Siri or CarPlay.
- Native 0.7.0 retains the 0.6.0 ride, communication and CarPlay implementation. Two-iPhone, headset and head-unit acceptance remains deferred as requested. Background push, documents/media and the wider membership/commerce/welfare work remain outstanding.
- 73 PostgreSQL/API tests and 47 native Swift tests passed. CarPlay Debug Simulator and unsigned CarPlay Release iPhone builds compiled. See `community-sections-build.md` for exact scope and validation.

## Ride operations and CarPlay — native 0.6.0

- The owner requested continuation against the specification and a CarPlay companion, with the two-iPhone field trial deferred until the design brief is complete. The current interface brief is `design-brief.md`.
- Added event-scoped organiser delegation; accepted Lead/Sweep/deputy/responder roles; audited handovers; editable briefings/stops; GPX route preview/import/export; and a native Calendar editor.
- Added private help/SOS/check-in requests, independent Guardian acknowledgements/responding, reasoned resolution/reopening, arrivals/assistance, closure checks and protected pending-request retries. Expired sharing never counts as a safe arrival.
- CarPlay Communication templates, Siri message intents, Start Call handoff and physical-phone CallKit code are implemented. Push-to-talk, timed vehicle speech and system voice ducking are included. Apple managed entitlement approval, signing and real head-unit/Siri/headset trials remain required.
- 52 PostgreSQL/API tests and 38 native Swift tests passed; CarPlay Debug Simulator and unsigned Release iPhone code compiled. Simulator storage tests verify queue separation/backup exclusion; physical file encryption/locked-phone behaviour still needs a real device.
- Foreground badges are implemented. Background APNs, automatic accident detection, outside-contact dispatch, a custom CarPlay navigation map and the rest of the platform remain outstanding. See `ride-operations-build.md`.

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
This build is for private chapter review. Membership and event-organiser delegation are provisioned by operator CLIs. Member/admin approval screens, renewals, deletion self-service, background push, attachments, payments, fundraising, outside-contact escalation, owned-media transport controls and confidential welfare remain unimplemented. Messaging, tracking and intercom are implemented; native 0.6.0 adds the Guardian/route/CarPlay work above. Physical helmet/cellular/locked-screen and battery trials, Apple entitlement approval, public media deployment, Android validation and signed iPhone/TestFlight distribution are pending.

See `deploy/VM20000.md` for operations and `cms/EDITOR-GUIDE.md` for chapter editing.
See `docs/mobile-build.md` and `mobile/README.md` for mobile operations and simulator setup.
