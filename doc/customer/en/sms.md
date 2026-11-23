---
title: "Create targeted SMS campaigns and check delivery"
summary: "Manage contacts and consent, preview and launch an approved-template campaign, cancel remaining sends and read delivery reports."
---

## Before you start

SMS must be enabled for your organization. Sign in as an administrator and confirm that **Communication → SMS** is available. The sending service needs an approved sender and template, arranged by your service team.

Confirm that the recipient has agreed to receive this kind of message. For marketing, record the actual permission separately on the SMS contact with its evidence reference and consent statement. Adding a phone, syncing data or matching an audience does not grant permission. A number's absence from the opt-out list does not establish consent; recording a new grant does not remove an existing block.

Open **Settings → Text message limit** to view the daily sending allowance. This is read-only for customer administrators. Ask support if you need a different allowance or a new approved message template.

The SMS workspace opens **Campaigns**, with links to **Contacts**, **Segments**, **Messages** and **Opt-outs**. Campaigns personalize approved marketing templates through **Audience → Content → Schedule → Review**. Your service team controls template wording and sending accounts; the campaign form does not send arbitrary free text. Transactional messages can also come from a configured task or form that supports SMS.

## Steps

### Add contacts and record permission separately

1. Open **SMS → Contacts → Add contact**. Enter the phone and two-letter country context, such as `CN`, an optional name, and an IANA timezone such as `Asia/Shanghai`. Country does not determine timezone; a blank contact timezone falls back to the campaign timezone.
2. If needed, enter **Custom attributes (JSON)**, for example `{"city":"Shanghai","vip":true}`. Use at most 32 scalar attributes and 8 KiB total, with lowercase keys beginning with a letter. Nested objects and arrays are not supported.
3. Select **Save contact**. A new contact has Unknown marketing consent, not permission to send.
4. Open the contact and record a separate consent event. For **Grant consent**, enter the evidence reference, the recipient's actual consent statement, and its occurrence time, such as `2026-10-13T10:00:00+08:00`; it must have an explicit offset and cannot be in the future. For **Revoke consent**, provide the evidence reference; notes are optional for either action.
5. Review **Consent history** and **Send eligibility**. Events are append-only, so later corrections require another event. Revoke also blocks the phone for your organization; a grant does not clear an existing organization/service-wide opt-out.

Changing the phone resets marketing consent to Unknown, even if the replacement number had historical evidence; record fresh permission for that phone. Old evidence stays with the old phone. **Archive contact** retains evidence and campaign history and makes the contact ineligible; **Restore contact** does not automatically supply consent or remove a block.

### Preview and explicitly sync contacts from an Entity

1. In **Contacts**, select **Sync from Entity**, choose an accessible supported Entity and **Load fields**. Only ordinary Entity records are supported; native-model extensions and bridge sources are unavailable.
2. Select a real **Telephone field**, optional **Name field**, country and timezone. A field merely named “phone” is insufficient. Shared definitions can be sources, but only your organization's records are read.
3. Optionally map contact attributes to scalar Entity field slugs, for example `{"city":"city","vip":"vip"}`. No permission fields are imported.
4. Select **Preview first 100** and inspect created/updated/unchanged predictions, invalid phones and source/identity conflicts. Preview changes nothing.
5. Select **Sync this batch** to apply at most 100 records. If more remain, use **Preview next 100**, review, then explicitly synchronize that batch. Continuation keeps the original upper record bound, so newly added source records are not silently swept into this run.
6. Review each batch result, resolve conflicts and record consent separately. This is a deliberate data operation, not a scheduled background synchronization.

Same-phone updates keep existing consent; changed phones reset it. Sync updates mapped attributes, retains unmapped ones and preserves archived status. Conflicting source links/identities are reported rather than merged. Removing a source record does not silently remove a contact, and repeating a batch does not create permission.

### Define and preview a dynamic audience

