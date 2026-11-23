---
title: "Manage your organization's settings"
summary: "Set registration, recovery, and admin MFA policies, choose member pages, and check public-form protection."
---

## Before you start

Sign in as an administrator for your organization. Open **Settings** to see the settings available for enabled modules, the member portal, and service billing. Use the settings search to locate a task by its displayed name.

Customer settings affect your organization. Some values are informational or managed by the service team. Contact support when a read-only limit needs changing or the required option or module is missing.

## Steps

### Allow or pause member registration

1. Open **Settings → Member registration**.
2. Set **Allow member registration** to **Enabled** or **Disabled**. For example, keep it disabled while preparing the member experience.
3. Select **Save** and check the saved choice. Disabling also pauses pending registration-confirmation links and confirmation resend requests until enabled again.

### Allow or disable password recovery

:::attention
Disabling recovery prevents reset emails and invalidates the use of already-issued reset links while disabled. It affects every account in your organization, including administrators. Arrange another way to recover access before saving Disabled.
:::

1. Open **Settings → Password reset** and review **Allow password reset**.
2. Choose **Enabled** or **Disabled**, then select **Save**.
3. Reopen the setting and confirm its saved state. If enabled, a user needing recovery can request a fresh link from the sign-in page.

### Require two-factor authentication for administrators

1. Open **Settings → Account security**.
2. Set **Require two-factor authentication** to **Yes** and select **Save changes**.
3. Check the saved choice. Administrators and owners must complete MFA enrollment or verification before protected access, including existing sessions that still owe enrollment. Members opt in through their own security settings; this tenant policy does not mandate member MFA.
4. Review **Roles & permissions** or **User access** when you need to check access scope. Built-in read-only permissions remain fixed.

:::note
**Session timeout (minutes)** and **Failed sign-in attempts before lockout** are stored preferences currently not read by sign-in enforcement. Saving them does not change the enforced timeout or lockout threshold. Ask support about actual sign-in behavior rather than relying on these values.
:::

### Choose what members see

1. Open **Settings → Member portal**.
2. Choose **Core pages**, **Member modules**, or **Record pages**. Core home, profile, and security pages are always available and cannot be hidden or reordered.
3. For optional pages, adjust member visibility. These changes save immediately. Showing a page does not give members access to other people's records.
4. Open a page's **Display settings** to adjust the offered navigation text, content columns, record details, empty-page message, icon, or order. For example, enter `My enrollments` as the display name of an enrollment record page. Select **Save** for display changes.
5. Check the result with a designated member account. Confirm that its own records and account services are shown as intended.

### Review module preferences

1. Use **Website** for site appearance and publishing, and **AI assistant** for its language preference.
2. Check **Email limit** and **Text message limit** for managed daily allowances. Use **Email personalization** for available email fields.
3. Use **Payment providers** for collection setup, and **Billing** for your Anysys plan, payment methods, and invoices.

### Set request limits for your public forms

1. Open **Settings → Public page protection**. Check whether protection is disabled, the provider is configured, or setup is unavailable.
2. Find your organization's public form under **Public page request limits**. Shared supplied forms are managed separately and are not editable in this list.
3. Choose a preset, such as **20 requests / minute / IP**. Presets save immediately. For **Custom limit…**, enter the request count and time window, then select **Apply**.
4. Reopen the setting and check the saved limit. Use **Open page** for a signed-out check of the intended form.

:::note
Saving a page limit does not configure platform captcha keys or prove a challenge works. Protection requires an enabled module and a configured provider; check readiness and the actual visitor experience. Ask support if the provider is unavailable or a shared form needs changes.
:::

## What to expect

Registration, recovery, admin MFA, and display preferences require a successful save. Member visibility and public-form limit presets save immediately; custom limits require **Apply**. Stored timeout and attempt preferences retain the limitation above. Module availability, sending/recording limits, and shared definitions are managed for you.

## Troubleshooting

- **No matching setting:** clear the settings search and check enabled modules.
- **Changes disappear:** confirm the save succeeded and inspect validation messages.
- **Members still see a core page:** core pages cannot be hidden.
- **A public form is absent from protection settings:** check that it is your organization's public form, rather than shared content or a website page.
- **No verification challenge appears:** check protection readiness and the page limit, then report the form name and observed behavior to support. Customer settings cannot repair provider credentials.

## Related guides

- [Users](users)
- [Forms](forms)
- [Websites](websites)
- [Billing](billing)
- [Support](support)
