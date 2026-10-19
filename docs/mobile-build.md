# Mobile review build — 19 October 2026

The first Flutter client is implemented in `mobile/`, following the phased
`LR-CONSULTATION.md` specification. This is a development milestone on the dedicated
Canada VM20000. The website remains editable in WordPress and supplies the app's
public news, chapter information and upcoming rides. The app does not consume the
old demonstration event endpoints.

## Services and data

`widows-sons-mobile.service` listens on **127.0.0.1:8009** and runs as the separate
`widowsapp` OS/database identity. VM Nginx forwards `/api/v1/mobile/` to this service.
The existing NPM hostname entry already forwards that path through the VM; no
additional NPM host, port-forward or public DNS change is required.

`backend/mobile_schema.sql` adds invitations, sessions, RSVP records and bounded
authentication attempt counters to the existing PostgreSQL database. Apply it after
`schema.sql`. Composite foreign keys bind records to both member and organisation.
The public `widowsapi` role still cannot read members. The mobile role has no
section/welfare access, cannot create members and cannot update names or email.
Membership provisioning is restricted to the database owner/operator workflow.

The app service reads only published content from the operator-configured local
WordPress origin. An unknown or unmapped chapter is rejected. Generalising the
CMS origin mapping and full theme assets for additional chapters is future work.

## Deploy an updated source release

Copy a reviewed source archive into a new directory beneath
`/srv/widows-sons/releases/`, owned by root and readable by the service. As root:

```sh
python3 /srv/widows-sons/releases/<commit>/deploy/install-mobile.py
systemctl status widows-sons-mobile.service
curl --fail http://127.0.0.1:8009/health
```

The installer checks the VM identity marker and hostname, applies the additive
schema idempotently, creates/scopes `widowsapp`, updates only the mobile unit and
adds its route to the existing Widows Sons Nginx site. The original Nginx site is
backed up before the first insertion. Nginx configuration is checked before reload.
Re-running the installer from a prior release restores that service's code; it does
not drop data. No database destruction is part of deployment.

## Issue an invitation

On VM20000, run the release's command as the postgres OS user. The destination must
be writable by postgres, private and outside Git. It must not already exist:

```sh
sudo -u postgres /srv/widows-sons/venv/bin/python \
  /srv/widows-sons/releases/<commit>/backend/manage_mobile.py invite \
  --organisation lr --email '<approved-member-email>' --name '<member-name>' \
  --type member --out /var/lib/postgresql/<unique-invitation-file>.json
```

`member`, `associate` and `guest` are supported membership types. Share the code
privately with the approved person. This action is account provisioning, so it
must be performed only for a membership the chapter has actually approved. No
real member is pre-seeded. The invitation file is mode 0600; no code is printed.

The invitation expires after seven days and is consumed atomically. Only digests
of invitation and session secrets are stored in PostgreSQL. The server issues an
opaque 256-bit random session secret, with a 30-day maximum lifetime. Each request
checks expiry, revocation, tenant scope and active membership. Redeeming a fresh
invitation revokes prior sessions for that member. Suspending the membership
therefore blocks private requests immediately. These controls are tested against
real PostgreSQL, not an in-memory database imitation.

The mobile client stores its session using iOS Keychain / Android secure storage.
Only public editorial data goes in preferences. A membership card requires an
online profile check and displays its verification timestamp; it is not a paid-dues
certificate, wallet pass or independently verifiable credential. No secret is
encoded in a card or a QR code. API responses use `Cache-Control: no-store` and
credentials are never placed in URLs. Authenticated route access logging is off.

## Test without affecting live members

The automated backend suite refuses a database whose name does not end in `_test`.
It deliberately resets the test schema. Never point it at the chapter database.

```sh
sudo -u postgres createdb widowssons_mobile_test
cd /srv/widows-sons/releases/<commit>/backend
sudo -u postgres env \
  WIDOWS_SONS_MOBILE_TEST_DSN='dbname=widowssons_mobile_test user=postgres host=/var/run/postgresql' \
  /srv/widows-sons/venv/bin/pytest -q -p no:cacheprovider test_mobile.py test_app.py
```

Run `deploy/verify-mobile.py` with the VM's Python environment as root for live HTTP
and service-role checks. It creates a clearly named temporary member and a
published event in 2099, checks all RSVP states and revocation, then removes the
fixtures in `finally` blocks. It sends no mail and prints no credential. Do this
while the development environment is private; the short-lived test event appears
on the public feed during the check. Unit test failures must be fixed before
sharing a build.

## Before a member pilot or store distribution

Public DNS, trusted HTTPS and HTTPS enforcement are pending the owner's Cloudflare
work. The private Mac-to-VM SSH tunnel is development-only. Real member onboarding,
administrator MFA/approval tooling, recovery and renewal policy, deletion self-service,
retention rules, privacy notices, backups/restore validation, monitoring and abuse
controls need chapter sign-off and further implementation. Production authentication
and operational security need a review before inviting real members.

The current build has no location or microphone use. Native location/audio,
notification delivery, Ride Guardian and emergency behaviours require separate
physical-device testing. These functions remain disabled and have no working UI
claims. Confidential Almoner access must remain separate from general administration.
