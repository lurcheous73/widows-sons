# Widows Sons — Heritage & Road design brief

Implementation brief 1.1 · 19 October 2026 · native iOS 0.7.0.

This records the owner's Swift, self-hosting, communications, tracking, messaging
and CarPlay instructions. The interface specification below is complete for the
current ride, communications and ordinary clubhouse milestones. Chapter policies, eligibility,
official artwork and commercial/welfare approvals remain consultation decisions;
this document does not represent their approval or a completed full-platform build.

## Product and identity

An approachable chapter clubhouse, with a practical ride companion underneath.
Public visitors read chapter stories and discover rides. Signed-in members carry
their membership, plan a ride, message the chapter and choose whether to share
their position. Guardians coordinate a specific ride without becoming chapter
administrators. CarPlay provides communication controls while connected to a
compatible vehicle or motorcycle head unit.

The active iOS implementation is Swift 6 and SwiftUI, minimum iOS 17, using native
MapKit, Core Location, EventKitUI, SiriKit, CarPlay and CallKit. Text and ride
services remain on Canada VM20000. LiveKit supplies voice transport. There is one
chapter data source shared with the editable website.

| Element | Specification |
| --- | --- |
| Background | Charcoal `#111820` |
| Cards | Slate `#1B242D`; border `#35404A` |
| Primary action | Brass `#C49A59`, charcoal label |
| Body text | Off-white `#F4F0E8`; secondary `#B8C0C5` |
| Urgent request | Red plus explicit SOS text and warning icon; never colour alone |
| Display typography | Georgia, scaled with Dynamic Type |
| Controls and body | Native system type, native semantics and accessibility |
| Shape | 20-point cards, 12-point controls, 24-point hero |
| Composition | 24-point horizontal margins; readable 712-point content limit |
| Imagery | Subtle road ribbon; WS monogram as a development mark |
| Official insignia | Only approved supplied assets; no invented chapter insignia |

The phone uses the Heritage & Road palette. CarPlay uses Apple's templates and
system sizing/appearance. Do not reproduce the phone layout, Georgia type, tab
bar or long reading cards on the vehicle screen.

## Information architecture

Five phone tabs remain consistent: Chapter, Rides, Comms, News and Member. Detail
screens use native back navigation. An active ride is reachable from Rides and
Comms. A request badge opens that ride's log from anywhere in the app.

| Screen | Primary content and actions | Required states |
| --- | --- | --- |
| Chapter | Welcome, communications entry, latest story, next ride, membership | Fresh content, saved public reading, empty chapter, retry |
| Rides | Upcoming/My rides, Guardian duty invitations | Guest, verified member, no dates, no personal RSVPs |
| Ride details | Date/place, description, calendar editor, RSVP, briefing, chat, join | Going/Interested/Not going, busy, rejected save, expired ride |
| Ride briefing | Meeting point, departure notes, check-in window, stops, GPX map/export | Published briefing, missing details, conflict, route unavailable |
| Guardians | Lead, Sweep, deputy, responder; nominate/accept/decline/handover | Offered, accepted, unavailable, replacement pending, withdrawn |
| Live ride | Consented rider map, fix ages, check-in, intercom, Stop, Home, Leave | Sharing off/on, awaiting permission, stale signal, offline removal, lease ended |
| Requests | Help/SOS/check-in, server receipts, individual acknowledgements, resolution log | Unsent, received, acknowledged, responding, resolved, reopened |
| Guardian roster | Joined riders, check-in needed, lease ended, home, left, assisted | Unconfirmed arrival remains unresolved; no automatic crash state |
| Comms | Intercom, chapter/ride/DM conversations, new member message | Guest, connecting, muted, speaking, reconnecting, no messages |
| Conversation | Message history, composer, retry, unread, removal/report/block | Pending send, failed send with draft retained, received reply, removed message |
| News/article | Search, article text, approved website link | Empty, search has no results, online, saved reading |
| Member | Invitation activation, verified card, RSVP summary, sign-out, privacy/licences | Guest, invalid/expired invite, online verified, offline verification required |

## Primary journeys

1. **Get ready:** read a ride → RSVP Going → review briefing, stops and route →
   optionally save an editable calendar entry → join live ride with sharing off.
2. **Share deliberately:** choose Share → allow native location permission →
   see a sharing indication and expiry → Stop removes the last fix. Rejoining or
   restarting the app never silently restores GPS or microphone publication.
3. **Stay in touch:** choose a chapter/ride conversation or member → write/send →
   show a server-confirmed message; a failed send retains its draft and retry ID.
4. **Speak:** join a voice room muted → enable the microphone or push-to-talk →
   clearly show speech/mute/connection state → Leave ends the session. CarPlay
   speech uses a maximum 30-second burst with a separate Mute action.
