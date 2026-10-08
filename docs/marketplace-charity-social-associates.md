# Marketplace, charity, social spaces and associate access

Status: product specification, not implemented.

## Design principles
This platform is brandable by any organisation. Each tenant configures section names, policies, eligibility and feature flags without modifying application code. Permission enforcement is server-side and audited.

## Chapter marketplace
- Listings for merchandise, patches (where authorised), apparel, spare parts and other permitted goods.
- Categories, photos, description, asking price, availability, pickup/delivery and seller contact choices.
- Distinguish **chapter shop** (official items) from **member classifieds** (peer-to-peer).
- Optional basket/orders for official stock, inventory quantities, order statuses, refunds and reports.
- Payments via an appropriate third-party processor; no storage of card details by the platform.
- Approval/moderation, takedown/reporting and anti-fraud protections.
- Do not permit prohibited or restricted goods in member listings. Organisations set their own additional listing policies.
- Marketplace visibility and ability to post/buy are separately configurable by role.

## Charity and community service
- Charity events, fundraiser campaigns, volunteering sign-up, attendance and activity reports.
- Targets and progress, named beneficiaries, donation links through approved payment providers and receipts where applicable.
- Distinguish donations, sponsorship and purchases; record expenses and disbursements for authorised treasurers.
- Public shareable charity pages can expose campaign totals without disclosing member records.
- Donations are subject to applicable charity/fundraising compliance and payment-provider rules. Do not imply Gift Aid eligibility automatically.

## Banter and chat
- Chapter announcements, discussion boards / banter, image posts, polls, event conversations, private and group messaging.
- Separate opt-in channels for social, rides, mechanical advice, charity activities and optional community sections.
- Moderation tools: report, mute, restrict, remove, retention controls and audit trail.
- Clearly distinguish private chats from announcement channels. Use suitable encryption for sensitive personal messages.
- Notifications configurable by channel; no default sharing of private chat content with administrators.

## Associate members
Associate is a configurable **membership type**, not the same as an administrator or on-road guardian.
- Tenant-specific roles: full member, associate, invited guest and any local membership classifications.
- Assign permissions independently for directory visibility, calendar, event RSVP, charity involvement, marketplace view/post/buy, banter and chats, and optional Ladies / Families / Supporters sections.
- Sensitive chapter minutes, finances, membership records, ride locations and administration remain closed unless specifically authorised.
- Member rights may change when membership status changes; access revocation must be enforced immediately.
- Section membership is permission/approval-based, not automatically inferred from gender, family relationship or other sensitive attributes.

## Initial L&R proposal (to confirm, not a final policy)
| Capability | Full member | Associate |
|---|---|---|
| Public/group announcements | Yes | Yes |
| General social / banter | Yes | Yes, if enabled |
| Events RSVP | Yes | Eligible events only |
| Charity and volunteering | Yes | Yes |
| Chapter shop | Yes | Yes |
| Member classifieds | Yes | Configurable |
| Member directory | Member-configured | Limited |
| Ride live position sharing | Explicit consent | Explicit consent if participating |
| Private committee documents | No, unless appointed | No |
| Admin portal | Only if separately authorised | No by default |

## API and data model for implementation
Organisation-scoped tables: marketplace_listing, order, order_item, campaign, donation_reference, volunteer_signup, channel, post, message, membership_type, role_grant and capability_rule.
All entities include organisation_id and a policy-checked creator. Role permissions checked for both reads and writes, not just by hiding interface elements.

Never put sensitive credentials, financial data, personal member information or private chats into public GitHub fixtures.
