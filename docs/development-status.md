# Working build status

The repository contains **demonstration software only**, not a functioning membership or ride safety platform.

## Implemented
- FastAPI read-only organisation metadata and example events.
- Two separate demonstration organisation brands.
- Static L&R public site, with a script fetching published events through a same-origin API proxy.
- Separate static administration preview.
- Docker Compose local-only bindings for API, site and admin.
- Basic FastAPI regression tests (run manually with pytest).

## Not implemented
- Secure sign-in, PostgreSQL tenant separation, member records, real event editing and publication.
- Shop checkout, email, fundraising provider integration, mobile apps, Ride Guardian, location tracking, messaging, helmet intercom, music audio control, and private welfare records.

## Testing
From `backend/`, install requirements and `pip install pytest httpx`; then run `python -m pytest -q`.
For deployment testing, bring up Compose inside the designated development container once provisioned. Access the prototype from that CT's localhost only.
