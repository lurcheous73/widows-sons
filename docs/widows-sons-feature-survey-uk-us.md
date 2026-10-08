# Widows Sons feature survey — UK, USA and app references
Date: 2026-10-08
Status: public-source product research, not implemented. Survey is broad but NOT exhaustive: private sites, app-only screens and inaccessible chapter websites were not audited.

## Sources
- UK national WSMBA: https://wsmba.uk/ and https://wsmba.uk/Where.html
- Cheshire: https://www.cwsmba.org.uk/
- Kernow/Cornwall: https://widowssonseng.uk/
- Merlin: https://www.merlinwidowssons.org.uk/
- US Ohio: https://ohiowidowssons.com/ , /events/ , /rescue-team/
- International directory: https://widowssonsinternational.com/directory/wpbdp_category/united-states/
- International forums: https://widowssonsinternational.com/forums/
- International memorial: https://widowssonsinternational.com/brothers-gone-but-not-forgotten/
- Netherlands iOS app (additional international benchmark): https://apps.apple.com/gb/app/widows-sons-nl/id6788451740
- Evoluado Android app: https://play.google.com/store/apps/details?id=com.widowssons.app

## Verified public reference patterns
### Netherlands — detailed app benchmark, not UK/US
- Invite-only member login, group/direct chats, reactions, attachments, replies, edits, search, pinned/unread.
- Event RSVP and guests; map/meeting points and route navigation handoff.
- GPS ride recording, GPX import/export, live location sharing, route planning and private trip journals.
- Per-event shared photo albums including map-tagged photographs.
- Chapter dashboard, charity meters, mileage stats/challenges.
- Expense splitting, treasurer payment requests, outstanding balances.
- Merchandise shop, stock/order pickup and delivery described in app release notes.
- Offline cache/connection recovery and large text options.
- These are developer-described app features, not independently tested.

### USA — Ohio Grand Chapter
- Multi-chapter calendar with flyered events, rally registrations, chapter/officer directory.
- Rescue network with primary, secondary and backup contact volunteers per chapter.
- Describes companion/ladies and other membership classifications.

### UK — Kernow / Cornwall
- Public charity ride-outs with planned fuel stop, marshal organisation, raffles, prizes, stall holders, sponsors and beneficiary impact stories.
- Specific fundraising results and community engagement.

### UK — Cheshire
- Member joining/patching information and Bad-Pennies family/friends group.
- Monthly family-friendly breakfasts and ride-outs.

### USA/International directory and forums
- Searchable worldwide chapter directory; authenticated forums for riding, safety, news, sickness/distress, humour and remembrance.
- Public memorial pages honour deceased members.

### Evoluado Android application
- Developer-advertised member-oriented events, motorcycle profiles and member directory, with chapter administrative tools. Do not assume it is Merlin's own proprietary software.

## Feature backlog suggested for our ORIGINAL brandable platform

P0 — foundations:
- Tenant-isolated organisation/chapter config, approved emblems and terminology, member/associate/section access.
- Browser admin, invitations, secure auth/MFA, event calendar/RSVP, group announcements and privacy controls.
- Responsive accessible website; offline-read event basics; UK/EU locale support.

P1 — riding and safety:
- GPX import/export, route/meetup waypoints, fuel/rest stops, sign-in roster, road captain and sweep roles.
- Dual guardian status, opt-in location sharing, last-fix age, safe-home confirmation, explicit incident/SOS and breakdown assistance.
- Local chapter rescue volunteer directory with consent-based contacts and opt-in availability, not a substitute for emergency services.
- External navigation handoff, rider group intercom through cellular data and compatible helmet Bluetooth.
- Music audio focus/ducking and interruption recovery.

P2 — clubhouse:
- Familiar threaded group chat, media, mentions, unread separators, moderated banter, polls and private channels.
- Optional Ladies/community sections, Almoner's restricted welfare area, memorial/tribute pages (consent and next-of-kin process).
- Shared event photo books, trip memories and mileage challenges; opt-in and privacy-aware, not surveillance by default.
- Cross-chapter invitations and events, with explicit federated visibility and no automatic data pooling.

P3 — finance/charity:
- Charity event public pages with verified donation impact, sponsors, volunteers, tickets/raffles subject to law.
- Merchandise shop with controlled insignia and merchant-of-record/charity settlement accounting.
- easyfundraising approved referral links; avoid fake donation/discount attribution.
- Shared ride costs and treasurer settlement; UK payment provider, never copy NL iDEAL-specific flows.
- Proper accounting for gross revenue, costs and net charity proceeds.

## Important boundaries
- Public research does not grant rights to third-party source code, artwork, logos, trademarks or databases.
- WSMBA website expressly identifies its own trademarked roundel; do not ship any chapter insignia without permission from relevant rights holder.
- No central Widows Sons membership API/authority is assumed. Product works for any club, with isolated groups.
- Protect welfare, emergency contacts, medical details, location histories, payments and member-only communications; enforce backend-level policy and short location retention.
- Do not treat app-store descriptions as evidence of operational effectiveness or safety suitability.
- Keep ride features usable for roadside stops, and avoid requiring screen interaction while riding.
