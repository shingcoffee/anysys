---
title: "Prepare and send email"
summary: "Test reusable content, verify an audience of existing users, and submit a reviewed send or schedule."
---

## Before you start

Email must be enabled for your organization and the sending service must be ready. Sign in as an administrator and open **Settings → Email limit** to review your daily allowance. This limit is managed for you; contact support if it needs to change or delivery is unavailable.

Prepare the message and identify the intended existing users in your organization. For a first send, use a small audience you can verify. Test emails also use the sending service and can be blocked by limits or suppressions.

## Steps

### Write and test a template

1. Open **Communication → Email**. In the module sidebar, choose **Content → Templates** and select **New Template**.
2. Enter a name, subject, and body. For example, name it `Welcome email`; type `{{` in the subject or use **Insert token** in the body to choose the available first-name token. Use the picker rather than inventing a token name. Available fields are managed in **Settings → Email personalization**.
3. Select **Preview** and check layout, links, images, and plain-text fallback. The standalone preview displays token labels rather than sample values.
4. In **Send test email**, enter a mailbox you control and select **Send test**. Check the result notice and the message in that inbox; testing uses the real sending service.

:::note
Every test destination uses the signed-in administrator's personalization, not the destination user's profile. If your first name is Alex, the selected first-name token uses Alex even when you test to another person's mailbox. A real send activity uses each resolved recipient's context. Testing unsaved content does not save the template; custom entity fields currently remain blank in sent email until recipient-to-record linking is available.
:::

### Save and activate the template

1. When creating a template, select **Activate template immediately** before submitting if it is ready to use.
2. Select **Create template** or **Update template** to save the reviewed content.
3. If the saved template is not yet active, use **Set active** when it is ready.
4. Reopen the template and check the saved content and **Active** state. Only active templates appear in send activities.

### Create and check an audience list

1. Open **Audience → Lists** and select **New List**.
2. Enter a recognizable name, such as `Welcome test audience`, and choose **Type**:
   1. **Static list:** enter one existing user's email per line in **Member emails**, for example `alex@example.com` if that account exists in your organization.
   2. **Dynamic segment:** build **Audience conditions**, then select **Preview** to inspect matching users.
3. Select **Create**. Read both the save notice and any warning about unknown email addresses.
4. Open the saved list. Check the static members or preview the dynamic conditions again. For a members-only message, include the intended member accounts or narrow the offered conditions and inspect the matches.

![New email list form with Dynamic segment selected and Add condition, Add group, Preview, and Create controls.](/help/docs/screenshots/en/email-audience.png "Define and preview audience conditions here before selecting Create for a dynamic list.")

:::note
Lists resolve to existing users of your organization, including administrator accounts; **Member emails** does not enforce a member-only audience. Unknown addresses are omitted from a static list. Dynamic conditions are evaluated when used for sending, so a preview is a check of current matches, not a frozen recipient list.
:::

### Send or schedule

1. Open **Send Activity** and select **New Send Activity**.
2. Complete the builder's steps:
   1. **Audience:** name the activity and choose the verified lists within the displayed selection limit.
   2. **Content:** choose the saved active template.
   3. **Schedule:** choose **Send Now** or **Schedule at**. For scheduled delivery, check date, time, and time zone. Leave recurrence at **None** for a one-time send.
   4. **Review:** check the audience, content, and timing together. Recipients on several selected lists receive one email for the activity.

### Submit the reviewed activity

:::attention
With **Send Now** selected, final submission queues real delivery; it is not a draft-only save. Already-sent messages cannot be recalled. Confirm the audience and content before submitting.
:::

1. Select **Create** on **Review** to submit the activity, or **Update** when editing a pending activity. Correct any highlighted error before resubmitting.
2. Open the saved activity and check its name, lists, template, scheduled time, and status. A scheduled activity remains pending until processing starts; confirm the state before retrying.

### Monitor delivery or stop further sends

1. Open the activity to review its status and delivery counts. Check **Failure reason** if processing fails.
2. Edit a pending activity before processing begins if its setup needs changing.
3. Use the available cancellation action when you need to stop further delivery. Check the resulting status; cancellation does not recall sent messages.

## What to expect

The activity records processing and completion, while delivery counts distinguish sent, delivered, failed, bounced, and suppressed messages. A successful activity does not prove every recipient received the email. Some sending services report only **Sent**, without a later delivery confirmation.

Use **Analytics** and its report, deliverability, and engagement tabs to review results. **Audience → Suppressions** shows blocked addresses. Respect unsubscribes and complaints; do not remove blocks simply to force another send.

## Troubleshooting

- **The template is missing:** save its content, check **Active**, then use **Refresh templates** in the builder.
- **Test personalization shows your name:** this is expected; tests use the signed-in administrator. Check recipient-specific content through a deliberately reviewed small real activity.
- **A static list omits addresses:** check the notice for addresses that do not belong to existing users in this organization.
- **A dynamic list is empty:** review its conditions and preview again.
- **Sending fails or reaches a limit:** read the failure reason, check the activity state before retrying, and contact support. Do not create duplicate sends while delivery is still processing.
- **Metrics are absent:** check the date range and allow time for delivery or engagement events.

## Related guides

- [Users](users)
- [SMS](sms)
- [Settings](settings)
- [Support](support)