1. Open **SMS → Segments → Create segment**, name it and add contact-field or scalar custom-attribute conditions.
2. Use AND/OR and nested groups deliberately. Conditions combine left to right unless grouped. An empty root considers all your organization's contacts, still subject to consent and sending eligibility.
3. Select **Preview audience**. Compare **Matched contacts**, **Currently eligible**, exclusions and sample contacts. Matching can include archived or nonconsenting contacts; it is not permission.
4. Select **Save segment**. Membership is dynamic, not a fixed saved list. A segment referenced by a campaign draft cannot be deleted until that reference is handled.

Invalid rules fail closed and never turn into all contacts. Mixed-type custom attributes are unavailable as audience fields. Campaigns must match at most 10,000 contacts; narrow the segment if that limit is exceeded.

### Prepare content and sending controls

1. Open **SMS → Campaigns → Create campaign** and name it. Under **Audience**, select a saved segment or **All contacts**; consent and eligibility still apply.
2. Under **Content**, select an **Approved marketing template** and map exactly its required variables. Use a contact field with an explicit fallback, a literal value, or the server-generated signed unsubscribe URL. Replace these illustrative keys with your template's actual variables:

   ```json
   {
     "name": { "source": "field", "field": "name", "fallback": "Customer" },
     "offer": { "source": "literal", "value": "20%" },
     "opt_out_url": { "source": "field", "field": "unsubscribe_url" }
   }
   ```

3. Permitted fields are `name`, `phone_e164`, `country_code`, `timezone`, curated `attributes.<key>` and `unsubscribe_url`. No code or expressions run. A missing/blank field uses its explicit fallback; without one that recipient is skipped. A variable-free template uses `{}`. Ask your service team to ensure the actual approved message contains its working opt-out route or supported reply instructions.
4. Select a **Sample contact**, then **Preview campaign** to regenerate the sample and counts. Selecting a sample does not add it to the audience or override consent. Text preview/segment estimates use an optional service-maintained mirror of approved content; without it, only variables are shown and text/segment estimates are unknown. Preview does not send a test SMS, save changes or reserve allowance.
5. Under **Schedule**, choose **Send now** or **Schedule campaign**. For scheduled sending, supply the local date/time and IANA timezone; correct nonexistent or ambiguous daylight-saving times.
6. Set controls, then select **Save draft**:

   | Control | Meaning |
   | --- | --- |
   | Quiet hours | Local start/end hours, default 21:00–09:00; start is included, end is excluded, and they must differ. Use the recipient's current timezone, otherwise the campaign timezone. Messages wait only before the deadline. |
   | Frequency window | 1–168 hours, default 24. One campaign attempt per organization/phone within the window, including attempts with Unknown results; this is a skip, not a promise to retry later. |
   | Send rate | 1–60 recipients per minute, default 60. This limits campaign admission; other traffic and the shared sending-account ceiling can further delay dispatch. |
   | Deadline | 1–168 hours, default 24, measured from intended start, not each recipient's admission. Quiet hours and other delays do not restart it. |

Incomplete drafts can be saved while you arrange a template, finish mappings or choose a scheduled time. Shared accounts default to one authorized sending attempt per second and may be configured lower by the service team; this is shared across organizations, campaigns and direct sends, not a guarantee of phone delivery speed. Daily/phone allowances also apply.

### Review the saved draft and launch separately

1. Open the saved draft and compare **Saved campaign settings**, current counts, exclusions, waiting contacts, personalized samples, intended start, absolute deadline and minimum estimated duration. The duration is a lower bound, not a delivery promise.
2. Resolve **Resolve before launch** items, such as missing marketing content, incomplete mappings, no eligible consented contacts, unavailable sending account or a past scheduled time. Save edits and preview again.
3. Use **Preview campaign** on the saved draft to refresh the review when needed, then choose **Launch campaign** or **Schedule campaign**. Review authorization lasts 15 minutes and becomes invalid if saved settings, audience rules, template content or selected account identity change. Refresh/review again if prompted.
4. Follow the campaign detail and **View report**. Launched campaigns cannot be edited or relaunched. A draft can be deleted; launched campaigns and reports are retained.

