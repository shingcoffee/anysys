---
title: "Manage your service subscription and invoices"
summary: "Choose service capacity, verify recurring payment authorization, manage renewal, and keep invoice records."
---

## Before you start

Sign in as an administrator and open the **Billing** group under **Settings**. You are managing the service subscription for your own organization.

Service billing is separate from the Payments module, which tracks money collected from your customers or members. Confirm which charge you are investigating before changing a subscription or payment method.

## Steps

### Review or change your plan

1. Open **Settings → Plan**. Review the current subscription status, price, currency, billing period, trial end or renewal date, and any scheduled cancellation.
2. Compare the available plans:
   1. Check billed price, currency, and billing interval. A yearly plan's monthly equivalent is a comparison value, not a monthly charge.
   2. Compare enforced page, entity, and member limits with current usage. Paid limits come from the accepted plan snapshot; changing the catalog does not change purchased terms.
   3. A customer can receive a paid trial at most once. Moving from a free plan or switching plans does not restart it.
3. For enrollment, open **Review subscription** and select **Subscribe** after reviewing its terms. For an existing live subscription, select **Review plan change**, check the server-calculated charge and effective date, then **Switch**. Same-interval upgrades wait for proration settlement, including manual payment. Downgrades, equal-price changes, and interval changes are scheduled for renewal; trial changes are scheduled for trial end.
   A blocked review shows the reason first. It does not offer a charge estimate, confirmed effective date, or submission until the blocker is resolved.
4. Check the persisted request after submitting. A pending upgrade retains the current purchased plan. A positive-price initial subscription awaits settlement and uses finite free limits meanwhile. A pending change can be cancelled when no unresolved provider payment prevents it; resolve that request before selecting another target.
5. If you have a coupon, enter **Coupon code** in **Apply Coupon** or the initial subscription review. Accepted terms are saved at redemption. Duration counts eligible positive-price initial/renewal cycles from attachment; free and prorated invoices do not consume a cycle. Issued invoices are unchanged, and voiding does not restore a consumed cycle.

### Authorize a billing payment method

1. Open **Settings → Payment methods**. In **Payment authorization**, select the offered **Set up** action for your provider and complete any requested authorization for recurring service fees.
2. Alipay authorization opens a provider redirect/form and supports CNY only. Stripe uses a secure provider card form. Return to **Saved billing methods** and check both status and charge readiness: **Active** alone is not proof that the provider account, currency, and verified authorization are ready.
3. Use **Make Default** to choose the authorized method used for billing, then check its default indicator. Do not remove the only working method while automatic collection is expected.
4. Pending, failed, and removed methods remain visible. Lists show 25 methods per page; use the page controls for older authorizations. **Continue authorization** opens the existing pending attempt. Removal prevents new local charges immediately; provider cleanup may remain pending. Adding a method does not itself pay invoices or restore ended service.

### Stop or resume renewal

1. Open **Settings → Plan** and choose **Cancel Subscription**.
2. Read the confirmation and confirm only when you want renewal to stop at the end of the current period.
3. Verify **Scheduled cancellation** and its date. The subscription does not end immediately.
4. To reverse a scheduled cancellation before its boundary, use **Keep subscription**. It clears the cancellation schedule, not debt, and does not reinstate a cancelled plan change. Outstanding invoices are not waived and cancellation is not a refund.
   Cancel/keep controls follow the server's current eligibility, including payment conflicts and the cancellation boundary. A stored status or cancellation badge alone does not guarantee an action is available.

### Keep invoice records

1. Open **Settings → Invoices**, search invoice numbers or filter by status, and use the page controls to reach older records. Lists show 25 records per page.
2. Check invoice status separately from **Collection status**, along with billing period, due date, immutable lines/totals, failed collection count, and next scheduled attempt. Processing or authentication-required payment is not eligible for another charge.
   An **Uncollectible** invoice can still have a processing payment, required authentication, or settlement reconciliation. Follow its actual collection state; that financial classification alone does not mean collection is exhausted.
3. Use **Download** for the printable invoice view or **Print**. Your browser can print the view or save it as a PDF when supported.
4. Check that the opened or saved document has the same invoice number and total. **Download** opens the full document; it is not necessarily a direct PDF-file download.
5. When offered, **Pay invoice** retries the original authorized invoice; **Complete payment authentication** confirms its existing Stripe payment. Refresh to see verified settlement. Printable documents contain neither payment widgets nor client secrets.

## What to expect

Available billing providers and plans are managed for you. Customer administrators can recover eligible invoice payments; manual settlement and collection-policy overrides belong to the platform owner. When paid access is unavailable or saved grace has expired, finite free limits apply. Existing records remain readable; capped creates may be blocked. Ended service requires explicit reenrollment.

## Troubleshooting

- **No plans or payment providers:** contact support to check availability.
- **A plan change is rejected:** resolve existing payment, plan-change, or cancellation conflicts before retrying. The server checks the current state on every submit.
- **A billing form is rejected:** review the linked field errors and correct the submitted values. Invalid price text, blank entries, plan limits, and retry-schedule text remain visible for correction; a rejected form does not overwrite the saved record.
- **Subscription is past due:** review payment-method status and the invoice, then ask support about unresolved collection.
- **Authorization remains pending:** check the method's current status and provider result before authorizing again. Pending is not an active default payment method.
- **A charge looks wrong or an older invoice is absent:** reset filters, check later pages, then send support the invoice number and relevant dates. Payment recorded after an ended/expired request may require platform review rather than reactivate service.

## Related guides

- [Payments](payments)
- [Users](users)
- [Email](email)
- [Support](support)
