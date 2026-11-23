# SMS campaigns — UX specification

Date: 2026-10-13 · Status: **READY_FOR_FRONTEND** · Contract: v1

Architecture, schema, routes, forms, and service results: [frozen implementation plan](../../plans/2026-10-13-sms-audience-campaigns.md). That document owns data/behavior contracts; this document owns layouts, component props, interaction, and presentation. Both describe proposed implementation.

## 1. Design direction and component consultation

Design a cohesive **Modules / SMS** workspace: Campaigns, Contacts, Segments, Messages, Opt-outs. Primary task: select consented recipients → personalize approved content → set delivery timing → review → deliberately launch. The contact and segment tools support that task rather than becoming separate technical dashboards.

The four official platform references and their product decisions are recorded in the implementation plan. Their useful interaction patterns are Klaviyo's audience/content/review progression, Braze's permission-aware audience and personalization, Mailchimp's checklist/report/cancel flow, and Twilio's distinction between queue acceptance and asynchronous delivery.

The shadcn skill/MCP tools are unavailable in this harness. Official shadcn documentation was consulted via webfetch **before this design was written**:

- [Card](https://ui.shadcn.com/docs/components/card): header/title/description/action, content, footer composition. Use one purposeful card per section, with actions aligned to its heading or footer.
- [Field](https://ui.shadcn.com/docs/components/field): semantic fieldsets, labels, controls, descriptions, inline errors; mobile-first vertical fields and grouped responsive fields.
- [Table](https://ui.shadcn.com/docs/components/table): semantic caption/header/body, aligned numeric columns, row actions, contained responsive overflow.

Deliver these patterns through existing Rails ViewComponents, Tailwind tokens, and Rails `ActionView::Helpers::FormBuilder`; no React/package installation is needed. Verified project components are `Admin::Modules::PageComponent`, `CardComponent`, `BadgeComponent`, `AdminTableComponent`, `Emails::Audience::SegmentBuilderComponent`, and `Sms::Admin::MessageDetailsComponent`.

## 2. Surface inventory and navigation

Here `S = /:cid/admin/modules/sms`. All tenant surfaces use the URL customer context, including owner browsing. Admin/owner authorization and SMS enablement are enforced by controllers.

| Surface | URL | Navigation area | Main component |
| --- | --- | --- | --- |
| Campaign directory | `S/campaigns` | Modules / SMS / Campaigns | `Sms::Admin::CampaignsIndexComponent` |
| New/edit draft and server preview | `S/campaigns/new`, `S/campaigns/:id/edit`, POST preview routes | Modules / SMS / Campaigns | `Sms::Admin::CampaignFormComponent` |
| Saved draft review / launch result | `S/campaigns/:id` | Modules / SMS / Campaigns | `Sms::Admin::CampaignDetailsComponent` |
| Campaign delivery report + CSV | `S/campaigns/:campaign_id/report` | Modules / SMS / Campaigns | `Sms::Admin::CampaignReportComponent` |
| Contact directory | `S/contacts` | Modules / SMS / Contacts | `Sms::Admin::ContactsIndexComponent` |
| Contact new/edit | `S/contacts/new`, `S/contacts/:id/edit` | Modules / SMS / Contacts | `Sms::Admin::ContactFormComponent` |
| Contact detail + consent history/form | `S/contacts/:id` | Modules / SMS / Contacts | `Sms::Admin::ContactDetailsComponent` |
| Explicit Entity sync mapping / batch results | `S/contacts/entity_sync/new` and POST endpoints | Modules / SMS / Contacts | `Sms::Admin::EntitySyncComponent` |
| Segment directory | `S/segments` | Modules / SMS / Segments | `Sms::Admin::SegmentsIndexComponent` |
| Segment new/edit/preview | `S/segments/new`, `S/segments/:id/edit`, collection/member POST preview | Modules / SMS / Segments | `Sms::Admin::SegmentFormComponent` |
| Segment detail/membership preview | `S/segments/:id` | Modules / SMS / Segments | `Sms::Admin::SegmentDetailsComponent` |
| Existing message/opt-out directories and message detail | `S/messages`, `S/messages/:id`, `S/opt_outs` | Modules / SMS / Messages or Opt-outs | Existing table/details plus SMS navigation |
| Template purpose/optional preview mirror | `/81721200/admin/maintenance/platform/module_settings/sms/templates` and new/edit | Maintenance / Platform / Module Settings | Existing platform template form/table components |
| Common account send-rate setting | `/81721200/admin/maintenance/platform/module_settings/sms/credentials` and edit | Maintenance / Platform / Module Settings | Existing credential form plus generic field |
| Signed recipient unsubscribe confirmation/result | `/sms/unsubscribes/:token`, GET then POST | public | `Sms::UnsubscribeComponent` |

Customer-specific Settings / SMS retains the existing read-only daily cap. SMS enablement/cap stays in Maintenance / Modules. Campaign controls belong to the individual campaign, not a new customer settings page. No new member surface or role is required.

Workspace navigation order: **Campaigns → Contacts → Segments → Messages → Opt-outs**. Each item is an ordinary link with active `aria-current="page"`; on mobile the link strip scrolls within its own container. Campaigns is the task entry linked from the module registration/sidebar. Breadcrumb examples: Modules / SMS / Campaigns / campaign name; Modules / SMS / Contacts / contact name. Store-record names are user data, not application labels.

## 3. Shared layout, states, and accessibility

- Mount every admin surface inside `Admin::Modules::PageComponent` with `module_key: "sms"`, translated title/description, breadcrumbs, and bounded actions. Then render `Sms::Admin::NavigationComponent` and the page-specific component. Thin ERB mounts only; substantive layout belongs in ViewComponents.
- Match existing tokens: `text-text-primary`, `text-text-secondary`, `text-text-muted`, `bg-canvas-elevated`, `bg-surface-subtle`, `border-border-subtle`, `text-danger`, `text-success`, `text-warning`, and `text-info`. Reuse existing `btn`, `btn-primary`, `btn-secondary`, `input-field`, `form-label`, `section-header` design utilities.
- Page stack `space-y-6`. Card body `p-4 sm:p-6`; use `CardComponent` with `padding: :none` when adding the responsive body inset. Header actions `flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between`; action groups `flex flex-wrap gap-2`.
- Forms default vertical labels/controls/helper/error. Two-column related fields start at `md`; content/summary sidebar begins at `xl`, with a fluid `minmax(0,1fr)` main region. Every grid child uses `min-w-0`; identifiers/JSON examples wrap with `break-words [overflow-wrap:anywhere]`.
- Preserve `AdminTableComponent`'s contained horizontal scrolling, semantic headers, filters, and pagination. Name/phone/status/actions remain discoverable without fixed-width page overflow. Place secondary identifiers/source data under the primary cell when possible; use numeric right alignment and `tabular-nums` for counts/times, not prose.
- Badge mapping: granted/delivered/completed `:success`; unknown/draft `:default`; scheduled/running/API accepted `:info`; revoked/archived/skipped/suppressed/expired `:warning`; failed `:danger`. Cancelled is neutral. Always show translated text as well as color.
- Times are semantic `<time datetime="ISO8601">` with a readable localized value and visible timezone where timing matters. Consent state and current eligibility are different displayed values.
- Inputs have actual labels; helper/error IDs connect through `aria-describedby`; invalid controls have `aria-invalid`. Related controls use `fieldset`/`legend`. Error summary is above the form with links to invalid fields. Counts/results use heading semantics, not color-only icons.
- Full-page native submit/navigation is the default. Reuse existing Turbo form submit disabling/loading behavior where available; there is no invented progress percentage for a preview. Any existing frame loading indicator uses translated text. Enqueue/processing states use recorded timestamps and a manual Refresh link.
- No required launch/cancel modal. Saved draft Review is the launch confirmation surface. A running campaign has an inline cancellation card describing the exact boundary, followed by a POST button. Contact archive/draft deletion use explicit detail-page action cards rather than relying on a new confirmation controller.

## 4. Campaign directory

```text
Modules / SMS / Campaigns                         [Create campaign]
SMS campaigns
Plan, launch, and report on targeted messages.
[Campaigns] [Contacts] [Segments] [Messages] [Opt-outs]

[Search campaigns________] [Status: All v]       Result count
Campaign              Status        Timing             Recipients  Actions
Autumn offer          Draft         Send now            —           Review
Renewal reminders     Scheduled     Oct 16 10:00 CST     —           Open
VIP invitation        Running       Started 10:01        280         Report

[Pagination]
```

Data: `Sms::Campaign.name`, `status`, `send_timing`, `scheduled_at`/`started_at`, and ledger-derived `stats.matched_count` after snapshot. Recipient count before snapshot is translated “Not started,” not an invented frozen count. Row link opens show/review; row primary action is Review for draft, View report otherwise. Edit/delete are available only for draft.

Empty: compact Card with campaign icon, “Create your first SMS campaign,” description, primary Create campaign and secondary Contacts link. Filtered empty: clear-filter link and no creation implication. Error: standard localized request error; never show another tenant's data as a fallback. Loading: ordinary table/frame loading indicator; background sending is represented by campaign status, not a page spinner.

Index props are `{records:, columns:, pagination:, filters:}` from the frozen controller contract.

## 5. Campaign draft form — four ordered sections

Use one server-rendered workspace with a four-item ordered anchor navigation. It is a guided form with all sections available; there is no separate client-side wizard state to keep in sync. The section order is always **Audience → Content → Schedule → Review**.

```text
Modules / SMS / Campaigns / New                    Draft badge
Create SMS campaign
[Campaigns] [Contacts] [Segments] [Messages] [Opt-outs]
[1 Audience] [2 Content] [3 Schedule] [4 Review]

MAIN (fluid, 2/3 at xl)                         SUMMARY (1/3 at xl)
Card: 1 Audience                               Card: Audience estimate
  Campaign name [_________________]              Matched      350
  Segment       [All contacts v]                 Eligible     280
  [Manage contacts] [Manage segments]             Excluded      70
  Positive consent / start-time help             Evaluated 10:00

Card: 2 Content                                Card: Sample message
  Approved marketing template [______ v]         Contact [Sample contact v]
  Required variables: name, offer, opt_out_url    Rendered approved mirror
  Variable mappings [JSON textarea________]      Variables/defaults applied
  Three explicit mapping examples                Encoding / units / segments

Card: 3 Schedule
  (o) Send now  ( ) Schedule
  Local date/time [________] Timezone [________]
  Quiet hours start [21]  end [9]
  Frequency window [24] hours
  Send rate [60] recipients/minute
  Deadline [24] hours

Card: 4 Review
  Settings summary / missing requirements
  Audience excludes + deferred counts
  Intended start / absolute deadline / duration estimate
  “Save this draft to launch it from the review page.”

[Save draft] [Preview campaign] [Back to campaigns]
```

Mobile order: Audience → Content → sample message → Schedule → Review/estimate summary → actions. On desktop, section summaries/preview may occupy the right column without moving keyboard/reading order ahead of their source fields. No sticky overlay footer; ordinary footer buttons are full width below `sm` and inline above.

### 5.1 Audience card

- `name` is required; no backend-generated campaign name.
- `segment_id` is a native select: translated All contacts option with blank value, followed by same-tenant `@segments` entries. Explain: all contacts are considered, but only active, positively consented, unblocked recipients may send. This option does not mean “all phones will receive a message.”
- New segment/contact actions navigate to their directory/new forms. They do not silently create or grant records from the campaign form.
- Live membership is evaluated once at execution start using frozen segment rules. Preview shows matched/eligible separately and a timestamp. Consent/contact changes can reduce eligibility after that.

### 5.2 Content card and JSON mapping help

`template_id` select contains only active marketing templates in `@templates`. Template key, required variable names, and optional preview mirror are visible. Provider/account controls do not appear in a tenant campaign form.

`sms_campaign[variable_map_json]` is a labeled, resizable native textarea (`font-mono text-sm min-h-48 w-full`), with preserved raw text on errors. Display translated explanation and these three concrete shapes beside/below it:

```json
{
  "name": { "source": "field", "field": "name", "fallback": "Customer" },
  "offer": { "source": "literal", "value": "20%" },
  "opt_out_url": { "source": "field", "field": "unsubscribe_url" }
}
```

The example is documentation inside translated helper content: application wording and the human fallback “Customer” have matching en/zh-CN translations; protocol keys and enum values stay stable. A variable-free template uses `{}`. Present a translated list of permitted personalization fields and explain that missing/blank values require a fallback or the recipient is skipped. Arbitrary code/expression input is not suggested by placeholders.

The sample-contact select uses `preview_contact_id`, root-level, with at most 20 `@contacts` choices. Submission explicitly regenerates preview server-side. Choosing a contact does not add it to the segment or override permission. A sample outside the audience is clearly labeled as a personalization sample, with its eligibility reason; campaign totals remain based on the real audience.

The shared native form posts the sample selector on Save too. The HTTP adapter validates its tenant scope and treats it only as read-only form metadata; it never becomes a saved draft setting. Submit-button `commit`, `_method`, `authenticity_token`, and `locale` are framework transport fields, excluded from canonical service attributes.

If `body_template` exists, display escaped server-rendered text in a simple message Card, not a fabricated device image. Show `encoding`, `units`, `segments` from the existing calculator, clearly marked estimate. If absent, show variable resolution and translated “Message text is managed by the provider; preview text is unavailable.” Estimate is Unknown. Do not infer body/segments from a template code, show a fabricated body, or call the provider to preview.

### 5.3 Schedule card

Map exactly to `send_timing`, virtual `scheduled_local`, `timezone`, `quiet_hours_start`, `quiet_hours_end`, `frequency_window_hours`, `send_rate_per_minute`, and `deadline_hours`. Defaults: immediate, Asia/Shanghai, quiet 21:00–09:00, frequency 24 hours, rate 60/minute, deadline 24 hours.

Both immediate and scheduled controls are rendered without new JavaScript. Native radios choose timing; date/time stays visible with helper “Required only for scheduled campaigns.” Blank scheduled time is allowed in an incomplete saved draft but blocks launch. The timezone field is an IANA zone input with the explicit default/sample; invalid/ambiguous DST times are inline errors, not silent shifts.

Group quiet start/end in one fieldset. Helper: recipient timezone, fallback campaign timezone; delay to the next allowed time, only before the campaign deadline. Show rate helper as campaign admission limit, with shared account ceiling separately summarized; it is not a guarantee of receipt timing. Deadline helper states TTL starts at intended campaign start and does not reset after delays.

### 5.4 Review/preview behavior and native form verbs

- Save draft is the primary normal form action; it never sends. Redirect `303` to saved draft show/review.
- Preview campaign is an explicit **POST to the separate preview route**. It renders this full form with all submitted values, refreshed summary/samples, and validation messages. No save/message/recipient/consent/quota/job side effects.
- There is no Launch button in an unsaved form. The review card links the user to saving first. A valid preview of unsaved changes does not mint a launch token for persisted settings.
- Native button-specific `formaction` preserves controls without JavaScript. For existing edits, avoid a hidden `_method=patch` leaking into the preview POST: render the shared form as POST and place `_method=patch` **on the Save draft submit button only**, targeting the record update URL; the Preview button targets the POST preview URL without a method override. New Save targets collection POST. Put Save first in submit-button DOM order. Apply the same convention to segment save/preview. Use the Rails session-bound global `form_authenticity_token` for this multi-action form so a per-form token bound to the default preview URL does not reject Save at its different action/verb. Keep CSRF enforcement and FormBuilder naming; test both targets.

Empty template picker: explanation plus link to the existing SMS settings/help location; only platform owner additionally sees the platform template-management link. Draft can be saved, review shows `template_required`. Empty contacts: Create contact / Sync from Entity links; no false “ready to send.” Invalid JSON: inline parse error, original textarea preserved, no stale eligibility presented as current. Stale edit: `409`, identify concurrent change and link to reload current draft; retain submitted values for manual comparison.

## 6. Saved campaign review, launch, cancellation, and report

### 6.1 Saved draft review

Header: campaign `name`, Draft badge, Edit draft action. Cards summarize saved Audience, Content, Schedule, then Review with actual preview counts and at most five samples. Use `Sms::Admin::AudienceSummaryComponent` and `Sms::Admin::CampaignPreviewComponent` for the same presentation used in the form.

Review card contains:

1. Matched, currently eligible, and exclusions by translated reason.
2. Personalization sample and mirror availability; missing required mappings are blockers.
3. Intended schedule timezone, quiet interval, frequency window, campaign admission rate, shared account rate, absolute deadline, and lower-bound duration estimate.
4. Start-time audience explanation and provider acceptance/delivery distinction.
5. Final **Launch campaign** or **Schedule campaign** POST action, using saved `lock_version` and `review_token` only. No editable settings are forwarded by launch.

Blockers keep the final action unavailable and give a specific next step (Edit mappings, Add consented contacts, or relevant settings link). Quiet-hour deferral is described, not falsely labeled ineligible. Missing credential readiness is detected locally; preview does not ping the vendor.

Expired/stale review returns `409 review_changed`, refreshes read-only review, and asks the user to review the changed saved settings. Launch success redirects to show with Scheduled badge, intended time, deadline, and View report action. Even immediate campaigns first enter the committed scheduled state, then start asynchronously.

### 6.2 Launched campaign detail

Settings cards are read-only snapshots. Header has status badge, View report, and Refresh link. Show `launched_at`, `started_at`, `heartbeat_at`, `expires_at`, and `finished_at` when present; missing facts use translated Not started/Not recorded.

For Scheduled/Running, cancellation card reads: “Cancel remaining messages. Messages already attempted will continue to receive delivery updates.” Button **Cancel remaining messages**, POST `cancel_campaign`. After success show Cancelled badge, cancelled count, attempted count that cannot be recalled, and preserved report link. Cancelled replay is successful. Completed/failed campaigns show their final explanation and report.

Provider-down/timeout is report state: Failed for a proven rejection, Unknown for uncertainty. There is no resend action. An enqueue outage keeps durable scheduled/queued records, with recorded heartbeat and refresh; do not show a vendor error as an ordinary form validation failure.

### 6.3 Delivery report

```text
Modules / SMS / Campaigns / Autumn offer / Report    [Download CSV] [Refresh]
Autumn offer — delivery report                       Running badge

Matched 350   Eligible at start 280   Attempted 120   Delivered 105
API accepted 112   Failed 4   Unknown 8   Queued 160   Cancelled 0

Card: Skips and delays                Card: Sending facts
  Missing consent 40                   Snapshot at / stats freshness
  Archived 10                          Absolute deadline
  Opted out 20                         Delivery rate denominator
  Quiet hours waiting 90               Actual provider segments + missing count

[Search name/phone____] [Recipient status v] [Message status v] [Reason v]
Contact / phone      Recipient       Message       Attempted     Delivery / reason
Alice / +86…         Admitted        Delivered     10:01         Delivered 10:02
Bob / +86…           Pending         —             —             Quiet hours
Chen / +86…          Skipped         —             —             Missing consent
[Pagination]
```

Four main metric cards at `xl`, two at `sm`, one on narrow mobile. Other facts appear as definition-list rows rather than a wall of metric cards. Milestone counts overlap current statuses; helper text explicitly explains this. Delivery rate is delivered/attempted; zero attempts is Unknown. `completed` means dispatch work completed, and pending/unknown receipts may still update afterward.

Recipient rows come from `@records`, with linked `message` preloaded. Contact link is tenant contact detail. Message link opens existing message details; vars/raw/evidence are not repeated in reports. Name and phone are snapshot values so historical rows remain interpretable after contact edits. CSV exports all filtered rows, not only the visible page, using the fixed architecture column order. Show actual provider segments with missing-data count and no currency quote.

Empty before execution: “The audience will be captured when sending starts,” scheduled time and Refresh; no fabricated zero-success metric. Empty audience after start: show recorded skip/failure facts. Loading: ordinary navigation/Refresh, no automatic polling required. Error: standard scoped error with campaign detail link.

## 7. Contacts and consent

### 7.1 Directory and manual form

Directory header: Contacts, description, **Add contact** primary, **Sync from Entity** secondary. Columns: name/phone, consent badge, contact status, country/timezone, source, updated time. Filters: consent status, contact status, source; search name/phone. Eligibility may be shown as translated status text without exposing the existence/reason/provider metadata of another tenant's global suppression.

Empty: Add contact and Sync from Entity actions, with “Adding a contact does not grant SMS consent.” Filtered empty uses clear filters. Inline errors/standard loading follow shared states.

Form Card: raw `phone`, `country_code`, `name`, optional `timezone`, status on edit, and optional `custom_attributes_json` textarea with a scalar JSON example. Country default CN is visible and editable. Helper explains international/national normalization and no timezone inference. No consent checkbox exists here. Save redirects to contact detail; invalid phone/source identity collision/stale edit rerenders values and field errors.

### 7.2 Detail, evidence, and archive

```text
Modules / SMS / Contacts / Alice                    [Edit contact]
Alice                                              Active badge

Card: Contact                                      Card: Marketing permission
  Canonical phone, country, timezone                  Consent: Granted
  Source + synced_at                                  Eligibility: Currently blocked
  Scalar custom attributes                            Last recorded change

Card: Consent history
  Recorded time  Action  Occurred time  Source  Actor  Evidence reference
  Read-only evidence text; paginated

Card: Record consent event
  Action [Grant consent / Revoke consent v]
  Occurred at [date/time with offset]
  Evidence reference [________]
  Consent statement [________]
  Notes [________]
  [Record consent event]

Card: Archive contact
  Retains consent evidence and campaign history.
  [Archive contact]
```

Evidence fields map to `sms_consent_event`; source/phone/actor/customer are server-derived. Event key is a generated hidden deduplication value, not a contact-data field. Statement helper says required for grant. `consent_events` is `{records:, pagination:}` for the history table. No mutable event edit/delete menu is rendered. On revoke, detail immediately shows revoked and suppression; on grant, the UI may still show blocked. Grant never displays an unblock implication.

Editing a phone shows static helper “A changed phone needs a new consent record.” After save, detail displays Unknown and retains prior-phone history. Archive POST/DELETE is explicit and keeps history; archived detail offers Restore via contact update. Directory default may filter active, with archived reachable via filter.

## 8. Entity sync

One native form with Mapping, Preview batch, and Result sections. GET with an allowlisted `entity_id` selection reloads field choices without JavaScript; no writes occur. Source select is `@entities`; phone field is required from `@source_fields[:phone]`, name field optional from scalar fields. Inputs country CN, timezone Asia/Shanghai, and `attribute_map_json` appear explicitly.

```text
Sync SMS contacts from an Entity
Card: Mapping
  Entity [________ v] [Load fields]
  Telephone field [mobile v]   Name field [full_name v]
  Country [CN]                Timezone [Asia/Shanghai]
  Custom attribute mappings [JSON textarea]
  “Synchronization does not grant consent.”
  [Preview first 100]

Card: Preview batch
  Scanned 100 / New 75 / Update 20 / Invalid 3 / Conflicts 2
  First rows: entry / normalized contact / planned outcome / reason
  [Sync this batch]

Card: Result
  Created / Updated / Unchanged / Invalid / Conflicts
  [Preview next 100] [Back to contacts]
```

Preview is POST to the separate read-only route. Sync POST preserves exact mapping, cursor, and high-water bound; no checkbox or text implies permission import. After execution the page shows bounded per-entry results and next cursor; the next batch is explicit. Source/schema changes are revalidated. An inaccessible source/field gives scoped `404`/`422`, no alternative Entity auto-selection. Item failures are listed without hiding successful items. Empty source/schema/no tel fields explains the condition and links back to Contacts.

Loading is request-based; do not claim background sync or an overall import percentage. Source links use accessible Entity/entry helpers; show no cross-tenant source data. No automatic restore of archived contacts and no silent merges.

## 9. Segments

Directory: **Create segment**, search name, columns name/description, updated time, Open/Edit actions. Avoid recomputing audience counts per directory row; exact counts belong to detail/preview. Empty explains dynamic matching and points to contact creation.

Form: name, description, Card containing the existing grouped builder, then matched/eligible summary and up to five sample rows after POST Preview. Reuse:

```text
Emails::Audience::SegmentBuilderComponent
  list: segment
  catalog: Sms::Audience::FieldCatalog.new(customer: current_customer)
  param_name: "sms_segment[segment_rules_json]"
  preview: false
```

Builder retains its existing `segment-builder` Stimulus controller unchanged. A new segment's native Preview submit uses `admin_modules_sms_preview_segments_path(current_customer_id)`; an existing segment uses `admin_modules_sms_preview_segment_path(current_customer_id, segment)` at `S/segments/:id/preview`. Member preview retains the tenant-scoped record identity and submitted `lock_version` on success or validation rerender, so Save remains a PATCH to that original segment and stale edits still conflict. Do not invoke `email-list-form#preview`. `@segment.segment_rules` for rerender is the validated submitted tree or a safe display object, and original invalid JSON stays in `@form_values` for correction; never normalize an invalid tree into an executable empty audience.

Help: AND/OR groups are left-associative unless explicitly nested; an empty root considers all contacts; membership does not itself confer marketing permission. Backend `422` identifies invalid fields/operators/values/bounds and preserves input; it never previews a broadened “best effort” tree. Detail is read-only rules description plus matched/eligible/count timestamp and Edit link. Delete is available only with no draft dependencies; a protected delete explains the dependency and links to campaign directory.

## 10. Platform template/credential additions and foundation links

In the existing owner-only template form, add **Purpose** native select (`transactional`, `marketing`) and **Preview message text (optional)** textarea. Show existing provider codes/variables alongside; helper says preview mirror must match actual approved provider content and is not sent as a raw message. Render `{{name}}` as protocol example, with translated surrounding text. Classification is fixed at campaign launch. Template table may show purpose badge; tenant campaign picker includes marketing only.

In the existing owner-only credential form, add a common **Account send rate (messages/second)** number field above vendor-specific fields, default 1, range greater than 0 and at most 1. It saves generic `config.sender_rate_per_second`; mutable `dispatch_next_at` is runtime-only, not an editable setting. Helper says the ceiling is shared by every tenant/campaign/direct send using this account.

Existing message detail reuses `Sms::Admin::MessageDetailsComponent`. Add scoped campaign/contact links when typed associations are present; retain existing variable redaction and receipt status explanation. A displayed campaign link is authorized by the same URL tenant scope. Messages/Opt-outs use the common SMS navigation. No raw provider response or credential is exposed in new surfaces.

## 11. Recipient unsubscribe

Public responsive layout: single centered fluid Card, full width with small-screen insets, `max-w-lg` only as a maximum, never fixed width. Render no admin sidebar or contact record link.

GET valid token: heading “Unsubscribe from SMS,” masked phone, brief explanation, **Confirm unsubscribe** POST button. Generating/loading this page writes nothing. POST success: heading “You have unsubscribed,” explanation that remaining unattempted messages for this tenant/phone will be blocked; no signup/re-consent action. Replay uses the same success state. Invalid/expired token: localized not-found explanation and no phone/account metadata.

The server supplies only `{masked_phone:, already_unsubscribed:}` from `Sms::Campaigns::Unsubscribe.preview`. Form retains Rails CSRF. The button acts on the signed phone; a later changed contact phone does not cause a different number to be revoked. Link scanners and GET/HEAD refresh cannot unsubscribe. Rails request-start logs and controller instrumentation redact the capability path through `Request#filtered_path`; the browser's real confirmation URL and token stay intact.

## 12. Frozen ViewComponent props and controller integration

All component names are under `Sms::Admin` except the public component. These are prop interfaces, not source implementations:

| Component | Required props | Reuse |
| --- | --- | --- |
| `NavigationComponent` | `customer_id:, active:` (`campaigns/contacts/segments/messages/opt_outs`) | Native links; project nav tokens |
| `CampaignsIndexComponent`, `ContactsIndexComponent`, `SegmentsIndexComponent` | `records:, columns:, pagination:, filters:` | `AdminTableComponent` (`rows: records`), `CardComponent` empty state |
| `CampaignFormComponent` | `campaign:, templates:, segments:, contacts:, form_values:, preview:, errors:` | `CardComponent`, FormBuilder, preview/summary components |
| `CampaignDetailsComponent` | `campaign:, templates:, segments:, contacts:, preview:, report:, errors:` | Cards, badges, preview/summary, native launch/cancel POST |
| `AudienceSummaryComponent` | `preview:` (audience or campaign preview hash) | Card with matched/eligible/excluded/deferred facts |
| `CampaignPreviewComponent` | `preview:, contacts:, selected_contact_id: nil` | Card, native sample select, server-rendered body/vars |
| `CampaignReportComponent` | `campaign:, report:, records:, columns:, pagination:, filters:` | Cards, badges, AdminTable |
| `ContactFormComponent` | `contact:, form_values:, errors:` | FormBuilder, Card |
| `ContactDetailsComponent` | `contact:, consent_events:, eligibility:, consent_form_values:, errors:` | Cards, badges, AdminTable evidence, nested `ConsentFormComponent` |
| `ConsentFormComponent` | `contact:, form_values:, errors:` | Native append-only event form |
| `EntitySyncComponent` | `form_values:, entities:, source_fields:, sync_result:, errors:` | Cards, FormBuilder, bounded result table |
| `SegmentFormComponent` | `segment:, catalog:, form_values:, preview:, errors:` | Generic grouped SegmentBuilder, Cards, FormBuilder |
| `SegmentDetailsComponent` | `segment:, preview:` | Read-only rules presentation, AudienceSummary |
| `Sms::UnsubscribeComponent` | `unsubscribe:, errors:` | Card, native confirmation POST |

Every page wrapper independently uses `Admin::Modules::PageComponent`; these props do not contain a duplicate page title/router state. Components derive authorized links from existing helpers/current customer context, with URLs from architecture section 9. Optional hashes default nil as documented; errors always `{}` or populated.

Frozen assigns:

```text
Index:        @records, @columns, @pagination, @filters
Contact:      @contact; @form_values, @errors
Consent:      @consent_events, @eligibility, @consent_form_values
Segment:      @segment; @catalog, @form_values, @preview, @errors
Campaign:     @campaign; @templates, @segments, @contacts,
              @form_values, @preview, @report, @errors (surface-dependent)
Entity sync:  @form_values, @entities, @source_fields, @sync_result, @errors
Report:       @campaign, @report, @records, @columns, @pagination, @filters
Public:       @unsubscribe, @errors
```

Pickers are arrays of hashes, not ActiveRecord objects: template `{id, key, label, required_vars, body_template}`; segment `{id, name}`; sample contact `{id, name, phone_e164}`; Entity `{id, label}`. Their exact limits/form names are frozen in the architecture. Never assume `@template`, `@lists`, `@audience`, or Email send-activity instance variables exist.

## 13. Interaction flows and failure paths

| Story | Click-by-click flow | Failure handling |
| --- | --- | --- |
| Create contact + record permission | `S/contacts` → Add contact → Save → `S/contacts/:id` → record Grant with evidence → same detail | Invalid phone/JSON/evidence `422`, values retained; unknown consent until separate valid grant; existing suppression still blocks |
| Sync contacts | Contacts → Sync from Entity → select Entity/Load fields → choose tel/name/country/timezone → Preview 100 → Sync batch → preview next or Contacts | Inaccessible source `404`; schema/input `422`; item conflicts/invalid phones reported; no permission grant |
| Create segment | Segments → Create segment → enter rules → Preview → Save → segment detail | Invalid tree rejected whole; rules/text retained; no all-contacts fallback |
| Create/review immediate campaign | Campaigns → Create → Audience → Content → Schedule Send now → Preview → Save draft → saved Review → Launch → show/report | Missing requirements block launch; saving still possible for incomplete draft; stale review `409`, regenerated read-only review |
| Schedule campaign | Same workflow → Schedule + local time/timezone → Preview → Save → Schedule campaign → show Scheduled | Past/DST gap/ambiguity rejected; quiet hours explained as bounded delay; audience snapshot happens at execution start |
| Revoke before dispatch | Contact detail → Revoke event → remaining pending/queued campaign messages are blocked at final gate → campaign report | Already attempted messages remain observable; no misleading recall confirmation |
| Cancel campaign | Scheduled/running detail → inline cancellation boundary → Cancel remaining messages → Cancelled detail/report | Start/cancel race follows durable attempt marker; terminal completed/failed cancel conflicts; repeat cancel succeeds |
| Inspect delivery | Campaign directory → View report → filter recipients → Message link → existing message detail → Download CSV from report | Vendor uncertainty remains Unknown; no resend action; report/CSV GET does not trigger execution or persistent stats refresh |
| Recipient unsubscribe | Signed URL GET → read masked phone → Confirm unsubscribe POST → success | GET no writes; replay same success; expired/invalid token localized `404`; signed old phone only |
| Unauthorized browsing | Member/anonymous or tenant admin reaches protected SMS URL → controller authorization response | No directory data or picker/evidence leakage; cross-tenant record ID is scoped not-found |

## 14. I18n delivery and representative copy

Every application-added word in headings, labels, buttons, help, AR validation/flash/errors, statuses, empty states, table/CSV headers, and aria text uses I18n. Reuse an existing key for identical English; new keys belong in paired area files, with identical key/interpolation sets in `en` and `zh-CN`. Proposed namespaces: `admin_modules.sms.contacts`, `.segments`, `.campaigns`, `.entity_sync`; `sms_campaigns.errors/reasons`; `sms_unsubscribe`; platform additions under existing `maint_platform` SMS namespace.

Representative frozen wording below is a copy specification, not permission to hard-code it in a component:

| Intended key suffix / role | English | 简体中文 |
| --- | --- | --- |
| `campaigns.title` | SMS campaigns | 短信活动 |
| `contacts.title` | SMS contacts | 短信联系人 |
| `segments.title` | SMS segments | 短信分群 |
| `campaigns.create` | Create campaign | 创建活动 |
| `campaigns.steps.audience` | Audience | 受众 |
| `campaigns.steps.content` | Content | 内容 |
| `campaigns.steps.schedule` | Schedule | 发送时间 |
| `campaigns.steps.review` | Review | 确认 |
| `campaigns.save_draft` | Save draft | 保存草稿 |
| `campaigns.preview` | Preview campaign | 预览活动 |
| `campaigns.launch` | Launch campaign | 启动活动 |
| `campaigns.schedule` | Schedule campaign | 定时发送 |
| `campaigns.cancel` | Cancel remaining messages | 取消剩余发送 |
| `campaigns.report` | View report | 查看报告 |
| `campaigns.csv` | Download CSV | 下载 CSV |
| `campaigns.all_contacts` | All contacts | 全部联系人 |
| `campaigns.matched` | Matched contacts | 匹配联系人 |
| `campaigns.eligible` | Currently eligible | 当前可发送 |
| `campaigns.send_now` | Send now | 立即发送 |
| `campaigns.quiet_hours` | Quiet hours | 免打扰时段 |
| `campaigns.mapping` | Variable mappings (JSON) | 变量映射（JSON） |
| `campaigns.sample` | Sample contact | 示例联系人 |
| `campaigns.fallback_sample` | Customer | 客户 |
| `contacts.add` | Add contact | 添加联系人 |
| `contacts.sync` | Sync from Entity | 从实体同步 |
| `contacts.grant` | Grant consent | 记录同意 |
| `contacts.revoke` | Revoke consent | 撤回同意 |
| `contacts.evidence_reference` | Evidence reference | 凭证来源 |
| `contacts.statement` | Consent statement | 同意内容 |
| `contacts.no_implied_consent` | Adding a contact does not grant SMS consent. | 添加联系人不代表已获得短信发送授权。 |
| `contacts.changed_phone_help` | A changed phone needs a new consent record. | 更换号码后须重新记录同意。 |
| `entity_sync.no_consent` | Synchronization does not grant consent. | 同步数据不会授予短信发送授权。 |
| `campaigns.start_snapshot_help` | Audience membership is captured when sending starts. | 发送开始时确定受众名单。 |
| `campaigns.cancel_help` | Messages already attempted will continue to receive delivery updates. | 已尝试发送的短信仍会更新送达状态。 |
| `campaigns.preview_unavailable` | Message text is managed by the provider; preview text is unavailable. | 短信正文由服务商管理，暂无预览文本。 |
| `unsubscribe.title` | Unsubscribe from SMS | 退订短信 |
| `unsubscribe.confirm` | Confirm unsubscribe | 确认退订 |
| `unsubscribe.success` | You have unsubscribed | 已退订 |

Copy beyond this representative set must follow the same key-parity rule. Stored contact/campaign/template/Entity names and evidence are user data and escaped, not translated as keys. Stable JSON fields/source enums/AST operators remain protocol values; labels explaining them are translated. Never resolve `I18n.t` into a Ruby constant.

## 15. Stimulus and frontend verification

**Zero new JavaScript is the default design.** Existing grouped segment behavior remains in the already-tested `segment-builder` controller; all campaign previews, mapping-field reloads, schedule validation, action confirmation, and report refresh work through native forms/links and server render. Existing Turbo/navigation behavior can be reused without changing its controllers.

If implementation discovers a concrete need to change JavaScript, define the smallest Stimulus action/target/value contract before editing, pass all user-facing strings as server-translated values, and update its Vitest suite in the same change. Require actual 100% line/branch/function coverage output for touched files. Do not introduce an SMS wizard controller just to hide already ordered form sections.

Component/request verification should cover both locales, required prop hashes, validation input retention, POST preview method isolation from PATCH Save, no launch on draft save, badges/count semantics, unavailable body mirror, phone-change consent reset, readonly evidence, explicit Entity batches, conditional cancellation, and signed GET/POST unsubscribe. Responsive smoke checks at 360/768/1280 px verify no viewport-wide overflow, readable JSON help, accessible row actions, wrapping Chinese labels, and functional keyboard navigation.

## RETURN
ux_doc: docs/superpowers/specs/2026-10-13-sms-campaigns-ux.md
surfaces:
  - name: SMS campaigns, review, and reports
    nav_area: Modules
    new_components: [Sms::Admin::CampaignsIndexComponent, Sms::Admin::CampaignFormComponent, Sms::Admin::CampaignDetailsComponent, Sms::Admin::CampaignReportComponent, Sms::Admin::AudienceSummaryComponent, Sms::Admin::CampaignPreviewComponent, Sms::Admin::NavigationComponent]
    reused_components: [Admin::Modules::PageComponent, CardComponent, BadgeComponent, AdminTableComponent]
  - name: SMS contacts, consent, and Entity sync
    nav_area: Modules
    new_components: [Sms::Admin::ContactsIndexComponent, Sms::Admin::ContactFormComponent, Sms::Admin::ContactDetailsComponent, Sms::Admin::ConsentFormComponent, Sms::Admin::EntitySyncComponent]
    reused_components: [Admin::Modules::PageComponent, CardComponent, BadgeComponent, AdminTableComponent]
  - name: SMS dynamic segments
    nav_area: Modules
    new_components: [Sms::Admin::SegmentsIndexComponent, Sms::Admin::SegmentFormComponent, Sms::Admin::SegmentDetailsComponent]
    reused_components: [Admin::Modules::PageComponent, CardComponent, Emails::Audience::SegmentBuilderComponent]
  - name: SMS template purpose and account rate
    nav_area: Maintenance/Platform/Module Settings
    new_components: []
    reused_components: [CardComponent, BadgeComponent]
  - name: Recipient unsubscribe
    nav_area: public
    new_components: [Sms::UnsubscribeComponent]
    reused_components: [CardComponent]
overall: READY_FOR_FRONTEND
notes: Fixed schema, route/form/assign contracts, server-rendered previews, explicit positive consent, and existing component reuse support parallel implementation with no required new JavaScript.
