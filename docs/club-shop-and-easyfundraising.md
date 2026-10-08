# Club shop and easyfundraising

Status: specification only. No shop, payment or third-party integration is active.

## Shopping for Charity
- Each organisation may configure its own approved easyfundraising good-cause link and beneficiary.
- Members access an explanation and approved outbound link from their clubhouse login.
- easyfundraising is an external service, not our payment processor; do not assume its API, SSO, discount promises, or access to donation records.
- Refer members through provider-approved methods and show only verified donated totals.

## Club Shop
- Organisation-branded product catalogue for authorised patches, T-shirts, clothing, accessories and event merchandise.
- Size/colour variants, stock counts, restricted insignia, public/member/associate pricing, delivery and event collection.
- Admin product editor, order history, fulfilment, cancellation, refunds, transaction audit and reports.
- Optional public storefront but access-controlled products, with restricted patches available only to members authorised to purchase them.
- Use hosted PCI-compliant checkout such as an approved payment provider. Store no payment-card details.

## Paying proceeds to the charity
Determine the legal seller and merchant of record before launch. Preferred where legally and commercially supported: the nominated charity (or its authorised trading entity) owns the payment account, verified bank account and checkout, so receipts settle to that account directly.

**Gross receipts are not net profits.** Track cost of goods, postage, packaging, processing fees, taxes, refunds, and other agreed costs. Display gross revenue, expenses, net proceeds and confirmed charity transfers separately. If the chapter sells the goods, it must make and document a subsequent transfer of net profits; never promise an automatic charity payout without an approved, tested settlement arrangement.

Do not store payout banking details casually or permit an ordinary admin to change beneficiaries. Require finance-role approval and audit all changes. Confirm UK consumer rights, charity/trading, tax, VAT and restricted insignia requirements with the nominated organisation before launch. Ordinary merchandise purchases do not automatically qualify for Gift Aid.

## Implementation sequence
1. Brandable product catalogue, inventory models and administrator editing.
2. Verified hosted checkout, stock reservations, receipts and refunds.
3. Audited net-profit accounting, approved disbursement process and verified reporting.
4. easyfundraising approved links, charity campaigns and partner-based summary if supported.