:::attention
Launch fixes rules, template content and settings; the audience is captured once when execution actually starts. Contact changes between review and start can change membership. At start the service freezes destination, personalization and eligibility for all matched contacts, including exclusions. A later grant/restore does not add an initially excluded contact. Later phone changes, archiving, revocation or opt-outs can block remaining sends without replacing their frozen content or destination.
:::

### Cancel remaining messages and read the report

1. For a Scheduled or Running campaign, select **Cancel remaining messages** if sending must stop. Pending recipients and linked queued messages without an attempt are closed. Repeating cancellation is harmless; messages already attempted cannot be recalled and continue receiving delivery updates.
2. Open **View report**. Compare matched/eligible-at-start, pending/admitted, attempted/API-accepted and current delivery outcomes. Also review terminal reasons and current delays separately.
3. Filter by recipient/message status, reason or name/phone, and open a linked message for diagnostics. Select **Download CSV** for all filtered recipient rows, not just the visible page. It includes destinations, states, times, failure codes and actual provider segments, with localized headers; variable values, consent evidence, raw responses and signed links are omitted.
4. Treat **Completed** as dispatch work finished, not every phone confirmed delivered. Attempted and API-accepted are historical milestones overlapping delivery outcomes; do not add them together. Delivery rate is Delivered divided by Attempted and is unknown before any attempt. Provider segments sum only reported facts, with missing counts shown, not a billing quote.

Recipients who follow a signed unsubscribe link first see a confirmation page with a masked phone; only **Confirm unsubscribe** records revocation and an organization-level block. Opening the link alone does not unsubscribe. Links expire after 365 days; a link for a changed phone still applies to its original number, not the replacement.

### Prepare and run an agreed test

1. Ask the person responsible for your setup which form or task sends the SMS and which approved template it uses.
2. Prepare its inputs:
   1. Use an agreed recipient, such as a team-controlled phone for a confirmation-message check.
   2. Use an international number beginning with `+` or `00`, or a valid China national number when the task uses the default country context. Spaces, hyphens and balanced parentheses may format the number; do not include explanatory text or an extension. Check other national formats with your setup team.
   3. Supply exactly the values required by the approved template, such as an appointment date when that template expects one. Do not add unrelated fields or nested lists/objects.
3. Complete the configured task once using its actual submission action. This admits a real SMS for background sending, not a preview; the task may also create records or payments.
4. Check the task's completion or error message before moving to the log. A successful task or queued result does not mean the phone has received the message.

### Find the message and check its receipt

1. Open **Communication → SMS**, then **Messages**, or **Modules → SMS → Messages**.
2. Search for the recipient number or approved template key. For example, paste the same number you used in the task; clear search if no row matches.
3. Use sortable columns and pagination to locate the relevant time, then open the message.
4. Compare destination, template, provider, state and vendor reference with your original task inputs. The details screen shows variable names but redacts all values; use the original task to check them. Review dispatch start, attempt count, sent/delivered times, expiry, provider event time/status and actual provider-reported segments. For Failed messages, inspect **Failure** code/text. Missing facts are marked Unknown or Not recorded. Check the team-controlled phone as well as the recorded state.
5. Keep the message reference and result for support. Confirm the current outcome before repeating the original task.

### Check opt-outs

1. Open **Modules → SMS → Opt-outs**.
2. Search for the recipient's number and review **Reason** and **Scope**. The list can include your organization's blocks and service-wide blocks.
3. Respect the opt-out. Do not change the number's formatting or switch tasks to bypass a block. If you believe a record is incorrect, ask support to review it with the recipient's context.

