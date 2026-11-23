# Email Modules — Bug Audit + Grouped Segment Builder

Date: 2026-06-26
Scope: `/:cid/admin/modules/emails/*` and `/:cid/admin/modules/email_campaigns/*`

## Goal

Three threads of work, driven autonomously (user waived the confirmation gate):

1. Audit every operation in the **emails** and **email_campaigns** modules; fix the underlying bugs.
2. On `lists/new` (and `lists/edit`): **remove the "Advanced (raw JSON)" section**.
3. **Replace the flat segment/condition builder** with a grouped (nested AND/OR) builder that references the flowchart **Decision** element's condition builder UX and data model, including condition groups.

Plus: enrich/enhance the surrounding email functionality where it materially improves correctness or usability, staying conservative on anything risky.

---

## Part 1 — Confirmed bugs (verified in source)

| # | Severity | Location | Bug | Fix |
|---|----------|----------|-----|-----|
| B1 | High | `jobs/email_campaigns/send_campaign_job.rb:15` | On **resume** (`campaign_pauses#destroy`) and on any re-trigger, the job re-iterates the *entire* audience from scratch. Anyone already emailed gets a **duplicate**. | Track per-(campaign,user) sends and skip users already sent. Use the existing `Emails::Message` rows (`message_type:"campaign"`, `metadata.campaign_id`, `metadata.user_id`) as the ledger — no new table. Add a deterministic `idempotency_key` per (campaign,user) so a duplicate insert is impossible even under a race. |
| B2 | High | `services/email_campaigns/audience_query.rb:92,110` | `after`/`before` with an unparseable value → `parse_time` returns `nil` → `col > NULL`, which matches **nobody** and is silently wrong. Same for `cast_value` datetime path. | Drop the whole condition when the value can't be parsed (return `nil` predicate), consistent with how unknown fields are dropped. |
| B3 | Medium | `audience_query.rb:94-95` | `is_blank`/`is_present` only test `IS NULL`. For string columns an empty string `''` is neither "blank" nor excluded by "present". | `is_blank` → `col IS NULL OR col = ''` for string types; `is_present` → `col IS NOT NULL AND col != ''`. Non-string types keep NULL-only semantics. |
| B4 | High | `controllers/admin/modules/emails/templates_controller.rb:73` + `services/email/gateway.rb:20` | Template **test-send** compiles rich-text HTML containing `cid:blob-<id>` image refs, but `send_raw` has no attachment support → broken images in the test email. | Add `attachment_blob_ids:` to `send_raw` and persist them into `metadata` (same shape the SMTP adapter already reads). Test-send computes blob ids via `Emails::CompileTemplate.blob_ids_for` and passes them. |
| B5 | Medium | `jobs/email_campaigns/scheduler_job.rb:42` | Recurring next-occurrence is computed from the **old** `scheduled_at`. A late run produces a next time still in the past → re-triggered immediately → catch-up storm. | Roll the occurrence forward past `Time.current` (advance by interval until `> now`). |
| B6 | Medium | `controllers/admin/modules/email_campaigns/campaigns_controller.rb:65` | `destroy` is unguarded; deleting a `sending` campaign makes the running job raise `RecordNotFound`. | Block destroy unless status ∈ {draft, sent, cancelled}; redirect with an alert otherwise. |
| B7 | Low | `controllers/.../lists_controller.rb:83` | Malformed segment JSON silently becomes `{}` (user loses their rules with no feedback). | With the new builder the hidden field is always controller-generated JSON, but keep a guard: on parse failure, add a model error and re-render instead of silently wiping. |

Non-bugs reviewed and intentionally left as-is: tenant scoping (correct via `for_customer`/`TenantScoped`), Arel parameter binding (safe), unsubscribe token verification (correct), `increment_stat!` uses `with_lock` (acceptable).

## Part 2 — Remove "Advanced (raw JSON)"

Delete the `<details>` raw-JSON block from `segment_builder_component.html.erb` and the `raw`/`rawChanged` plumbing from the Stimulus controller. The hidden `segment_rules_json` input remains the single source of truth submitted to the server.

## Part 3 — Grouped segment builder (reference: flowchart Decision)

### Data model (new, mirrors flowchart group format)

`email_lists.segment_rules` becomes a recursive **group**:

