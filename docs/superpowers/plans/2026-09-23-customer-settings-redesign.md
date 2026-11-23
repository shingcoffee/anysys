# Customer settings redesign — implementation plan

Date: 2026-09-23

Status: **READY_FOR_FRONTEND — brainstorming finalized; parent-approved.**

Design: [Customer settings UX](../specs/2026-09-23-customer-settings-brainstorm-ux.md). Scope: `/81721200/admin/settings` and all nested screens, forms, dialogs, conditional actions and generic module configuration destinations. Preserve the broad existing worktree, particularly website work.

## 1. Approved IA

Overview and one settings search; five groups with direct destination links. Paths below are relative to the settings root.

| Group | Destinations |
| --- | --- |
| People & access | Member portal → `/member`; Member registration → `/modules/authentication/sign_up`; Password reset → `/modules/authentication/forget_password`; **Account security → `/modules/authentication`**; Roles & permissions → `/modules/authentication/roles`; User access → `/modules/authentication/user_role_assignments`; Public page protection → `/modules/captcha` |
| Website & tools | Website → `/modules/website`; AI assistant → `/modules/ai_assistant` |
| Communication | Email sending limit → `/modules/emails/daily_cap`; Email personalization → `/modules/emails/template_tokens`; SMS sending limit → `/modules/sms/daily_cap` |
| Receive payments | Payment providers → `/modules/payments/merchant_accounts` |
| Subscription & billing | Plan & subscription → `/billing/subscription`; Billing payment methods → `/billing/payment_methods`; Invoices → `/billing/invoices` |

Preserve module visibility/availability and existing permission filters. Retain unknown future contributions with readable fallback placement within Website & tools when no explicit group exists. Sidebar, search and overview use consistent descriptors/destinations. Deep pages highlight their most specific destination; Account security matches the generic authentication root exactly, never also highlighting its child routes. Overview links to named tasks, not an arbitrary first child.

## 2. Shared APIs and scope

- `Admin::Settings::PageComponent(customer_id:, title:, description: nil, breadcrumbs: [], actions: [], badges: [], width: :wide)` wraps `AdminPageComponent`, prepends the linked Settings root crumb, forwards actions/badges and owns width. Additional crumbs use existing `label`/`path` hashes; consumers omit the root crumb. One H1 per page.
- `Admin::Settings::SectionComponent(title: nil, description: nil, id: nil)` uses flat whitespace/hairlines. Optional collapsed Advanced content uses local native `details`/`summary`.
- Reuse `.form-label`, `.input-field`, shared font/button tokens, `ButtonComponent`, `FormErrorsComponent`, badges and alerts. Avoid Field/FormActions abstractions unless genuine reuse warrants them. Explicit actions per actual operation; no fictitious atomic saves or changed autosave semantics.
- Muted neutral design, readable form widths inside the wide page, responsive stacked fields and searchable mobile settings navigation. Preserve global admin chrome, keyboard/focus behavior and all nested-page context.
- Existing customer return-route overrides remain accessible under plain-language Advanced disclosure with URL input and explicit save. Display readable defaults, never raw JSON. Global configuration stays in existing authorized Maintenance/Platform destinations; internal IDs/slugs are not customer wording.
- **Preserve existing routes and role/controller capabilities. No additional role types, grants, assignments, novel custom-role affordances, role/security schema changes or authorization rewrite.** The preexisting custom/multiple-role inconsistency is a non-blocking baseline. Security review addresses confirmed regressions.
- Only backend behavior change: preserve omitted member visibility arrays on partial update; explicitly submitted arrays retain existing semantics. No other backend feature expansion.

## 3. Six parallel lanes

Parent publishes the APIs above, then dispatches the lanes together. Shared files belong to A; other lanes consume its API and request shared edits through A. Each lane owns matching component/request/JS specs. Shared asset builds and global configuration belong to parent/release integration.

### A. Navigation + shared shell + overview — frontend

