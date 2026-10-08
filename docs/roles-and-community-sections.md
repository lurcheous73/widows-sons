# Road roles, administration, and community sections

Status: design specification; not yet implemented.

## Separation of responsibilities

**Road Captain** is the lead rider **on the road** for an organised ride. The **Sweep / Tail Guardian** rides at the back. These are per-ride operational assignments, distinct from chapter administrator privileges.

Do not equate road leadership with the right to edit memberships, finances, account permissions, private messages or organisation branding.

The full chapter hierarchy and role names will be agreed later. For now, model **capabilities** rather than hard-coded rank: membership.manage, event.manage, ride.lead, ride.sweep, incident.respond, messaging.moderate, section.manage, finance.manage, branding.manage.

A member can hold multiple capabilities, delegated only within their organisation and for a specified scope (chapter, event, ride, or community section). Keep a record of who granted or revoked privileges.

## Ride roles

- Road Captain: lead rider and Lead Guardian for a specific ride.
- Sweep Rider: rear rider and Tail Guardian for a specific ride.
- Each receives appropriate rider safety alerts, visibility and communication functions, but no automatic general administrator access.
- A delegated replacement can take over a ride role with an auditable handover.
- Ride participation, incident alerts and safe-arrival confirmations remain opt-in and subject to privacy controls.

## Optional Ladies section

Some organisations may want a **Ladies section**, but it must not be compulsory or automatically created as a membership category for every tenant.

Implement configurable **Community Sections**:
- Each organisation may enable a section and set its display name (e.g. Ladies, Families, Supporters, Social, Associates).
- Dedicated section news, group discussion, events, documents and notifications.
- Membership and access by invitation/approval and explicit permissions, not inferred from gender or personal attributes.
- Section moderators can manage only their section, not the wider organisation.
- Support private sections with carefully enforced server-side access checks. Administrative support access must be constrained, auditable and disclosed.
- Allow sections to be open to all or membership-only, as defined by the group.
- Respect participants' privacy; no default disclosure of section membership to the public.
- Sections can be renamed, disabled, archived or added without modifying mobile app source code.

## Tenant isolation

Organisation A must never see the members, section content, messages, ride locations or permissions of organisation B. Enforce isolation in the backend and database, with automated tests.

## Open questions for later

Specific L&R hierarchy, eligibility rules, who approves membership and the exact Ladies section remit. These are organisational decisions, not assumptions baked into the code.
