---
title: "Review forms and manage access"
summary: "Review a form safely, launch your organization's form, and verify who can open and use it."
---

## Before you start

Sign in as an administrator and open **Content → Forms**. Forms are task pages used to collect or display information; they are separate from marketing website pages.

Identify whether the form belongs to your organization or is supplied as shared content. You can manage publishing and audience access for customer-owned forms. Shared forms have centrally managed names, definitions, and publishing; ask support when those need to change.

Before making a form public, decide what visitors should be able to see and submit. A public audience allows access without sign-in; member access requires an account.

## Steps

### Find and review a form

1. Open **Content → Forms**. Choose **All Forms**, a record-type group, or **Uncategorized** in the sidebar.
2. Search by name, such as `Registration`, and use **Status → Live** or **Draft** to narrow the list.
3. Open the row's more-actions menu and select **Preview**. Inspect the labels, required fields, instructions, and expected task. Previewing the layout is not the same as testing a real submission.
4. Select **Manage access** to open the publishing and audience panel. Review the form's status and the available audience links.

![Unlaunched form access panel with Launch and member and public visibility controls.](/help/docs/screenshots/en/forms-publishing.png "The access panel separates launch status from audience visibility; check both before sharing.")

### Fill in a form as an administrator

1. Select a launched form's name, or its **Fill in** button. The form opens inside the admin workspace; use **Open in new tab** from the row menu to keep the list open.
2. Complete the fields and submit. After a successful save you return to an empty copy of the same form, ready for the next entry.
3. In a dropdown that lists records, choose **+ Add new** when the record you need does not exist yet. Complete the record in the dialog and select **Create Entry**; the dialog closes and the new record is selected. Choose **Cancel** or press Esc to keep your previous choice.

:::note
Drafts and forms not visible to administrators show **Preview** instead of **Fill in**. **+ Add new** appears only for administrators; members and public visitors see the plain list.
:::

### Launch a customer-owned form and select its audience

1. Use **Launch** in the panel or row menu. If launch is rejected, read the error and ask support to resolve the form's setup before trying again.
2. Confirm that the panel shows the form as launched before checking audience access.
3. Set the intended audience:
   1. Keep administrator access, which is always included.
   2. Enable member access for signed-in members, or public access for visitors without sign-in.
   3. Note the coupling: selecting public also includes members; removing members removes public too.
4. Wait for each audience change to save automatically. Reopen **Manage access** and check the choices persisted.

:::note
Launch status and audience are separate. Audience switches save automatically; they do not launch an offline form. A displayed public link does not itself grant access.
:::

### Check the link and a real submission

1. Use the audience's **Open** link to check the launched form.
2. For member access, check the page with a designated member account. An administrator opening the member link receives a read-only preview; it cannot test member writes.
3. For public access, copy the displayed public link and open it in a signed-out browser.
4. Submit an agreed sample only if you intend to create or change actual data. For example, use a designated test member for a registration task; do not submit another person's information as a preview.
5. Read the completion or field-error message. If the task writes a record, check the intended record list before submitting again.

### Withdraw a form

1. Open your form's access panel and select **Take Offline**.
2. Confirm the offline state, then check its audience link is no longer usable normally.
3. Review website or email links that point to the withdrawn form and update them as needed.

## What to expect

A launched form still needs the correct audience to be reachable. A displayed public link alone does not grant public access. Draft or offline forms cannot be used through their normal audience links.

The Forms menu focuses on reviewing and distributing existing forms. It does not provide a customer form-layout editor. Request new fields or a new form through support, describing the task and intended audience. Shared forms can be used with your organization's data without giving you control of the supplied definition.

## Troubleshooting

- **The link is unavailable:** check launch state and audience, and confirm you copied the current link.
- **A shared form rejects a change:** ask support to manage the supplied form.
- **A submission fails:** note the field errors, correct the values, and confirm the result before submitting again.
- **Public requests are limited:** review **Settings → Public page protection** for your own public forms. Ask support about challenge configuration or shared forms.

## Related guides

- [Records](records)
- [Websites](websites)
- [Settings](settings)
- [Support](support)