**Source ownership:** `app/services/settings_contributor.rb`; `app/components/sidebar_component.*`, `sidebar_node_component.*`; settings integration in `drawer_component.*`/`shell_component.*` as needed; new `app/components/admin/settings/page_component.*`, `section_component.*`; `admin/settings/catalog_component.*`; `app/views/admin/settings/show.html.erb`; relevant navigation Stimulus code/tests.

**Responsibilities:** approved grouping, Account security root, exact/deep active matching, existing availability/permission filters, future contribution fallback, stable Page/Section APIs, responsive navigation and one coherent overview/search directory with exact destinations. Avoid unrelated shell changes.

**Locales:** new `config/locales/settings_navigation.en.yml` / `.zh-CN.yml`, matching namespace; owns shared navigation/page wording. Others reuse without editing this pair.

### B. Member portal + access — frontend

**Source ownership:** `app/views/admin/settings/{members,member_sources,member_surfaces}/`; `app/components/admin/settings/member_{hub_card,source_row,surface_form}_component.*`; associated member display presenters; `app/views/admin/settings/modules/authentication/`; `app/components/admin/settings/modules/authentication/`; existing access-dialog/grants Stimulus presentation code/tests as needed.

**Responsibilities:** member hub, essential/module/record source lists, every display editor and row visibility toggle; registration/reset; role list/detail/new/edit, grants filters/review/save, user-assignment list/dialog. Apply shared page/section composition and readable labels; preserve payloads, locked choices, current operations and authorization. Coordinate partial toggle versus full-form array payloads with F. **Account security's generic body belongs to D; its navigation belongs to A.** Do not change role cardinality or introduce new role controls.

**Locales:** new `settings_people.en.yml` / `.zh-CN.yml`.

### C. Subscription + billing — frontend

**Source ownership:** `app/views/admin/settings/billing/`; customer-facing subscription/payment-method/invoice presentation under `app/components/billing/admin/`; matching specs. Preserve platform branches of shared components.

**Responsibilities:** subscription summary/plan comparison/coupon/cancel/resume; payment-method empty/populated/add/authorize/default/remove states; invoice index/detail/download/print. Clarify subscription expenses versus customer receipts. Preserve billing operations, redirects, conditional actions and customer-path invoice scope even for owner.

**Locales:** new `settings_billing.en.yml` / `.zh-CN.yml`.

### D. Generic + email + captcha + payment module UI — frontend

**Source ownership:** `app/views/admin/module_configs/show.html.erb` and settings-specific presentation extracted from it; `app/views/admin/settings/modules/{emails,captcha}/`; matching components; customer presentation in `app/components/payments/admin/{gateway_gallery,gateway_card,gateway_config,credential_fields,test_connection_result}_component.*`; relevant captcha picker/JS presentation and specs. Any necessary payment settings controller render-wrapper edits belong here and are presentation-only.

**Responsibilities:** Account security generic root, AI assistant, email/SMS caps and generic roots/entries; all schema-backed fields and independently saved return-URL overrides; personalization list/new/edit/delete; captcha status alias, page search and presets/custom controls; provider gallery, existing new redirect/create behavior, all provider/environment edits, defaults, enable/disable and connection tests. Add missing page titles/breadcrumbs. Preserve dynamic credentials, blank-secret retention, HTML/Turbo negotiation, availability checks, endpoint/payload semantics and existing operations. No new provider/security features.

**Locales:** new `settings_modules.en.yml` / `.zh-CN.yml`.

### E. Website settings — frontend

**Source ownership:** `app/views/admin/settings/modules/website/sites/show.html.erb`; `app/components/websites/admin/settings_form_component.*`, `skeleton_replace_component.*`, and directly associated settings presentation/controllers/specs. Inspect and build on existing uncommitted website work.

