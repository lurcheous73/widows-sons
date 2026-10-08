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
- `admin/` – initial administrator portal prototype
- `mobile/` – future Flutter client
- `docs/` – architecture, roadmap and security constraints
- `deploy/` – local development deployment

## Run the prototype
```bash
docker compose -f deploy/compose.yaml up --build
```
Open http://localhost:8088 for the demonstration administration interface, and http://localhost:8008/docs for the API.

**Important:** The current API is a read-only, sample-data prototype. It deliberately does not expose real member records or allow unauthenticated administrative writes. Do not expose either service to the public Internet until authentication, authorisation, database-backed tenant isolation, TLS and audit logging are implemented.

## Branding
Tenant identifiers and branding are server-side data, not compiled into app code. The demonstration comes with `lr` and `demo` organisations. Neither uses a third party's logo. Real marks must be supplied by their owners. One installation can host multiple independently configured groups without sharing private data.

## Licence
Licence selection is pending; do not assume the repository contents are licensed for unrestricted redistribution until a licence is added.
