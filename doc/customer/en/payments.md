---
title: "Connect providers and manage collections"
summary: "Configure a collection provider, validate checkout results, and track payments, refunds, and recurring charges."
---

## Before you start

The Payments module must be enabled. Sign in as an administrator and open **Settings → Payment providers**. Have the provider account, required payment-product approvals, and credentials for the intended environment ready. Ask support if the module, provider, or connected checkout is unavailable.

This guide covers money collected from your customers or members. Your Anysys service subscription and its invoices are managed separately in [Billing](billing).

## Steps

### Configure a collection provider

1. Open **Settings → Payment providers**. Review the available provider cards, then select **Configure →** for the provider you intend to use.
2. Choose **Test** or **Live**. These are separate saved accounts, not a switch that copies credentials. Confirm with support which environment your workspace's checkout uses.
3. Under **Connection details**, replace any unset **Merchant account identifier** with the required account or application identifier. This identifier must be unique across organizations for that provider.
4. Fill every provider credential field using the setup below. Choose **Default currency** from the offered currencies. Leave **Notify URL override** blank for the standard notification address unless support has supplied a specific override.
5. Select **Save changes**. Correct any form errors; a successful save returns to the provider gallery. Reopen the same provider and environment to verify the saved identifier and credential-status text. Blank credential values retain existing stored values, so blank or masked inputs do not mean stored credentials were erased.

![Disabled, unconfigured payment provider in Test with blank credential fields, Save changes, and Test saved connection.](/help/docs/screenshots/en/payment-settings.png "Connection details and saved-connection testing are separate steps; save new values before testing.")

### Prepare the fields for your provider

Use only the provider offered to your organization; ask support to confirm notification setup with you.

- **Alipay:** enter the application's App ID as **Merchant account identifier**. Supply **Merchant private key (PEM)** and **Alipay platform public key** for RSA2 public-key signing, not certificate-mode files. The application needs approval for the payment flows you will use.
- **WeChat Pay:** enter the merchant number as **Merchant account identifier**. Supply **App ID (official account / mini program)**, the 32-character **APIv3 key**, **Merchant private key (PEM)**, **WeChat Pay platform public key**, and **Merchant cert serial**. Confirm the relevant Native, H5, or JSAPI approvals, domain/directory registration, and refund-notification setup in the merchant platform.
- **Stripe:** supply **Secret key**, **Publishable key**, and **Webhook signing secret** from the same test or live account setup. Use a unique merchant routing identifier. Ask support to confirm the matching signed-notification endpoint and event selection; test and live webhook secrets are separate.
- **PayPal:** supply **Client ID**, **Client secret**, and **Webhook ID** from the same Sandbox or Live REST app, plus a unique merchant routing identifier. Register the matching app webhook with support and verify a real payment and refund notification.

:::note
The app's **Test** account is its Sandbox record; it does not automatically select a vendor sandbox. Current Alipay and WeChat Pay adapters use their normal vendor endpoints even with a Test account. Stripe requires matching test/live keys; PayPal uses the account's Sandbox/Live API. Confirm the intended vendor environment before making a payment.
:::

### Test the saved connection

:::note
Current Alipay and WeChat Pay connection checks return an assumed result without contacting the vendor. Even **Saved connection verified** does not prove checkout, refunds, or signed notifications work.
:::

1. Reopen the saved provider/environment and select **Test saved connection**. This reads saved values, not your unsaved inputs; you can test while the provider is disabled.
2. Read the result. If it fails, correct the account/environment or credentials, save, and test again. Testing does not enable the provider.

### Enable the provider and validate checkout

1. Return to the gallery and check the card's displayed **Environment** before enabling it. The toggle saves immediately and applies only to that displayed account; it does not enable every environment. If the gallery shows a different environment from the one you configured, ask support to arrange activation of the required account. **Set as default**, when offered, is a separate immediately saved choice requiring an eligible configured provider.
2. Open your organization's connected checkout and complete an agreed transaction with the intended provider and currency. This is an actual payment; use the correct vendor test setup or an approved live amount.
3. Check the result page, the provider's record, and **Modules → Payments → Transactions** for the same reference, amount, and status. Ask support to verify signed notifications and, when needed, a refund or saved-card flow before relying on the setup.
4. An eligible member signed in to this organization can select **Save this card for future payments** in the Stripe provider-selection form before starting checkout. It is unchecked by default. Other provider forms do not submit Stripe's consent, and the later secure payment widget does not offer a second save-card choice.

### Check a payment

1. Open **Payments**, or **Modules → Payments → Transactions**.
2. Locate the order reference and compare its provider, amount, currency, and status with the customer's report. Open the reference or **View** for details.
3. A checkout may show a QR code, redirect to a payment app, or offer a secure payment form, depending on the configured provider and device. Direct customers through your connected checkout rather than requesting their payment details in a support message.
4. If the result is pending, check the transaction again before asking the customer to pay a second time. Use the provider's confirmed result and contact support when the records disagree.

### Refund a captured payment

1. Find a **Succeeded** transaction and select **Refund**.
2. Verify the order reference and original amount. Enter a positive refund amount in the displayed currency and add a reason. For example, refund `10.00` from a captured `25.00` payment when a partial refund is appropriate.
3. Select **Issue Refund** once and read the result. A processing notice means the refund is not yet complete.
4. Check the provider result before submitting another refund. The total of completed and in-progress refunds cannot exceed the captured payment, even if the form displays the original amount as its maximum.

### Manage recurring payments

1. Open **Modules → Payments → Subscriptions** and select **New subscription**.
2. Choose an eligible saved payment method. For example, enter plan name `Monthly membership`, amount `25.00`, the intended currency, and a monthly billing cycle. Select **Create Subscription**. A member must first have an active, confirmed saved card; available providers determine recurring support.
3. Open the subscription to review its status and next charge. Use its cancellation action when the recurring arrangement should end, and confirm the resulting status.
4. Review **Reconciliations** for available settlement files and downloads. Use **Disputes** to review recorded payment disputes; contact support or the provider for follow-up.

## What to expect

Transaction and subscription lists show the latest 100 records. A succeeded payment is different from a completed refund. Members use only their own payment services, saved cards, and subscriptions when those services are available in their portal.

## Troubleshooting

- **No providers in the gallery:** contact support to check module and provider availability.
- **No payment methods at checkout:** check the enabled account, merchant identifier, every saved credential, currency, and checkout environment. A connection-test notice alone is not evidence of readiness.
- **New credentials appear to have no effect:** save them first, reopen the same environment, and test the saved connection. Do not paste credentials into a support message.
- **The gallery shows the wrong environment:** its card represents one account, preferring an enabled account and otherwise the Test account. Do not enable it expecting the Live account to change; tell support which environment needs activation.
- **Refund rejected:** confirm capture, a positive amount, and the remaining refundable balance.
- **No saved card for a subscription:** ask the member to complete card setup in their own account.
- **Missing settlement data or an older transaction:** provide the order reference, date, and provider to support.

## Related guides

- [Forms](forms)
- [Settings](settings)
- [Billing](billing)
- [Support](support)
