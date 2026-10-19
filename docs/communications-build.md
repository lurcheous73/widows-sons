# Swift communications and tracking — 0.5.0

Owner priority, 19 October 2026: communications, opt-in ride tracking and messaging.
The client is Swift 6 / SwiftUI with the existing Heritage & Road design. The
self-hosted API, PostgreSQL and CMS remain on Canada VM20000.

## Available for private review

- Chapter text conversation, private two-member conversations and per-ride chat.
- Server-confirmed sending with an idempotent message identifier, history,
  pagination and unread counts. Retry does not create a second copy. Open threads
  refresh every two seconds; the conversation list refreshes every five seconds.
- Remove your own messages, block/unblock direct messages and save a report.
  Reports require operator review; they do not send urgent alerts. The directory
  exposes active chapter display names, never email addresses.
- Chapter/ride audio rooms through LiveKit Swift 2.18.0 and self-hosted LiveKit
  1.13.10. Join starts without publishing a microphone. A separate permission and
  action enables it. Mute and Leave stop capture. There is no recording,
  transcription or egress service in this installation.
- RSVP Going, explicitly join a live ride, then separately opt in to GPS sharing.
  Only active members who joined the same ride can read its positions/roster.
- Native MapKit, accuracy, fix age and check-in times. Pins change colour after
  30 seconds and disappear after two minutes. Stop, Home and Leave clear precise
  coordinates. Old requests cannot restart a stopped sharing lease. There is no
  route-history table and Home does not save a home address.
- The app's ride lease lasts up to four hours; voice lasts up to one hour, both
  bounded by the member session. Server live mode opens 12 hours before departure
  and closes 48 hours afterwards. Published post lookup keeps a ride usable after
  it leaves the upcoming-events feed. Leaving Going status also ends sharing.

## Permission and lifecycle boundaries

Every private endpoint verifies active membership and an unexpired, unrevoked
session. Mutations recheck under a database lock. Organisation filters and
foreign keys scope records to their chapter. Road participation grants no chapter
administration rights. No Almoner section is exposed by these services.

Sign out stops local capture and clears private in-memory views. Backgrounding
hides private content and requires fresh verification on return. Explicitly
started location/audio sessions can continue while locked until stopped/expired;
neither is silently resumed after an app restart. Physical-device behaviour is
still acceptance work. Messages, profiles and positions are absent from the
public news cache.

Location fixes must be finite, recent, within coordinate/accuracy bounds and newer
than the saved fix. The server hides fixes over two minutes old and its 15-second
maintenance sweep purges expired coordinates. No route history is retained.

Voice JWTs allow microphone publication and subscription in exactly one room, with
no video, data publication or room administration. Initial admission tokens last
90 seconds. Nginx `auth_request` verifies signature, room, voice lease, membership
session and ride participation on every remote join/reconnect, including SFU
refreshed tokens. SFU administration is loopback-only. Maintenance checks leases and connected participants
every 15 seconds and removes revoked/expired participants; failed checks retry.
Native clients also close at their lease deadline.

Communication uses transport encryption on production HTTPS/WebRTC; it does not
claim end-to-end encryption. The trusted chapter server holds text messages and
manages audio rooms. Retention/moderation procedures need chapter agreement before
a real-member pilot.

## VM20000 operations

- `widows-sons-mobile.service`: Unix/database identity `widowsapp`, loopback 8009.
- `widows-sons-intercom.service`: `widowsvoice`, signalling/API loopback 7880,
  private ICE TCP 17881 and UDP 17882.
- `/etc/widows-sons/livekit.json` and `voice-api.env`: root-only secrets; systemd
  uses `LoadCredential` for the SFU. No server secrets are in Git.
- `deploy/install-communications.py`: checks the dedicated VM marker/hostname,
  applies additive schema/grants and verifies the pinned server release SHA-256:
  `c25a3e45fb922e9a93c6443d10c0ed041ba64342097e38632331736630283165`.
- VM Nginx `/rtc` checks admission then upgrades WebSockets. NPM forwards this
  route for `wsmba.the-grange.uk`. Token-bearing request/error logging is disabled
  at both proxies. All five unrelated NPM hosts were preserved and checked.
- The VM firewall permits media from its authorised development gateway only.
  The simulator uses the Mac SSH tunnel on 19820 for API/signalling and the
  routed VM private address for media.

Run the installer from the intended release directory as root on VM20000. Run
`configure-communications-npm.mjs` inside NPM when its route needs configuring.
It backs up the proxy database and preserves existing TLS/settings. Cloudflare
is unchanged. The release commit is recorded in
`/srv/widows-sons/communications-deployment.json`.

This deployment advertises the VM private IP. Public cellular use requires public
media NAT/candidates and suitable TURN fallback, trusted TLS after the owner's
DNS setup, then real network trials. An ordinary Cloudflare HTTP proxy does not
carry the raw WebRTC media ports.

## Validation and remaining acceptance

31 PostgreSQL/API tests passed against a disposable `_test` database; 29 Swift
tests passed. These cover tenancy, ownership, message retry identifiers, blocking,
reports, read cursors, GPS validation, sharing lease races, home receipts, voice
admission/revocation, native storage and private-state invalidation.

Deployed checks confirmed that the public API cannot read messages/locations and
the member service cannot read welfare sections or create memberships. Native
simulator checks exercised invitation activation, chapter/direct text sending,
received chapter replies, a muted intercom with a second QA participant, a
synthetic Core Location fix in both foreground and simulator background, Stop and Home removal. Two WebRTC clients exchanged
synthetic audio through the VM proxy; revocation disconnected its participant
and Nginx refused reconnection with the old token. The connected sender was also disconnected after its member record was deleted, including after grant records cascaded. No human microphone or audio recording was used by that transport test.

The repeatable root-only check is `deploy/verify-communications.py`; its optional RTC test dependency is `livekit==1.1.21`. It creates disposable fixtures and removes them in cleanup blocks.

Physical helmet routing, microphone quality, phone interruptions, locked-screen
operation, battery use, cellular handover and music ducking remain device/network
trials. SOS dispatch, automatic incident detection, Guardian escalation, push
notifications, attachments and music controls are not implemented by this milestone.
Apple signing/TestFlight is still a distribution step.
