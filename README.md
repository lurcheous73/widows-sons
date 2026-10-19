# Community Ride Platform

Open-source, self-hosted, brandable community platform. **Widows Sons L&R is the first planned organisation, not a hard-coded product identity.**

## Project goals
- iOS and Android member applications, browser-based administration
- Organisation / chapter isolation, permissions, invitations, events, calendars and notifications
- Private conversations, optional email integration, video meetings
- Ride-out coordination, optional live location sharing, SOS and safe-arrival check-ins
- Mobile-data group intercom using a connected Bluetooth helmet headset
- Per-organisation themes, names, icons, domains and terminology

## Repository layout
- `backend/` – FastAPI initial service and tenant-specific configuration/events API
- `admin/` – original administrator portal prototype
- `cms/` – custom WordPress block theme, chapter content tools and initial editable pages
- `ios-native/` – active native Swift 6 / SwiftUI iOS app and Xcode project
- `mobile/` – earlier Flutter prototype, retained as a reference
- `docs/` – architecture, roadmap and security constraints
- `deploy/` – local development deployment

## Run the prototype
```bash
docker compose -f deploy/compose.yaml up --build
```
Open http://localhost:8088 for the demonstration administration interface, and http://localhost:8008/docs for the API.

The original prototype endpoints provide read-only demonstration data. The active
native app uses the separate invitation/session and RSVP API on VM20000; it reads
published WordPress content rather than demonstration event fixtures. See the
deployment documentation for private development access and production requirements.

## Branding
Tenant identifiers and branding are server-side data, not compiled into app code. The demonstration comes with `lr` and `demo` organisations. Neither uses a third party's logo. Real marks must be supplied by their owners. One installation can host multiple independently configured groups without sharing private data.

## Chapter website and CMS
The L&R website has a custom WordPress block theme with visual page editing,
news, rides/events, charity stories, photo albums and a private enquiry inbox.
Chapter editors can publish content and edit the shared design without managing
users, plugins or system settings. PostgreSQL holds the chapter application data;
the WordPress database holds editorial content.

See [VM20000 deployment](deploy/VM20000.md), the
[chapter editor guide](cms/EDITOR-GUIDE.md) and the
[native iOS build](ios-native/README.md). The native app reads the CMS, provides
invitation sign-in, online membership cards and ride RSVPs. Chapter approval/admin
screens, intercom and Ride Guardian remain future work. Development mail delivery
is disabled. Public DNS/trusted HTTPS and signed iPhone distribution are pending.

## Licence
Licence selection is pending; do not assume the repository contents are licensed for unrestricted redistribution until a licence is added.
