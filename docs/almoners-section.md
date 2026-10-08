# Almoner's Section

Status: requirements specification only. No live welfare records or messaging implemented.

## Purpose
An optional, confidential welfare and benevolence area for an organisation's appointed Almoner(s). This is distinct from the charity fundraising pages, general banter and shop. Different organisations can rename or disable the section.

## Member experience
- A prominent but discreet **Contact the Almoner** action, accessible according to each organisation's policy (including eligible associates).
- Choose to request support for oneself or to raise a concern about another person. Explain confidentiality and how the information will be handled before submission.
- Contact preference (phone/email/in-app) and suitable times, with a minimal free-text message. Avoid requiring detailed medical or financial information.
- Optional welfare event notices, check-in requests and support resources visible to the appropriate audience.
- Clear statement that the section is not an emergency-response service; use 999/112 for immediate danger.

## Almoner access
- **almoner** is a delegated, organisation-scoped capability, separate from Road Captain, Sweep and ordinary administrator permissions.
- Only the assigned Almoner and specifically authorised deputies can access confidential cases. A general chapter administrator must not automatically read welfare case notes.
- Almoners can acknowledge contact requests, assign a deputy, record follow-up tasks, close cases and export only where authorised.
- Members must not be exposed to another person's case or welfare correspondence.
- A request to support another member should not disclose their details to unrelated people or automatically notify the person named.

## Privacy and safeguards
- Welfare records may contain health, disability, family or financial information. Apply data minimisation, restricted access, encryption, explicit retention/deletion rules, audit logging and a UK GDPR/DPIA review before launch.
- No sensitive details in lock-screen push notifications or email subjects; push only says that a private message is available.
- Don't infer health conditions or share welfare cases with fundraisers, the shop, ride leaders or general chat.
- Include a process for reassignment when an Almoner leaves office, with auditable access changes and proper retention policy.
- Optional direct contact details should only be published with the Almoner's approval.

## Suggested interface
Member portal: **Welfare & Almoner** → Contact / Welfare Events / Resources.
Almoner workspace (restricted): New Requests / Follow-ups / Resolved / Resources.
Branding, terminology and eligibility controlled per organisation.
