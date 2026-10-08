# Architecture and safety boundaries

## Tenancy and branding
Future organisations table: id (UUID), slug (unique), name, short_name, theme JSON, approved assets, custom domain, locale, feature flags.
Every member, ride, event, message and document must contain an organisation_id. Enforce that scope in **database queries and access policies**, not only in the interface.
Group-level admins cannot manage another group. Cross-organisation access must be explicit and audited.

## Planned services
- Flutter mobile apps on iOS and Android.
- FastAPI backend, PostgreSQL and a job queue.
- Responsive administrator portal with MFA and fine-grained RBAC.
- Push: APNs / FCM; messaging via proven E2EE protocol; calls via Jitsi/WebRTC.
- Helmet Bluetooth is audio I/O; inter-rider transport is mobile data, not arbitrary long-range Bluetooth.
- GPX routes, calendar invitation export, emails via each organisation's own mail integration.

## Safety
Ride Guardian is opt-in, time-limited and visible only to designated participants/contacts.
Store accurate location timestamps, show last-known status, and distinguish silence from a crash.
Never claim SOS contacted emergency services unless a call was actually placed.
Sensor-based crash detection requires extensive validation and must not be marketed as guaranteed protection.
Members must be able to end a ride, revoke sharing and manage retention.
Initial prototype DOES NOT track locations or implement incident detection.

## Before production
Implement OIDC/authentication, MFA for admins, authorization tests, audit logs, migrations, backups, restore drills, TLS, monitored uptime, GDPR processing documentation, privacy defaults, abuse controls and threat modelling.
No real user data in public repositories or demonstration fixtures.
