# Native ride operations and CarPlay — 0.6.0

Build continuation: the owner asked to continue against the spec and defer a
two-iPhone field trial until the design brief is complete. CarPlay was added as
an explicit requirement during this milestone. See `design-brief.md` for the
complete current interface brief and remaining platform areas.

## Added

- Per-event organiser delegation, Lead/Sweep/deputy/responder nominations,
  explicit acceptance/decline/withdrawal and audited replacement handovers.
- Private ride briefings, ordered stops, optimistic edit revisions, bounded GPX
  import, native route preview/export, Apple Maps stop directions and an editable
  native Calendar sheet. Calendar reading access is not requested.
- Help/SOS and Guardian check-in requests, independent receipts, responding,
  reasoned resolution/reopening, a shared activity log and arrival roster.
- A separate protected request queue with stable IDs and no GPS/token fields.
  Requests older than 15 minutes are not auto-sent. Sign-out clears the queue.
- Safe arrival/departure receipts survive live sharing expiry. Expiry is never a
  safe arrival. Assistance needs a Guardian's explicit reason. Closure rejects
  unresolved riders and incidents. No emergency services are contacted.
- Foreground request badges and duty invitations. Background APNs alerts,
  external safety-contact escalation and automatic incident detection are absent.
- Push-to-talk, bounded CarPlay speech and system voice ducking, with restoration
  on leave. Fixed dB reductions and third-party music transport are not claimed.
- CarPlay Communication scenes, CPMessageListItem/Siri messages, Send/Search/Read
  intents, Start Call handoff and physical-phone CallKit audio ownership.

## Build and operations

The `WidowsSons` scheme remains the normal phone app. The
`WidowsSons-CarPlay` scheme selects `CarPlay-Debug`/`CarPlay-Release` and the
communication/Siri entitlement file. Apple approval and matching signing are
required before installing an entitled build on a physical device/head unit.

`backend/ride_schema.sql` is additive. `install-communications.py` applies it and
the scoped runtime grants; `install-mobile.py` supports a fresh installation.
The existing public API cannot read the new private tables. `widowsapp` can read
organiser grants but cannot grant them. It cannot read welfare records.

Provision an approved organiser per event using the operator-only CLI:

```sh
sudo -u postgres /srv/widows-sons/venv/bin/python backend/manage_rides.py grant \
  --organisation lr --member APPROVED-MEMBER-UUID --event cms-POST-ID \
  --reason 'Chapter-authorised ride organiser delegation'
```

The command does not create a member or send a message. Revoke using the same
arguments and `revoke`. Road role acceptance never creates this permission.
Private native endpoints are under `/api/v1/mobile/lr/rides/cms-N/`; `ride-duty`
provides only event/alert identifiers for the app's badge.

The VM's mobile request body ceiling becomes 1 MiB for JSON-wrapped GPX. Raw XML
is restricted to 256 KiB in the route endpoint. Only geometry/name are stored.
NPM and Cloudflare need no changes for these HTTP additions. Existing private
LiveKit media networking remains; public TLS/media/TURN remain deployment work.

New incident, role and arrival history is private development data. No live
chapter retention policy has been assumed or scheduled. Operators must agree
the retention settings and record disposal process before a real-member pilot.
Precise GPS continues to use the existing two-minute expiry/purge, independently
of these coordinate-free receipts.

## Validation boundaries

Automated PostgreSQL tests exercise authority/tenancy, handovers, dual receipts,
idempotency, note validation, blocked closure, home privacy, assistance,
check-in responses, GPX validation and revision conflicts. Swift checks exercise
private queue persistence/retries/expiry, foreign receipts, Siri session/room
checks, real CarPlay callback selection and scene/intent declarations.

Debug CarPlay Simulator and unsigned Release hardware compilation check both
conditional audio paths. Physical CallKit, Siri interaction, CarPlay head-unit
behaviour, file encryption while locked and helmet/music/network/battery results
remain explicitly unverified until the owner starts the device trial.
