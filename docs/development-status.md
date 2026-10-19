# Development status — 19 October 2026

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