Verified STOP replies (including REVOKE/OPTOUT or the provider's STOP classification) and Twilio error `21610` can create a service-wide block. START/HELP replies do not automatically remove that block or record renewed permission in Anysys. Your list shows service-wide blocks only for recipients your organization has actually contacted; an admission-time blocked message does not reveal another organization's opt-out history.

## What to expect

| State | What it tells you |
| --- | --- |
| Queued | The task recorded the message for background dispatch. |
| Pending | An older record remains unresolved; this is not the new-send starting state. |
| Sent | The sending service accepted the message, not proof of phone delivery. |
| Delivered | A delivery receipt confirms success. |
| Failed | The provider rejected the send or reported failed delivery. |
| Unknown | Acceptance or delivery is uncertain; this is not permission to resend. |
| Suppressed | Sending was blocked before an external attempt. |
| Expired | The deadline passed before the sending attempt. |

The default direct/task sending deadline is one hour after admission; a configured task may use a different deadline. Campaigns instead use their absolute deadline from intended start. Disabling SMS or receiving an opt-out before dispatch can block an already queued message; marketing also rechecks current contact activity, phone and consent. Once an attempt begins, the service does not automatically send the same message again, even after a timeout or missing receipt. A late receipt can resolve an Unknown or Failed record as Delivered.

Retries that complete the message record only repeat database writes, not the SMS send. An Unknown message may retain a usable vendor reference from a partial or malformed response, allowing later receipt matching or provider queries; the reference itself does not prove acceptance or delivery. Provider-query waiting and aging begin at dispatch, with historical acceptance/creation times as fallbacks, rather than the time a new task was submitted.

An actual segment count appears only when the provider reports it. Campaign preview can estimate a rendered approved-content mirror when supplied, but the app cannot calculate an estimate from a provider template code alone, and segment information is not a price quote.

Provider event time can be the provider's resource-update time, including on an Unknown or Failed message. That timestamp or a segment count does not confirm delivery; look for the Delivered state and its receipt. Sent time records API acceptance, not arrival at the phone.

Approved templates require the expected values. Customer administrators review results here; sender approvals and template availability are managed for you.

## Troubleshooting

- **A contact matches but cannot receive marketing:** inspect consent, archived status, phone changes, opt-outs, missing personalized values and campaign frequency. Sync or a fresh grant does not clear a block.
- **Launch is unavailable or review changed:** save the latest draft, resolve blockers and review again. No active marketing template or configured account requires a service-team fix; an unsaved preview cannot launch its edits.
- **A campaign is waiting:** inspect current delays for quiet hours, campaign/shared-account capacity or daily/phone allowances. The absolute deadline still applies; an estimate is not a guaranteed finish time.
- **Cancel or Completed still shows unresolved sends:** already attempted messages can receive late receipts. There is no unknown-result resend or recall action; investigate the original message rather than launching a duplicate to get a clearer result.
- **No message appears:** check the task's completion message, clear log search, and inspect the relevant time. If still absent, give support the task name, time, and intended template before running it again.
- **A message fails:** open **Failure**, correct the recipient or required values if indicated, and ask support about vendor/template errors. Check whether the task already created another record or payment before retrying it.
- **The result stays Queued:** check its deadline and ask support to inspect queue/worker recovery. Repeating the task can create another message and other records.
- **The message is Expired:** ask support why dispatch missed the deadline and whether a new message is still useful before submitting another task.
- **The result is Sent or Unknown:** wait for a receipt and check the test phone; do not treat acceptance or a missing receipt as confirmed delivery. The service can query the provider when callbacks are missing, but some outcomes remain unresolved. Do not repeat an uncertain send merely to obtain a clearer status.
- **The result is Suppressed:** check the opt-out context or ask support whether SMS was disabled before dispatch. A START/HELP reply does not automatically unblock it.
- **The daily limit is reached:** wait for the allowance to reset or ask support about an adjustment.
- **SMS, a template or sending credentials are unavailable:** report the intended task, template and the task's localized error message to support. Missing sending credentials need a service-configuration fix before a new send can be queued.

## Related guides

- [Forms](forms)
- [Email](email)
- [Settings](settings)
- [Support](support)