```json
{
  "type": "group",
  "match": "all",                // "all" => AND, "any" => OR between this group's members
  "conditions": [
    { "field": "first_name", "operator": "equals", "value": "Ada" },
    {
      "type": "group",
      "match": "any",
      "conditions": [
        { "field": "roles.key", "operator": "equals", "value": "admin" },
        { "field": "roles.key", "operator": "equals", "value": "owner" }
      ]
    }
  ]
}
```

Design choice vs. the flowchart's per-edge `joins` array: the flowchart allows mixed operators between siblings (`joins: ["AND","OR"]`). For an audience segment a **uniform match per group** (`"all"`/`"any"`) is the well-understood Mailchimp/CRM model and maps cleanly to SQL `AND`/`OR`. Arbitrary mixing is expressible by nesting groups, so no expressive power is lost. We keep the flowchart's **nesting + group-card UX** but use the segment's existing `match` vocabulary — this is the conservative, lower-risk choice and keeps `AudienceQuery` simple and provably correct.

Backward-compat: the old flat shape `{match, conditions:[{field,operator,value}]}` is normalized to a root group on read (both in `AudienceQuery` and the component), so existing lists keep working without a data migration.

### `AudienceQuery` rewrite

Recursive compile:
- A **group** compiles its members to predicates, then reduces with `.and`/`.or` per the group's `match`.
- A **leaf** compiles as today (field resolved via `FieldCatalog`, value bound as Arel param).
- Invalid leaves (unknown field, unparseable date) are dropped; an empty group contributes no predicate.
- Joins (`left_outer_joins`) are collected recursively across the whole tree, de-duplicated.

### UI (`SegmentBuilderComponent` + `segment-builder` Stimulus controller)

Adopt the flowchart Decision builder's interaction model, rebuilt in Tailwind + Stimulus (no custom CSS/JS), as a self-contained ViewComponent:

- **Group card**: header with an **AND/OR pill toggle** (this group's `match`), a left accent bar + tint for nested groups (mirrors `_buildGroupHTML`), and a footer with **"+ Condition"** and **"+ Group"** buttons.
- **Condition row**: field `<select>` (from `FieldCatalog`), operator `<select>` (operators filtered by field type, repopulated on field change), value input, remove button. Operators that need no value (`is_blank`/`is_present`) hide the value input.
- **Nesting**: "+ Group" inserts a nested group card into the nearest enclosing group; remove cascades empty-group cleanup; the root group never disappears.
- **Serialization**: the controller walks the DOM tree and writes the recursive group JSON to the hidden `segment_rules_json` input on every change. The component pre-renders the existing tree server-side so the form is usable before JS hydrates.

The builder is rendered with `match`/operator labels driven by `FieldCatalog::OPERATORS_BY_TYPE`, and the field catalog is passed to Stimulus as a JSON value (as today).

### Files touched

- `services/email_campaigns/audience_query.rb` — recursive compile + B2/B3.
- `components/email_campaigns/segment_builder_component.{rb,html.erb}` — grouped UI, remove Advanced.
- `javascript/controllers/segment_builder_controller.js` — grouped DOM ↔ JSON, nesting, remove raw.
- `controllers/.../lists_controller.rb` — B7 guard.
- `jobs/email_campaigns/send_campaign_job.rb` — B1 dedupe ledger.
- `jobs/email_campaigns/scheduler_job.rb` — B5 roll-forward.
- `controllers/.../campaigns_controller.rb` — B6 destroy guard.
- `controllers/admin/modules/emails/templates_controller.rb` + `services/email/gateway.rb` — B4 test-send attachments.
- Specs for every touched layer (model/service/job/component/request) + updated `audience_query_spec`, `segment_builder_component_spec`.

### Out of scope

- No schema migrations (segment_rules is already JSON; campaign ledger reuses `Emails::Message`).
- No new RRULE features beyond the roll-forward fix.
- No changes to the flowchart builder itself (reference only).
- No changes to SMTP/DKIM delivery internals.

### Success criteria

- All targeted specs pass; existing email_campaigns specs stay green (normalization preserves old data).
- `lists/new` renders the grouped builder, no Advanced section, supports nested AND/OR groups; saved rules round-trip and produce the correct audience.
- Resume/re-trigger never double-sends.
- Test-send email renders inline images.
