# Ordinary clubhouse sections — Swift 0.7.0

This milestone continues the consultation specification with ordinary Community
Sections and retains native 0.6.0 riding, Guardian, messaging and CarPlay code.
It creates no actual chapter groups, ranks, eligibility rules or membership
policies. The owner still plans the two-iPhone/headset/CarPlay trial later.

## Implemented

- Comms → Community Sections, using the Heritage & Road SwiftUI design.
- Named, optional groups with purpose, open chapter joining, moderator approval
  or private invitations. Invitations must be accepted by the recipient. Pending
  approval/invitation is not content access. All active membership types use the
  same explicit access rules; no gender or chapter rank is inferred.
- Discussions, moderator-only announcements, polls, text comments and pagination.
  Section creation/posts/comments use stable client IDs for uncertain retries.
  Changed unconfirmed post/comment content receives a new identifier. Native
  success depends on a server receipt; no optimistic “delivered” indicator.
- Informal polls: two to eight distinct immutable options; one current choice per
  member; aggregate counts; change/withdraw before deadline; moderator close;
  automatic deadline enforcement. The API never returns other voters' choices.
  Vote identities exist in the database: these are not secret or binding ballots.
- Moderators can invite, approve/decline, remove access, promote/demote section
  moderators, pin/unpin, remove content with a reason and review/resolve reports.
  Last-moderator checks count active chapter accounts. Removal is not a ban from
  the chapter and does not grant membership/finance/ride/welfare administration.
- Text removal erases the post/comment text in live records and leaves a marker;
  audit reasons/reports and backups may retain information under a future agreed
  retention policy. Leaving revokes access but keeps past contributions/votes.
- Optional renaming, join-policy changes, pause and archive without an app update.
  Paused means no content reading; archived means existing-member reading only.
  Explicit confirmation for native access/availability changes; optimistic
  revisions prevent overwriting another configuration change.

## Authority and privacy

`clubhouse_sections`, `clubhouse_memberships`, `clubhouse_posts`,
`clubhouse_comments`, `clubhouse_votes`, `clubhouse_reports` and
`clubhouse_activity` are new ordinary-group tables. The legacy reserved
`community_sections` / `section_members` tables are not migrated or granted to
this mobile role; they do not become an Almoner feature through this release.

Chapter `section.manage` permits creation and metadata discovery. Configuration
of an existing section also requires active section moderator membership. The
capability does not admit its holder to existing private sections, posts,
rosters, reports or activity. The creator explicitly joins their new group as
first moderator; this is disclosed by the native form. Only section moderators
see its roster. Invite-only groups are hidden from ordinary uninvited members.

Every endpoint is organisation scoped; composite foreign keys prevent member,
section, post and reported-comment mixing. Per-section PostgreSQL transaction
locks serialize permission changes with content writes/votes. The current
session/account is rechecked and locked inside the operation. Revoked sessions,
suspended accounts and removed memberships lose server access. Native responses
are guarded against sign-out/background changes and foreign section receipts.

No private section data is written to the public file cache, Siri intents or
CarPlay templates. Private view state and editors clear on background/verification
loss; the CarPlay communication service can remain separate. Screens recheck on
appearance/return/pull-down. There is no background section push, live subscription
or promise that an already-visible screen changes instantly after remote removal.

Post history pages contain 30 posts, comment pages 50; older content is requested
explicitly using IDs scoped to that section/post. Pinning moves a loaded post to
the top of the current page; it is not a global pinned-post index. Moderator UI
shows up to 500 current/invited/requested memberships and the latest 100 pending
reports/activity entries; the prototype chapter directory is bounded at 1,000.

## Provisioning and deployment

First section configuration delegates are appointed explicitly by the operator:

```sh
sudo -u postgres /srv/widows-sons/venv/bin/python backend/manage_sections.py grant \
  --organisation lr --member MEMBER_UUID --reason 'Approved chapter configuration delegate'
```

`revoke` removes that chapter capability. Both actions are audited, send no mail
and grant no existing section membership. The runtime role cannot modify
`role_grants`; ordinary moderation is delegated in the app by that section's
moderators. Emergency support/recovery of an orphaned section is not an implicit
administrator override and needs a separately agreed, disclosed workflow.

`deploy/install-sections.py` validates the dedicated VM/release path, adds the
schema/grants and restarts only the private mobile API. It preserves the earlier
service file, CMS, NPM, voice configuration and Cloudflare. Fresh mobile/comms
installers also apply the additive schema. The database remains a private review
installation; backup/retention and membership/admin MFA policy must be agreed
before a chapter pilot. No approved real role hierarchy is assumed.

## Acceptance record

The final delivery receipt records test totals, source commit and deployment.
Server tests cover guests, explicit joins, approvals/invitations, removed access,
capability separation, foreign tenants/foreign keys, moderator handover,
configuration conflicts, pause/archive, stable retries, comment removal,
poll validation/change/withdraw/closure, scoped reports and history pagination.
Native tests cover input/poll validation, permission labels, private state
clearing, foreign receipts, revocation and retries without credential-bearing
URLs. The simulator UI is reviewed with disposable chapter data before cleanup.

Physical phones, Siri recognition, CallKit/headsets, actual CarPlay display,
background delivery and battery use remain device acceptance work. APNs, media
attachments, section documents/events, public sections, formal voting,
member approvals/renewals/deletion self-service, shop/payments/fundraising and
independently protected welfare remain later milestones.