**Responsibilities:** shared wrapper and clear general/appearance/search/footer/publishing sections; retain theme preview, layout choice, footer add/edit/remove/reorder, publishing, view-site and starter replacement. Separate replacement from routine save without changing semantics. Do not expand into page-editor/platform-gallery redesign.

**Locales:** exclusively owns existing `website_settings.en.yml` / `.zh-CN.yml` for this task. Reuse website/common keys elsewhere; coordinate essential shared website-file changes through parent.

### F. Member partial-save omission preservation — backend

**Source ownership:** `app/concepts/member/settings/operation/update.rb`; `app/concepts/member/settings/contract/update.rb` only if necessary; `spec/concepts/member/settings/operation/update_spec.rb`.

**Responsibilities:** visibility-only row updates omitting `visible_column_keys`, `visible_section_keys`, or `visible_detail_row_keys` preserve customized lists. Explicit selected/empty arrays keep existing replacement/clear/default/required-field behavior. Preserve all other values, tenant scope, validation and authorization. Coordinate B's omitted versus explicitly empty payloads; no new controller or endpoint.

**Required operation specs:** customized arrays survive visibility-only updates; submitted arrays update correctly; explicit empties follow existing semantics; mixed partial updates preserve omitted arrays; current failure behavior remains intact. No locale pair needed; reuse existing validation keys.

## 4. Localization ownership

Use unique new namespaces matching `settings_navigation`, `settings_people`, `settings_billing`, `settings_modules`; E alone owns `website_settings`. Reuse identical preexisting translations and common action keys rather than duplicating them. Every new heading/label/hint/status/error/ARIA string has en/zh-CN parity. Stimulus strings use translated Values. Data keys remain stable behind readable labels. No concurrent edits to another lane's locale pair.

## 5. Verification and integration

1. **A:** targeted contributor/catalog/sidebar/Page/Section specs and `spec/requests/settings_spec.rb`; cover preserved filters, unknown contributions, exact search destinations and exactly one active item on deep authentication/payment/member routes.
2. **B/F:** relevant `spec/requests/admin/settings/{members,member_sources,member_surfaces}_spec.rb`, authentication request/component specs, and `spec/concepts/member/settings/operation/update_spec.rb`. Verify actual toggle payload preserves custom arrays while full forms can explicitly clear them.
3. **C/D/E:** affected billing request/component specs; email/captcha/payment merchant-account/default-gateway request/component specs; generic/AI/SMS settings specs; `spec/requests/websites/admin_settings_spec.rb` and touched website component specs. Use fixtures for conditional states absent from live seed data.
4. **Any JS change:** update matching suites and run `npx vitest run --config config/javascript/vitest.config.js --coverage`; verify touched testable files at 100% lines/branches/functions. Browser-only interactions receive corresponding Playwright coverage.
5. **Integrated QA:** compare reachable surfaces/actions with the parent's source inventory. Inspect root and every surface family at 390/768/1024/1440px in en/zh-CN: search/menu, selected ancestor, breadcrumbs, focus, validation, no clipping, truthful status and explicit per-operation actions. Use isolated fixtures for save/mutation tests; live discovery remains GET-only.
6. **Review:** anysys-security-engineer checks confirmed authorization/tenant/capability regressions against baseline; anysys-tech-lead and anysys-code-reviewer check conventions/correctness. Record existing role-policy issues without repairing them in this UI change. Verify no newly exposed global configuration or internal identifiers.
7. **Release:** after focused checks pass, build Tailwind and smoke-test the integrated app. If restarting, follow AGENTS.md manifest/clobber guidance and development `SKIP_AUTH=1`. No auto-commit. Broaden testing only when demonstrated impact warrants it; use project parallel RSpec workflow if a full run becomes necessary.

**Done:** all inventoried settings surfaces use the approved IA/composition; existing authorized actions, filters and future contributions remain reachable; partial saves preserve omitted lists; targeted checks and responsive bilingual checks pass; confirmed regressions are resolved. No further design confirmation required.
