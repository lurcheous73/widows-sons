# Widows Sons L&R — Consultation Document
**Draft 0.1 | 8 October 2026 | For chapter consultation; no policies agreed yet**

## Vision
One integrated, self-hosted, brandable community platform: public L&R website, secure member clubhouse, browser-based administration, and iPhone/Android applications. One code repository, backend, organisation-scoped database, permissions system and design language. L&R is the first organisation, not a permanent hard-coded brand.

The feature review covers publicly accessible UK/US Widows Sons sites and comparative app descriptions, notably Ohio (chapter events and rescue assistance), UK chapters (charity, members and public information), Widows Sons International (forums and remembrance), and Widows Sons NL (GPX rides, messaging, group expenses and photos). See [research](widows-sons-feature-survey-uk-us.md). These are ideas only; do not copy proprietary code or artwork.

## Consultation topics and proposed features
### Public website
- Home; about the chapter; news; public events; charity projects/beneficiaries; sponsors; chapter contact; public shop; easyfundraising link.
- Accessible/mobile-first; approved chapter identity, photographs and copy; SEO and anti-spam contact form.
- Private clubhouse and web admin accessed through the same site, with separate permissions.

### Membership and community
- Invite/approval, members, associates, guests, configurable section access, digital cards and renewal reminders.
- Ladies section (optional); other brandable community sections.
- Banter and chat channels, announcements, polls, DMs, albums, ride memories and memorial pages with consent.
- Confidential Almoner's section, with independent permissions and strict privacy. General admins do NOT automatically see welfare cases.
- Chapter documents, voting if approved, galleries, inter-chapter guest access.

### Rides and audio
- Calendar, RSVP, GPX routes, departure briefing, fuel/coffee stops, shared events.
- Road Captain leads; Sweep brings up rear. Both are Ride Guardians for a specific event. Road roles are *not* administrative ranks.
- Opt-in live GPS, old-position timestamps, breakdown help, SOS, lost-rider check-in, safe-home confirmation.
- Cellular-data bike-to-bike voice intercom with helmet Bluetooth headsets; music/podcasts and ducking during speech; safe audio restoration.
- Sensors, coverage, Bluetooth and OS behaviour can fail: no guarantee of accident detection or emergency response. Road-test before safety reliance.

### Charity, sales and payments
- Public fundraising campaigns, volunteering, sponsors and verified outcomes.
- easyfundraising approved referral links for everyday shopping; distinguish retailer-funded donations from personal discounts.
- Chapter merchandise: patches (permission-restricted where applicable), T-shirts, gifts, fulfilment and refund workflow.
- Charity merchant account where legally appropriate, with separate reporting for gross sales, costs, processing fees and net proceeds. Confirm legal seller before launch.
- Member classifieds, shared ride expenses and payments subject to approval.

### Administration
- Admin web console: memberships, content, events, shop, finance, sections, branding and audit history.
- Fine-grained roles, MFA, per-tenant data access, no automatic rights over Almoner records or private messages.
- Chapter hierarchy and role names to be decided after consultation.
- Backend runs on authorised self-hosted infrastructure; no private member information in public GitHub.

## Suggested consultation questions
1. Which three features should members get first?
2. Should associates see public events, chat, shop and charity content by default, or by invitation?
3. Who may join Ladies/Supporters/Community sections, and who moderates them?
4. Which people may create a ride, serve as Road Captain or Sweep, or respond to incident alerts?
5. How long should live location history be retained, and who may see it?
6. Should riders be able to share safe-home status without sharing a home address? (Recommended: yes.)
7. Which chat groups should be member-only, associate-visible or committee-only?
8. What responsibilities and confidentiality controls does the Almoner require?
9. Which products belong in the club shop, and which chapter insignia need restricted sales?
10. Who is the legal merchant of record, and which registered charity/good cause receives shop proceeds?
11. What is L&R's approved easyfundraising cause link, if already registered?
12. What chapter contact email, website domain, photographs, logo and introductory copy are approved?

## Proposed delivery order
1. Public website + brand system + authenticated member/admin foundations.
2. Members, events, news, calendars, announcements and moderation.
3. Routes, ride roster, Road Captain/Sweep, Guardian safety trials and intercom/headset tests.
4. Shop, fundraising, easyfundraising, Almoner and other restricted areas after appropriate governance.
5. Inter-chapter and optional advanced integrations.

## Decision record
All choices above are proposals awaiting chapter consultation. Record decisions, responsible officer, approval date, and requirements changes before live launch.

**Current delivery status:** consultation and website prototype; no member database, live payments, riding safety service or public deployment.
