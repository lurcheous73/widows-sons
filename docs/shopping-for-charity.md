# Members' Shopping for Charity Portal

Status: design specification only; no affiliate or fundraising-provider integration is active.

## Goal
Provide a signed-in member website and a mobile-app entry point where eligible members can discover participating external retailers and shop in support of a cause nominated by their organisation. Keep the experience **brandable and tenant-specific**.

## Important distinction
Shopping-through fundraising schemes usually generate a donation to a supported cause, **not a discount on the customer's purchase**. Show individual retailer deals or promotional discounts only when independently supplied and permitted. Never promise a donation, discount, or cashback where none has been confirmed.

## Possible UK third-party providers
- easyfundraising: https://www.easyfundraising.org.uk/how-it-works/ ; supports many community good causes and retailer referral donations.
- Give as you Live Online: https://www.giveasyoulive.com/how-it-works ; charity-linked retailer donations.

Before implementation, establish an approved cause account, eligibility, provider referral-link and promotional rules, permitted branding/API/widget or feed usage, donation reporting access, privacy implications, and any affiliate relationship terms. No public API or direct white-label integration is presumed.

## Member experience
1. Log into the chapter/community portal using the platform's existing member account.
2. Open **Shopping for Charity**; read the currently nominated beneficiary and the provider attribution.
3. Browse approved participating retailer links, categories and genuine offers.
4. Follow an external provider-approved referral link and sign in/register with the provider if required. Shopping and card payment happen on the retailer's website, never within our app.
5. See an explanation that eligible completed purchases may lead to a donation from the retailer; donated amounts, approval and payouts are tracked by the partner.
6. Where the partner explicitly permits it, display verified aggregate fundraising totals. Otherwise link to their reporting dashboard instead of fabricating figures.

## Admin portal
Organisation admins may:
- configure feature enablement, section title and imagery;
- set eligible member roles (including associate members);
- choose an approved provider and beneficiary via validated links/configuration;
- curate permitted retailer/category links, approved campaign notices and genuine special offers;
- see aggregate referral clicks recorded with minimal data; see donations only where authorised data integration or official reports permit;
- disable referral programmes without breaking other shopping features (the chapter merchandise shop remains independent).

## Data and security boundaries
- Do not collect retailer passwords, card details, purchases or third-party member transaction histories.
- No automatic SSO or affiliate tracking hacks; partner login is separate unless an authorised integration supports it.
- No unsupported scraping, cookie injection, link rewriting, hidden affiliate redirects, or unapproved reuse of provider branding.
- Record consent/legitimate basis for analytics; avoid member-level purchase profiling.
- Member access and organisation isolation must be enforced in backend policies.
- Clearly label external destinations and disclose referral and commercial arrangements.
- Payment/fundraising eligibility and disbursements belong to the approved partner and organisation; comply with UK charity/fundraising and privacy rules.

## Build approach
Phase 1: authenticated member page, approved external fundraising link, explanation of beneficiary and referral flow.
Phase 2: curated retailer links/categories if the provider contract permits.
Phase 3: verified donation summaries and reporting integration only if the provider supports access.

## Acceptance criteria
- L&R member and permitted associate can access the charity shopping portal.
- Member from an unrelated organisation sees only that organisation's provider and beneficiary.
- Non-member and suspended accounts cannot access member-only sections.
- External retailer links are valid, explicitly labelled and lead through provider-approved attribution.
- The portal does not promise discounts or donation amounts it cannot substantiate.
- Disabling provider A does not affect provider B or the chapter's own shop.
