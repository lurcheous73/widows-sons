# Development status — 19 October 2026

## Running on the dedicated Canada development VM
- Home CT1000 source and the PostgreSQL chapter database have been migrated to VM20000 (`can-widows-sons-dev`), with 8 vCPU, 16 GiB RAM and a 500 GiB disk.
- The original FastAPI read-only prototype and PostgreSQL public chapter feeds run under a dedicated service account.
- A custom WordPress block theme provides the public website, visual page editing, news, rides/events, charity stories, photo albums and private contact enquiries.
- Chapter editors can publish content and edit the design without user, plugin or system administration rights.
- A public CMS events feed exposes published upcoming events.
- A dedicated NPM entry is configured for `wsmba.the-grange.uk`.
- 27 integration checks and all five original backend tests passed.

## Launch dependencies
The owner is handling Cloudflare/public DNS. A covering certificate and enforced trusted HTTPS are pending that step. Editor sign-in must use trusted HTTPS. Search indexing and outbound email are disabled in development. Initial account emails use reserved `.invalid` placeholders.

## Future application work
The mobile apps, member sign-in, live membership administration, private-record tenant policies, messaging, payments, fundraising integrations, location tracking, Ride Guardian, helmet intercom, music control and private welfare services are not implemented. The database schema is a foundation; it does not establish that these features function.

See `deploy/VM20000.md` for operations and `cms/EDITOR-GUIDE.md` for chapter editing.