5. **Ask for help:** choose Help or SOS → review and confirm → show local queued
   or server-received status → show Lead and Sweep acknowledgements independently
   → responding → resolution with reason. No state implies emergency dispatch.
6. **Guardian handover:** organiser offers a road role → nominee accepts → old
   assignment is replaced and the event log records the handover. Declining an
   offer leaves the existing Guardian in place. A deputy promotion is explicit.
7. **Finish:** rider chooses Home/Leave → coordinates are cleared → Guardians
   see the arrival/departure receipt. A Guardian can record confirmed assistance
   without claiming home arrival. Closure refuses unresolved riders or requests.

## Ride detail and Guardian behaviour

Briefing, Guardians and Requests are three segments of one ride detail area.
The organiser or accepted Road Captain edits the briefing and planned route.
An edit holds its original revision; a conflicting save requires a refresh and
never silently overwrites another organiser's changes. Stops preserve their IDs.

GPX import is limited to 256 KiB, 4,000 valid route/track points and 100 segments.
Disconnected segments remain disconnected. Import keeps only planned geometry
and the route name, discarding source author details and track timestamps.
Export includes planned geometry only. Rider positions are never converted into
a downloadable ride history. Stop directions open Apple Maps. The app's GPX map
is a route preview and does not claim turn-by-turn navigation.

Only a delegated organiser nominates road roles. Lead, Sweep and the designated
responder receive incident access after accepting and remaining Going. The
deputy does not acquire incident access until explicitly promoted. A normal
organiser has no automatic incident-reading right. None gains membership,
finance, private-message or Almoner rights from a road assignment.

Requests appear in the app while connected. The server's receipt, each person's
acknowledgement, and a person responding are distinct facts. A check-in after a
request is visible to the Guardians without silently resolving the request.
Resolution and reopening require a reason and preserve the shared history.
An independent Guardian can continue when the other is offline. Automated
background push/escalation to outside safety contacts remains a later integration.

## CarPlay design

The first companion uses the **Communication** category, matching the current
priority. Two system tabs: Intercom and Messages. No custom maps or social feed.

| Vehicle action | Behaviour |
| --- | --- |
| Join chapter/ride intercom | Current membership check; joins muted |
| Speak | Explicit microphone action, maximum 30 seconds; Mute remains available |
| Leave | Ends voice, including when the connection is recovering |
| Conversation selection | Conversation title/unread count only; Siri reads/composes/replies |
| I'm OK | Sends a check-in for the already joined ride; distinguishes failed delivery |
| Ask Guardians for help | Short confirmation; records/queues a help request; no dispatch claim |
| Required sign-in/permission | Explain availability without instructing the rider to manipulate the phone |

The implementation declares Send Message, Search Messages, Set Message Attribute
and Start Call SiriKit intents. CallKit owns physical-phone call activation and
interruption handling. The Simulator uses the existing audio transport because
it cannot validate the physical CallKit/headset path. Real Siri recognition and
message-reading flows need signed-device acceptance testing.

The `WidowsSons-CarPlay` scheme uses a separate entitlement configuration.
Apple must approve `com.apple.developer.carplay-communication` and the developer
must use a matching provisioning profile for real CarPlay distribution. The
ordinary phone build does not falsely carry a granted CarPlay capability.
No Apple request or legal addendum has been submitted on the owner's behalf.

