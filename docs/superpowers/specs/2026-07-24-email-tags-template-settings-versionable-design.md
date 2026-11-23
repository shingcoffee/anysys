# Email module: remove Tags, prune template Settings, Versionable templates

**Date:** 2026-07-24  
**Status:** Approved for planning  
**Scope:** Email audience Tags; `Emails::Template` Settings/Status/versioning under `/:cid/admin/modules/emails`

## Problem

Email audience **Tags** add CRUD and contact UI without enough product value for the lean ESP. Template **edit** overloads Settings (key, type, category, variables, status) and Version History tabs. Status and version management should live on the templates **list**, matching Pages/Entities/Flowcharts. Template identification for sends still uses `template_key`; product wants ID-based lookup and a hard prune of non-Status settings fields.

## Goals

1. Fully remove contact Tags from the Email audience area (UI, routes, models, tables, associations).
2. Make template edit composer-only (no Settings / Version History tabs).
3. Keep **Status** as the only template settings field; make it actionable on the templates list with transition guards.
4. Migrate templates onto shared **Versionable** + list **Versions** modal (Pages parity).
5. Change Gateway/Send API from `template_key` to `template_id` (no backward-compat alias).

## Non-goals

- Customer Email module settings (`/:cid/admin/settings/modules/email`).
- Platform email credentials.
- Campaigns / lists / suppressions / reports rework (beyond Status guards referencing campaigns).
- Tag replacement taxonomy.
- Other modules' versioning changes.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Settings field prune | **Full schema prune** of `key`, `template_type`, `category`, `variables` |
| Settings scope | **Template only** (not customer module settings) |
| Tags | **Full removal** (tables + code) |
| Versioning | **Full Pages-like** `Versionable` + `VersionsModalComponent` |
| Status transitions | **Guarded** when non-terminal campaigns reference the template |
| Approach | **Approach 2** — drop `key`; Gateway/Send use `template_id` |

---

## Section 1 — Remove Tags

### Remove

- Audience tab entry for Tags; `resources :tags` under emails routes.
- `Admin::Modules::Emails::TagsController` and all tags views.
- Models `Emails::Audience::Tag`, `Emails::Audience::Tagging`.
- `Authentication::User` associations `email_taggings` / `email_tags`.
- Contacts index tags column and contacts show tags section.
- Factories, model/request specs, orphaned i18n keys for Tags (and dead automation tag-trigger copy if unused).

### Schema

- Migration drops `email_taggings` then `email_tags` (FK order).

### Deep links

- Former tags URLs → routing 404 (no redirect shim).

---

## Section 2 — Template Settings prune + Status on list

### Edit page

- Remove Settings and Version History tabs and tab chrome from template edit/form.
- Composer/workspace remains: name, subject, editor_type, body, preview, test send.
- Create defaults to `status: "draft"`; no Settings step.

### Schema / model prune

Drop from `email_templates` (and model constants/validations/UI/i18n form fields):

- `key` (+ unique index on `[customer_id, key]`)
- `template_type` (+ related index)
- `category`
- `variables`

**Retain on parent (identity):** `name`, `status`, `customer_id`, compose fields as needed, plus Versionable head pointer (see Section 3).

### Status on list

- Templates index exposes Status as an actionable control (not display-only badge).
- Dedicated update path (e.g. `PATCH …/templates/:id/status` or status-only update) persists `draft` / `active` / `retired`.
- **Guards:** reject transition **to** `draft` or `retired` while any campaign in a non-terminal status references the template (`email_template_id`). Show clear I18n error. Allow free transition among statuses when no such campaigns exist. Transition **to** `active` is always allowed (subject to auth/tenant).
- Auth: admin/owner only; tenant-scoped; cross-tenant blocked.

---

## Section 3 — Send API + Versionable versioning

### Gateway / Send

- Replace `template_key:` with `template_id:` on `Emails::Gateway`, `Emails::Activities::Send`, Reform send contract, feature-module registration flowchart property, and all callers/specs.
- Resolve template by `id` + `customer_id`. No `template_key` alias.
- Send continues to require template `status == "active"` (retain existing active check semantics).

### Versionable (Pages parity)

**New / reshaped storage:**

- `email_template_contents` — content-addressed (`content_hash`, `payload`, `customer_id`), same pattern as `page_configuration_contents`.
- `email_template_versions` — replace snapshot-JSON shape with Versionable columns: `email_template_id`, `version_number`, `content_id`, `based_on_version_id`, `description`, `customer_id`, timestamps.
- `email_templates.current_version_id` FK (nullify on destroy of version, matching Pages).

**Parent model:**

- `Emails::Template` includes `Versionable` via `acts_as_versionable`.
- Snapshot payload JSON: definition body — at minimum `subject`, `body_html`, `body_text`, `editor_type`, and rich-text body representation needed to restore ActionText.
- Identity fields stay on parent: `name`, `status` (not versioned as definition).
- Auto-commit on save when definition changes (Versionable `after_save`); status/name-only saves do not create versions.
- Data migration: for each existing template, create content + v1 from current columns, set `current_version_id`; then drop old snapshot table/columns and pruned settings columns. Prefer head-synced readable `subject`/`body_html` for send/render (reload-from-head pattern like Page), so Gateway does not join versions on every send.

**List UX:**

- Templates index wraps table with Stimulus `versions` controller + `VersionsModalComponent` (same as Pages).
- Row action "Version History" opens modal: list, view/diff, restore-as-new, set current, delete (current undeletable).

**Versions API:**

- Nested under module templates, JSON contract matching `Admin::Maintenance::BaseVersionsController` (`index` / `show` / `create` restore-as-new / `default` / `destroy`).
- Tenant-scoped; admin/owner only.
- Retire old HTML template_versions index/show and edit-tab restore UI once modal path works.

---

## Section 4 — Auth, i18n, testing

### Auth

- Status + versions endpoints on existing admin Email module controllers with admin/owner + `customer_id` scoping.
- Members and anonymous denied.

### I18n

- New strings (list Status control labels if any, status-guard errors, versions row action) in both `en` and `zh-CN`.
- Remove unused Tags / Settings-tab keys where orphaned.

### Tests

- Tags: routes gone; contacts no longer expose tags; migration drops tables.
- Template prune: model/request specs updated; no key/type/category/variables.
- Status list update + campaign guard + tenant isolation.
- Gateway/Send `template_id` contract and activity specs.
- Versionable: commit on definition change; restore-as-new; set current; delete protection; versions JSON API; empty history.
- Vitest only if Stimulus wiring for versions/status requires new JS (prefer reuse of existing `versions` controller).

---

## Success criteria

- No Tags surface or tables remain for Email audience.
- Template edit is composer-only.
- Status is the only template settings field and is changed from the list with campaign guards.
- Templates use Versionable + list Versions modal at Pages feature parity.
- Programmatic send uses `template_id` only.
