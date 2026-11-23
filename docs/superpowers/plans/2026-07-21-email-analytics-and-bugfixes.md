# Email Analytics Pages + Underlying Bug Fixes Implementation Plan

> **For agentic workers:** Work directly on `master`; do NOT auto-commit. Use model `kimi-k2.7-code` for all subagents. Follow I18n parity (`en` + `zh-CN`), Tailwind-only styling, ViewComponent encapsulation for new UI surfaces, and strict tenant scoping.

**Goal:** Finish the Email module analytics pages (Reports, Deliverability, Engagement) and fix the suppression/global-scope bugs discovered in the email module.

**Architecture:** Keep the existing Overview tab layout (Dashboard | Reports | Deliverability | Engagement). Replace the placeholder analytics views with responsive ViewComponents that render the data already computed by the controllers. Fix the suppression layer so global provider suppressions are still enforced at delivery time but are no longer visible or deletable from a tenant admin UI.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, TailwindCSS, StimulusJS, RSpec.

## Global Constraints

- Work on `master`; do NOT run `git commit`.
- Every user-facing string must use I18n with matching keys in `config/locales/*.en.yml` and `config/locales/*.zh-CN.yml`.
- Use TailwindCSS only; no custom CSS.
- Encapsulate new UI surfaces in ViewComponents; do not inline markup in controller views.
- Preserve strict customer scoping and admin/owner authorization.
- Use `kimi-k2.7-code` for every subagent.

---

### Task 1: Implement Email Analytics UI (Reports / Deliverability / Engagement)

**Files:**
- Create: `app/components/emails/reports_component.rb`
- Create: `app/components/emails/reports_component.html.erb`
- Create: `app/components/emails/deliverability_component.rb`
- Create: `app/components/emails/deliverability_component.html.erb`
- Create: `app/components/emails/engagement_component.rb`
- Create: `app/components/emails/engagement_component.html.erb`
- Modify: `app/views/admin/modules/emails/reports/index.html.erb`
- Modify: `app/views/admin/modules/emails/deliverability/index.html.erb`
- Modify: `app/views/admin/modules/emails/engagement/index.html.erb`
- Modify: `config/locales/admin_modules.en.yml`
- Modify: `config/locales/admin_modules.zh-CN.yml`
- Test: `spec/components/emails/reports_component_spec.rb`
- Test: `spec/components/emails/deliverability_component_spec.rb`
- Test: `spec/components/emails/engagement_component_spec.rb`
- Test: `spec/requests/admin/modules/emails/reports_spec.rb`
- Test: `spec/requests/admin/modules/emails/deliverability_spec.rb`
- Test: `spec/requests/admin/modules/emails/engagement_spec.rb`

**Interfaces:**
- Consumes: `Emails::Analytics::Report.for(...)` result shape `{ since:, until_date:, totals:, daily:, streams:, campaigns: }`.
- Consumes: Deliverability controller assigns `@totals`, `@stream_breakdown`, `@failure_breakdown`, `@suppressions`.
- Consumes: Engagement controller assigns `@top_links`, `@opens_by_hour`, `@opens_by_day`, `@devices`.
- Produces: responsive components that render stat cards, date-range form, tables, empty states, and CSV export link.

- [ ] Create `Emails::ReportsComponent` to show date-range form, totals cards, daily trend table/sparkline, stream/campaign breakdowns, and CSV export link. Use existing `Emails::TabsComponent` and `AdminPageComponent`. Resolve stream/campaign IDs to names.
- [ ] Create `Emails::DeliverabilityComponent` to show totals cards, stream breakdown table, failure-code breakdown table, and recent suppressions table with empty states.
- [ ] Create `Emails::EngagementComponent` to show top clicked links, opens-by-hour, opens-by-day, and device breakdown with empty states.
- [ ] Replace placeholder copy in the three `index.html.erb` views with `render Emails::<X>Component.new(...)`.
- [ ] Add any missing `admin_modules.emails.analytics.*` locale keys in both languages.
- [ ] Add component specs covering rendering with data and empty states.
- [ ] Strengthen request specs for reports/deliverability/engagement to assert that real data is rendered and cross-tenant data is excluded.

### Task 2: Fix Suppression Tenant Scoping in the Model

**Files:**
- Modify: `app/models/emails/suppression.rb`
- Test: `spec/models/emails/suppression_spec.rb`

**Interfaces:**
- Produces: `Emails::Suppression.for_customer(cid)` returns only rows where `customer_id = cid`.
- Preserves: `Emails::Suppression.suppressed?` still matches both global (`customer_id nil`) and tenant rows so delivery gating continues to work.

- [ ] Change `scope :for_customer` from `where(customer_id: [nil, cid])` to `where(customer_id: cid)`.
- [ ] Keep `suppressed?` using `where(customer_id: [nil, customer_id])` unchanged.
- [ ] Update `spec/models/emails/suppression_spec.rb` so the `.for_customer` test expects tenant-only rows (no global rows) and add a dedicated test that `suppressed?` still honors global rows.

### Task 3: Fix Suppression Controller / Routes Bugs

**Files:**
- Modify: `app/controllers/admin/modules/emails/suppressions_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/admin/modules/emails/suppressions_spec.rb`
- Test: `spec/routing/admin/modules/emails/emails_routing_spec.rb`

**Interfaces:**
- Produces: `batch_unblock` destroys only rows scoped to `current_customer.id`.
- Produces: exactly one `resources :suppressions` declaration inside the email namespace, with `collection { delete :batch_unblock }`.
- Produces: removal of the obsolete `/email_campaigns/*path` redirect.

- [ ] Change `batch_unblock` to `::Emails::Suppression.where(id: ids, customer_id: current_customer.id).destroy_all`.
- [ ] Remove the duplicate `resources :suppressions, only: :index` line near line 474 of `config/routes.rb`.
- [ ] Remove the temporary `/email_campaigns/*path` redirect block near line 507 of `config/routes.rb`.
- [ ] Update `spec/requests/admin/modules/emails/suppressions_spec.rb` to assert global suppressions are NOT visible on the index and NOT deletable via batch_unblock, and that tenant-owned rows remain deletable.
- [ ] Update the routing spec if any routes changed.

### Task 4: QA / Release Verification

**Files:**
- Test: all touched specs above.

- [ ] Run the touched request, component, model, and routing specs in one invocation and confirm green.
- [ ] Run locale parity check for `admin_modules.emails.analytics` and `feature_modules.email.tabs`.
- [ ] If any JavaScript is changed, run `npx vitest run --coverage` and require 100% for touched files.