Apple's 13 October 2026 guide restricts category combinations and reserves the
CarPlay map template for navigation apps providing turn-by-turn guidance. A
full custom convoy map on CarPlay is therefore a distinct product/category
decision. Current planned-route directions can use Apple Maps. Sources:
[CarPlay Developer Guide](https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf),
[entitlement setup](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements),
[SiriKit handler dispatch](https://developer.apple.com/documentation/sirikit/dispatching-intents-to-handlers).

## Connectivity and privacy states

- Public editorial content can be read from the separate public cache. Messages,
  member cards, Guardian logs and live locations are not in that cache.
- Active GPS and audio leases are explicit and time limited. Position pins show
  their age, change after 30 seconds and disappear at two minutes. A lost signal
  never creates an accident label or a safe arrival.
- Sign-in is device-only Keychain, available after the first unlock since reboot
  so the paired, locked phone can serve Siri/CarPlay. The queue requests the same
  after-first-unlock file protection and is excluded from backups. Physical file
  encryption/lock behaviour cannot be established by a Mac Simulator test.
- Pending help requests store no coordinates or sign-in token. They retain the
  same retry identifier, need reconfirmation after 15 minutes and are removed at
  sign-out. The app does not retry by inventing a new incident.
- Messages use production transport encryption, not a claim of end-to-end
  encryption. Audio is not recorded by this deployment.
- No microphone, location prompt or account activation starts merely by opening
  CarPlay. New permissions must be prepared when safe; the display reports a
  missing permission rather than asking the rider to operate the phone.

## Other sections in the full consultation

These define the rest of the product's design direction and are not presented as
working services in the current native build.

| Area | Design and access boundary | Prerequisite for implementation/launch |
| --- | --- | --- |
| Community sections | Named, configurable sections with explicit invitations; no inferred gender/eligibility | Chapter chooses names, membership rules and moderators |
| Albums/memories/memorials | Consented media, captions, report/removal, deliberate visibility | Upload/retention/moderation decisions |
| Announcements/polls/docs | Separate reading and publishing rights; clear voted/not-voted receipts | Audience, governance and voting rules |
| Charity/easyfundraising | Verified cause, approved outbound link, clearly sourced totals | Confirm cause link, beneficiary and content |
| Shop | Catalogue/variants, restricted insignia, checkout, orders, collection/delivery | Legal seller, fulfilment, payment provider, refund policy |
| Welfare & Almoner | Discreet contact path and independently delegated case workspace | Appointed Almoner, eligibility, confidentiality/retention decisions |
| Administration | Browser console with scoped capabilities, audit history and MFA | Approved operator roles and member lifecycle workflow |
| Inter-chapter | Explicit guest invitation and event scope | Chapter agreement and tenancy acceptance tests |

The design completion point is a reviewable, specified set of journeys and
states. It is separate from full implementation, Apple approval, public launch
and the physical acceptance trial.

## Deferred physical acceptance

Once the owner is ready, use two signed iPhones plus a compatible CarPlay head
unit and helmet headsets. Check spoken messages and read receipts, intercom both
ways, mute/PTT release, speech timeout, screen lock, incoming calls, headset
disconnect, music ducking/restoration, mobile-network handover, offline help
retry, GPS age/expiry/Stop/Home, both Guardian receipts and battery usage.

Each result should record phone/OS/headset/head-unit models and network. Simulator
and API checks support development; they do not substitute for these trials.


## Community Sections extension — native 0.7.0

This extension uses the same Heritage & Road typography, colours, cards and five
tabs. Comms opens the clubhouse directory; Community Sections never appear as
CarPlay/Siri conversations. Ride controls stay in the existing riding surfaces.
No real chapter section or membership policy has been created by the build.

| Screen | Content and actions | Permission and failure states |
| --- | --- | --- |
| Comms / clubhouse entry | Clear Community Sections card beside the intercom/messages journey | Online member verification required |
| Community sections | Named groups, purpose, joining policy, membership/availability labels | Invite-only groups hidden from uninvited members; chapter configuration delegates can see names/settings without contents; no public directory |
| Section | Description, explicit Join / Request / Accept, newest discussions, pinned posts within loaded history, earlier posts, Leave | Pending/invited cannot read; paused hides content; archived permits existing-member reading; removed access clears private data when checked |
| New post | Discussion, optional moderator announcement, or informal poll; title/body | Server-confirmed delivery, stable retry identifier, changed unconfirmed content gets a new identifier; failed sends remain in memory while the editor is open |
| Poll editor | Two to eight distinct choices, closing time up to 90 days | No edits to question/options after publication; no eligibility inferred; poll is not secret or binding |
| Conversation / poll | Author/date/body, aggregate choices, your selected choice, comments and earlier history | One choice per member, change/withdraw before closure; moderator may close early; server rejects expired or archived writes |
| Members & moderation | Pending requests/invitations, scoped role changes/removal, reports and activity | Active section moderators only; last active moderator needs a replacement; chapter administration alone cannot open it |
| Section settings | Name/purpose, joining policy, active/paused/archived | Chapter section.manage plus active moderator membership; revision conflict asks refresh; access/availability change gets an explicit confirmation and audit |
| Content report / removal | Written reason/outcome | Reports remain pending until reviewed; no urgent dispatch; removed text erased from live records, visible marker retained |

Section content, memberships, reports and drafts stay out of the public cache.
Views and sheets clear private state when the phone leaves the foreground,
including when a CarPlay communication session stays connected. Every private
read/write checks the server session and section membership. Screens refresh on
open, return and pull-down; this milestone does not claim background alerts or
live push for section posts/invitations. Leaving does not erase past posts,
comments or poll choices. Names/settings may be visible to chapter configuration
delegates, but private content/rosters require the explicit section role.

Native review uses clearly labelled disposable QA members/groups and removes
them afterwards. The wider brief still includes section documents/events/media,
public publishing rules, membership administration/MFA and independent Almoner
services; those are not claimed by this extension.
