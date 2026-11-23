# Email Module Mailchimp IA + Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reshape Email admin IA to Mailchimp-style peers (Audience / Send Activities / Content / Analytics), fix labeling bugs, merge analytics, replace RRULE text with presets, then Figma-polish Email surfaces inside AdminPage chrome.

**Architecture:** Update `FeatureModules::Email::Registration` sidebar + tab partials first; add Content tabs and Analytics Health surface with redirects from old analytics URLs; map recurrence presets ↔ RRULE in campaign wizard; Figma via `anysys-ux-designer` before visual polish; prune stale locales/orphan views last.

**Tech Stack:** Rails 8.1.2, ViewComponent, Tailwind, Stimulus (only if needed), RSpec, Vitest (if JS changes), Figma MCP / `anysys-ux-designer`

**Spec:** `docs/superpowers/specs/2026-07-24-email-module-mailchimp-ia-visual-redesign-design.md`

## Global Constraints

- I18n: every user-facing string in both `en` and `zh-CN`; English value byte-identical to former hard-coded copy when replacing hard-coded text
- No Settings entry under Modules → Email; settings path `/:cid/admin/settings/modules/emails`
- When `campaigns_enabled=false`: sidebar = Audience + Content only (hide Campaigns and Analytics)
- Messages live under Content tabs with Templates
- Recurrence UI presets only: None / Daily / Weekly / Monthly → RRULE `nil` / `FREQ=DAILY;INTERVAL=1` / `FREQ=WEEKLY;INTERVAL=1` / `FREQ=MONTHLY;INTERVAL=1`
- Status value `retired` stays in DB; UI label = Archived
- Visual polish stays on AdminPage / AdminTable / Emails::TabsComponent — no Email page shell fork
- Do not auto-commit unless the human explicitly asks; plan commit steps are optional checkpoints
- Follow AGENTS.md SDLC: UI/UX polish requires Figma (`anysys-ux-designer`) before ViewComponent edits for Task 7+

---

## File map

| File | Responsibility |
|------|----------------|
| `app/services/feature_modules/email/registration.rb` | Sidebar entries, match_prefix, settings path, lists columns |
| `config/locales/feature_modules.en.yml` + `.zh-CN.yml` | Entry/tab labels (content, analytics, remove stale shells) |
| `config/locales/admin_modules.en.yml` + `.zh-CN.yml` | Page copy, recurrence presets, Archived label, suppressions titles |
| `app/views/admin/modules/emails/shared/_content_tabs.html.erb` | Templates \| Messages tabs (new) |
| `app/views/admin/modules/emails/shared/_analytics_tabs.html.erb` | Overview \| Health tabs (new; replaces overview_tabs) |
| `app/views/admin/modules/emails/shared/_audience_tabs.html.erb` | Unchanged set; used with corrected page titles |
| `app/views/admin/modules/emails/shared/_campaigns_tabs.html.erb` | Delete after Content split (or stop rendering) |
| `app/views/admin/modules/emails/templates/*.erb` | Content tabs + active-tab titles |
| `app/views/admin/modules/emails/messages/*.erb` | Content tabs + sidebar match |
| `app/views/admin/modules/emails/suppressions/index.html.erb` | Audience title (not Settings) |
| `app/views/admin/modules/emails/contacts/*`, `lists/*` | Audience titles = active tab where needed |
| `app/views/admin/modules/emails/dashboard/show.html.erb` | Analytics Overview (merge report bits) |
| `app/controllers/admin/modules/emails/health_controller.rb` | New Health index |
| `app/components/emails/health_component.rb` (+ erb) | Deliverability + engagement UI |
| `app/components/emails/overview_component.rb` (+ erb) optional | Or enhance dashboard/reports components in place |
| `config/routes.rb` | `health` resource; redirects for reports/deliverability/engagement |
| `app/services/emails/campaigns/recurrence_presets.rb` | Preset ↔ RRULE mapping |
| `app/views/.../campaigns/_wizard_step_setup.html.erb` | Preset select |
| `app/controllers/.../campaigns_controller.rb` + `services/emails/campaigns/build.rb` | Accept preset param → recurrence_rule |
| `app/views/.../campaigns/show.html.erb` | AdminPage chrome |
| Orphan dirs under `app/views/admin/modules/emails/{automations,block_list,...}` | Delete if empty leftovers |
| Specs under `spec/services/feature_modules/email/`, `spec/requests/admin/modules/emails/` | Update for IA + health + recurrence |

---

### Task 1: Sidebar IA — Content / Analytics / gating / Settings path

**Files:**
- Modify: `app/services/feature_modules/email/registration.rb`
- Modify: `config/locales/feature_modules.en.yml`
- Modify: `config/locales/feature_modules.zh-CN.yml`
- Test: `spec/services/feature_modules/email/registration_spec.rb`

**Interfaces:**
- Consumes: `campaigns_enabled?(customer)` (existing)
- Produces: `sidebar_contributions` entries:
  - campaigns on: `audience`, `campaigns`, `content`, `analytics`
  - campaigns off: `audience`, `content`
  - `settings:` array still exposes `daily_cap` for Settings nav (not Modules sidebar entries)
  - content `match_prefix`: templates + messages
  - analytics `match_prefix`: dashboard + health (and temporarily old paths until Task 3 redirects)
  - campaigns `match_prefix`: campaigns only (templates move to content)
  - settings path string: `"/#{customer.id}/admin/settings/modules/emails"`

- [ ] **Step 1: Write the failing registration specs**

Replace sidebar examples in `registration_spec.rb` with:

```ruby
describe ".sidebar_contributions" do
  let(:controller) { double("controller", current_customer: customer) }
  let!(:email_module) do
    FeatureModules::Module.find_or_create_by!(key: "email") do |fm|
      fm.name = "Email"
      fm.status = :active
    end
  end

  context "when campaigns are disabled" do
    before { ensure_customer_feature_module(customer, email_module, status: :active) }

    it "lists audience and content only" do
      keys = described_class.sidebar_contributions(controller)[:entries].map(&:entry_key)
      expect(keys).to eq(%w[audience content])
    end
  end

  context "when campaigns are enabled" do
    before do
      ensure_customer_feature_module(customer, email_module, status: :active,
                                    configuration: { "campaigns_enabled" => true }.to_json)
    end

    it "lists audience, campaigns, content, analytics" do
      keys = described_class.sidebar_contributions(controller)[:entries].map(&:entry_key)
      expect(keys).to eq(%w[audience campaigns content analytics])
    end

    it "points campaigns at campaigns only" do
      entry = described_class.sidebar_contributions(controller)[:entries].find { |e| e.entry_key == "campaigns" }
      expect(entry.path.call(customer)).to eq("/#{customer.id}/admin/modules/emails/campaigns")
      expect(entry.match_prefix).to eq(["/#{customer.id}/admin/modules/emails/campaigns"])
    end

    it "matches content to templates and messages" do
      entry = described_class.sidebar_contributions(controller)[:entries].find { |e| e.entry_key == "content" }
      expect(entry.path.call(customer)).to eq("/#{customer.id}/admin/modules/emails/templates")
      expect(entry.match_prefix).to eq([
        "/#{customer.id}/admin/modules/emails/templates",
        "/#{customer.id}/admin/modules/emails/messages"
      ])
    end

    it "matches analytics to dashboard and health" do
      entry = described_class.sidebar_contributions(controller)[:entries].find { |e| e.entry_key == "analytics" }
      expect(entry.path.call(customer)).to eq("/#{customer.id}/admin/modules/emails/dashboard")
      expect(entry.match_prefix).to include(
        "/#{customer.id}/admin/modules/emails/dashboard",
        "/#{customer.id}/admin/modules/emails/health"
      )
    end
  end

  it "does not put settings in module sidebar entries" do
    keys = described_class.sidebar_contributions(controller)[:entries].map(&:entry_key)
    expect(keys).not_to include("settings")
  end

  it "exposes daily_cap under settings contributions with plural emails path available via SettingsContributor" do
    settings = described_class.sidebar_contributions(controller)[:settings].map(&:entry_key)
    expect(settings).to eq(["daily_cap"])
  end
end
```

Also fix `lists_entry_config` expectations later in Task 5 if status column assertions exist; for this task only change sidebar.

- [ ] **Step 2: Run spec to verify fail**

Run: `bundle exec rspec spec/services/feature_modules/email/registration_spec.rb --format documentation`

Expected: FAIL on entry_keys still `%w[overview campaigns audience settings]`

- [ ] **Step 3: Implement registration + locales**

In `registration.rb` `sidebar_contributions`:

```ruby
def self.sidebar_contributions(context)
  customer = context&.current_customer
  base = "/#{customer.id}/admin/modules/emails"

  entries = [
    entry("audience", "#{base}/contacts", tab_paths: %w[contacts lists suppressions]),
    entry("content", "#{base}/templates", tab_paths: %w[templates messages])
  ]

  if campaigns_enabled?(customer)
    entries.insert(1, entry("campaigns", "#{base}/campaigns", tab_paths: %w[campaigns]))
    entries << entry("analytics", "#{base}/dashboard", tab_paths: %w[dashboard health])
  end

  {
    entries: entries,
    settings: [ModuleContribution.new(label: I18n.t("feature_modules.email.settings.daily_cap"), entry_key: "daily_cap")]
  }
end
```

Locales (`feature_modules.en.yml`):

```yaml
entries:
  audience: "Audience"
  campaigns: "Campaigns"
  content: "Content"
  analytics: "Analytics"
tabs:
  templates: "Templates"
  messages: "Messages"
  contacts: "Contacts"
  lists: "Lists"
  suppressions: "Suppressions"
  overview: "Overview"   # Analytics Overview tab
  health: "Health"
settings:
  daily_cap: "Daily send cap"
```

Mirror idiomatic zh-CN in `feature_modules.zh-CN.yml` (e.g. 内容 / 分析 / 健康 / 每日发送上限). Remove or stop relying on obsolete entry keys `overview`/`settings` as sidebar entries (keep tab keys as needed).

Remove stale Status column from `lists_entry_config` if still present:

```ruby
columns: [
  { key: :name, label: I18n.t("common.labels.name"), searchable: true },
  { key: :description, label: I18n.t("common.labels.description") }
]
```

(Lists index controller already defines real columns — registration config is for generic entries resolver.)

- [ ] **Step 4: Run registration spec**

Run: `bundle exec rspec spec/services/feature_modules/email/registration_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 5: Commit (only if human asks)**

```bash
git add app/services/feature_modules/email/registration.rb config/locales/feature_modules.en.yml config/locales/feature_modules.zh-CN.yml spec/services/feature_modules/email/registration_spec.rb
git commit -m "$(cat <<'EOF'
refactor(emails): Mailchimp-style sidebar IA and settings path

EOF
)"
```

---

### Task 2: Content + Audience tabs, titles, Suppressions fix, Messages wiring

**Files:**
- Create: `app/views/admin/modules/emails/shared/_content_tabs.html.erb`
- Modify: `app/views/admin/modules/emails/templates/index.html.erb`, `new.html.erb`, `edit.html.erb` (and any that render campaigns_tabs)
- Modify: `app/views/admin/modules/emails/messages/index.html.erb`, `show.html.erb`
- Modify: `app/views/admin/modules/emails/suppressions/index.html.erb`
- Modify: `app/views/admin/modules/emails/contacts/index.html.erb`, `show.html.erb`
- Modify: `app/views/admin/modules/emails/lists/index.html.erb` (+ new/edit/show as needed)
- Modify: `app/views/admin/modules/emails/campaigns/index.html.erb` — remove campaigns_tabs if only campaigns remain
- Delete or stop using: `app/views/admin/modules/emails/shared/_campaigns_tabs.html.erb`
- Modify: `config/locales/admin_modules.en.yml` + `.zh-CN.yml` for descriptions/titles if needed
- Test: `spec/requests/admin/modules/emails/suppressions_spec.rb`, `messages_spec.rb`, `templates_spec.rb`

**Interfaces:**
- Consumes: `Emails::TabsComponent`, path helpers
- Produces: `_content_tabs` with `active_tab:` `:templates` | `:messages`

- [ ] **Step 1: Failing request expectations**

In `suppressions_spec.rb` add/adjust:

```ruby
it "titles the page Suppressions under Audience" do
  get admin_modules_emails_suppressions_path(customer)
  expect(response.body).to include(I18n.t("feature_modules.email.tabs.suppressions"))
  expect(response.body).not_to include(">#{I18n.t("feature_modules.email.entries.settings")}<")
end
```

In `messages_spec.rb`:

```ruby
it "renders Content tabs with Messages active" do
  get admin_modules_emails_messages_path(customer)
  expect(response.body).to include(I18n.t("feature_modules.email.tabs.messages"))
  expect(response.body).to include(I18n.t("feature_modules.email.tabs.templates"))
end
```

In `templates_spec.rb` index example: expect Content entry breadcrumbs/title Templates (not Campaigns entry label as page H1).

- [ ] **Step 2: Run to verify fail**

Run: `bundle exec rspec spec/requests/admin/modules/emails/suppressions_spec.rb spec/requests/admin/modules/emails/messages_spec.rb --format documentation`

Expected: FAIL on Settings title / missing Content tabs

- [ ] **Step 3: Implement tabs + titles**

`_content_tabs.html.erb`:

```erb
<%
  tabs = [
    { label: t("feature_modules.email.tabs.templates"), path: admin_modules_emails_templates_path(current_customer.id), active: active_tab == :templates },
    { label: t("feature_modules.email.tabs.messages"), path: admin_modules_emails_messages_path(current_customer.id), active: active_tab == :messages }
  ]
%>
<%= render Emails::TabsComponent.new(tabs: tabs) %>
```

Templates index AdminPage:

```erb
breadcrumbs: [
  { label: t("admin_modules.nav.modules") },
  { label: t("feature_modules.email.entries.content") },
  { label: t("feature_modules.email.tabs.templates") }
],
title: t("feature_modules.email.tabs.templates"),
description: t("admin_modules.emails.templates.index.description"),
```

Render `content_tabs` with `active_tab: :templates`. Same pattern for messages (`active_tab: :messages`, title Messages).

Suppressions:

```erb
breadcrumbs: [
  { label: t("admin_modules.nav.modules") },
  { label: t("feature_modules.email.entries.audience") },
  { label: t("feature_modules.email.tabs.suppressions") }
],
title: t("feature_modules.email.tabs.suppressions"),
description: t("admin_modules.emails.suppressions.description"),
```

Contacts/Lists: title = active tab label (`Contacts` / `Lists`), parent breadcrumb Audience.

Campaigns index: title Campaigns; **do not** render templates tab.

- [ ] **Step 4: Run request specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/suppressions_spec.rb spec/requests/admin/modules/emails/messages_spec.rb spec/requests/admin/modules/emails/templates_spec.rb --format progress`

Expected: PASS (update any brittle string matchers)

- [ ] **Step 5: Optional commit** (if human asks)

---

### Task 3: Analytics Overview | Health + redirects

**Files:**
- Create: `app/controllers/admin/modules/emails/health_controller.rb`
- Create: `app/components/emails/health_component.rb`
- Create: `app/components/emails/health_component.html.erb`
- Create: `app/views/admin/modules/emails/health/index.html.erb`
- Create: `app/views/admin/modules/emails/shared/_analytics_tabs.html.erb`
- Modify: `app/controllers/admin/modules/emails/dashboard_controller.rb`
- Modify: `app/views/admin/modules/emails/dashboard/show.html.erb`
- Modify: `app/components/emails/reports_component.*` (reuse KPI/campaign table on Overview) **or** fold report into dashboard view
- Modify: `config/routes.rb` (emails namespace)
- Modify: old controllers to redirect: `reports_controller`, `deliverability_controller`, `engagement_controller` → permanent redirect actions **or** route-level redirects
- Test: `spec/requests/admin/modules/emails/dashboard_spec.rb`, new `health_spec.rb`, update `reports_spec.rb` / `deliverability_spec.rb` / `engagement_spec.rb` for redirects
- Locales: analytics tab labels, health copy

**Interfaces:**
- Produces: `GET .../emails/health` → HealthComponent with totals, failure_breakdown, suppressions, top_links, devices, opens (reuse private logic from DeliverabilityController + EngagementController — extract to `Emails::Analytics::Health` service if >~40 lines duplicated)
- Overview: Dashboard show uses `Emails::DashboardStats` + `Emails::Analytics::Report` for campaigns table + CSV link to `admin_modules_emails_dashboard_path(..., format: :csv)` **or** keep CSV on a redirected reports path that still serves CSV — prefer moving CSV to dashboard `respond_to`

- [ ] **Step 1: Failing routing/request specs**

```ruby
# spec/requests/admin/modules/emails/health_spec.rb
RSpec.describe "Admin::Modules::Emails::Health", type: :request do
  # auth/customer setup matching other email request specs
  it "returns 200 and Health tab copy" do
    get admin_modules_emails_health_index_path(customer)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("feature_modules.email.tabs.health"))
  end
end

# in reports_spec / deliverability_spec / engagement_spec
it "redirects to the merged analytics surface" do
  get admin_modules_emails_reports_path(customer)
  expect(response).to redirect_to(admin_modules_emails_dashboard_path(customer))

  get admin_modules_emails_deliverability_index_path(customer)
  expect(response).to redirect_to(admin_modules_emails_health_index_path(customer))

  get admin_modules_emails_engagement_index_path(customer)
  expect(response).to redirect_to(admin_modules_emails_health_index_path(customer))
end
```

- [ ] **Step 2: Run — expect fail (missing route/helper)**

Run: `bundle exec rspec spec/requests/admin/modules/emails/health_spec.rb spec/requests/admin/modules/emails/reports_spec.rb --format documentation`

- [ ] **Step 3: Routes**

Inside `namespace :emails`:

```ruby
get "dashboard", to: "dashboard#show", as: :dashboard
resources :health, only: %i[index]
# keep old routes but point to redirect actions, or:
get "reports", to: redirect { |path_params, _req|
  "/#{path_params[:customer_id]}/admin/modules/emails/dashboard"
}
get "deliverability", to: redirect { |path_params, _req|
  "/#{path_params[:customer_id]}/admin/modules/emails/health"
}
get "engagement", to: redirect { |path_params, _req|
  "/#{path_params[:customer_id]}/admin/modules/emails/health"
}
```

Prefer controller redirects if named route helpers must remain for CSV — e.g. ReportsController#index redirects HTML but still serves CSV, **or** move CSV to DashboardController.

Recommended: DashboardController gains CSV via `Emails::Analytics::ExportCsv` (copy from ReportsController); ReportsController#index always redirects to dashboard.

- [ ] **Step 4: Health controller + component**

Move deliverability + engagement queries into `Emails::Analytics::Health.for(customer, since:, until_date:, reason:)` returning a hash, then HealthComponent renders AdminPage + analytics_tabs + sections.

`_analytics_tabs.html.erb`:

```erb
<%
  tabs = [
    { label: t("feature_modules.email.tabs.overview"), path: admin_modules_emails_dashboard_path(current_customer.id), active: active_tab == :overview },
    { label: t("feature_modules.email.tabs.health"), path: admin_modules_emails_health_index_path(current_customer.id), active: active_tab == :health }
  ]
%>
<%= render Emails::TabsComponent.new(tabs: tabs) %>
```

Dashboard/Overview AdminPage title: `t("feature_modules.email.tabs.overview")`; parent breadcrumb Analytics.

Delete or gut unused deliverability/engagement/reports views once redirects work (keep thin redirect controllers if helpers still referenced).

- [ ] **Step 5: Run analytics specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/dashboard_spec.rb spec/requests/admin/modules/emails/health_spec.rb spec/requests/admin/modules/emails/reports_spec.rb spec/requests/admin/modules/emails/deliverability_spec.rb spec/requests/admin/modules/emails/engagement_spec.rb --format progress`

Expected: PASS

- [ ] **Step 6: Optional commit**

---

### Task 4: Recurrence presets in campaign wizard

**Files:**
- Create: `app/services/emails/campaigns/recurrence_presets.rb`
- Test: `spec/services/emails/campaigns/recurrence_presets_spec.rb`
- Modify: `app/views/admin/modules/emails/campaigns/_wizard_step_setup.html.erb`
- Modify: `app/views/admin/modules/emails/campaigns/_form.html.erb` if it still has RRULE text
- Modify: `app/services/emails/campaigns/build.rb` — map `recurrence_preset` → `recurrence_rule`
- Modify: `app/controllers/admin/modules/emails/campaigns_controller.rb` if strong params live there
- Modify: review partial to show human preset label
- Locales: `admin_modules.emails.campaigns.form.recurrence_presets.*`
- Test: `spec/requests/admin/modules/emails/campaigns_spec.rb`

**Interfaces:**
- Produces:

```ruby
module Emails
  module Campaigns
    module RecurrencePresets
      PRESETS = {
        "none" => nil,
        "daily" => "FREQ=DAILY;INTERVAL=1",
        "weekly" => "FREQ=WEEKLY;INTERVAL=1",
        "monthly" => "FREQ=MONTHLY;INTERVAL=1"
      }.freeze

      def self.rrule_for(preset) = PRESETS.fetch(preset.to_s) { raise KeyError, preset }
      def self.preset_for(rrule)
        return "none" if rrule.blank?
        PRESETS.key(rrule).presence || "none" # unknown legacy → none in UI; model validation still owns illegality on save if edited elsewhere
      end
      def self.select_options
        PRESETS.keys.map { |k| [I18n.t("admin_modules.emails.campaigns.form.recurrence_presets.#{k}"), k] }
      end
    end
  end
end
```

For unknown existing RRULEs (e.g. HOURLY): on edit, show None **or** add disabled blank — prefer: if `preset_for` nil, include a one-off option labeled via i18n `custom_unsupported` that maps back to keeping the same rule only if we pass through — **YAGNI:** coerce display to none and require re-pick; saving Setup without change would clear rule unless Build only writes recurrence_rule when preset param present. Safer Build logic:

```ruby
if params[:email_campaign].key?(:recurrence_preset)
  attrs[:recurrence_rule] = RecurrencePresets.rrule_for(params[:email_campaign][:recurrence_preset])
end
```

- [ ] **Step 1: Failing unit spec**

```ruby
RSpec.describe Emails::Campaigns::RecurrencePresets do
  it "maps presets to RRULE" do
    expect(described_class.rrule_for("daily")).to eq("FREQ=DAILY;INTERVAL=1")
    expect(described_class.rrule_for("none")).to be_nil
  end

  it "maps RRULE back to preset" do
    expect(described_class.preset_for("FREQ=WEEKLY;INTERVAL=1")).to eq("weekly")
    expect(described_class.preset_for(nil)).to eq("none")
  end
end
```

- [ ] **Step 2: Run — fail missing constant**

Run: `bundle exec rspec spec/services/emails/campaigns/recurrence_presets_spec.rb -v`

- [ ] **Step 3: Implement service + wizard field**

Setup partial:

```erb
<div>
  <%= label_tag "email_campaign_recurrence_preset", t("admin_modules.emails.campaigns.form.recurrence_label"), class: "form-label" %>
  <%= select_tag "email_campaign[recurrence_preset]",
        options_for_select(
          Emails::Campaigns::RecurrencePresets.select_options,
          Emails::Campaigns::RecurrencePresets.preset_for(f.object.recurrence_rule)
        ),
        class: "input-field mt-1" %>
</div>
```

Remove hard-coded RRULE placeholder and examples caption (or replace caption with i18n hint that recurrence is daily/weekly/monthly).

Wire Build/permit `recurrence_preset`.

- [ ] **Step 4: Request spec create with daily preset**

Assert campaign `recurrence_rule` == `FREQ=DAILY;INTERVAL=1`. Assert response body has no literal `FREQ=DAILY;INTERVAL=1` as input placeholder.

- [ ] **Step 5: Run campaigns + presets specs — PASS**

- [ ] **Step 6: Optional commit**

---

### Task 5: Campaign show AdminPage + Archived label + row-action wording

**Files:**
- Modify: `app/views/admin/modules/emails/campaigns/show.html.erb`
- Modify: locales for `set_retired` → display "Archive" / "Archived" (keys may stay `set_retired` / `retired` for stability — **change English values** to Archive/Archived per AGENTS i18n rule)
- Modify: template index row action labels via locales only
- Test: `spec/requests/admin/modules/emails/campaigns_spec.rb`, `templates_spec.rb` (expect Archive not "Set retired")

- [ ] **Step 1: Failing template spec on copy**

```ruby
expect(response.body).to include(I18n.t("admin_modules.emails.templates.status.actions.set_retired"))
# after locale change English is "Archive"
```

Update expectation to `"Archive"` via I18n.

- [ ] **Step 2: Change en/zh-CN strings**

```yaml
set_retired: "Archive"
retired: "Archived"
```

zh-CN: idiomatic 归档 / 已归档 (replace 设为停用 / 已停用 if those were the old strings — update both locales in parity).

- [ ] **Step 3: Rewrite campaign show with AdminPageComponent**

Match other email show pages: breadcrumbs Modules / Campaigns / name; actions array for Send/Pause/etc.; body cards unchanged functionally.

- [ ] **Step 4: Run specs — PASS**

---

### Task 6: Prune stale leftovers

**Files:**
- Delete empty/orphan view dirs if unused: `app/views/admin/modules/emails/{automations,block_list,preference_topics,segments,signup_forms,streams,tags}` (verify no render/controller first)
- Clean stale keys in `feature_modules.*.yml` (automations, streams, signup_forms, block_list, segments, preference_topics) and duplicate `email.preview` in `email.en.yml`
- Grep for removed constants/paths; fix any leftover references
- Test: `bundle exec rspec spec/services/feature_modules/email spec/routing/admin/modules/emails --format progress`

- [ ] **Step 1: Grep safety**

```bash
rg -n "automations|signup_forms|preference_topics|email_streams|Emails::Audience::Tag" app config spec --glob '!docs/**' | head -50
```

- [ ] **Step 2: Delete confirmed orphans + locale cleanup**

- [ ] **Step 3: Run routing + registration specs — PASS**

---

### Task 7: Figma design pass (required before polish code)

**Files:** Figma file via plugin; write UX notes under `docs/superpowers/ux/` if the designer agent produces them

**Interfaces:** Consumes Section 4 of the design spec; produces layout specs for KPI cards, tabs+titles, wizard stepper, composer, empty states, suppressions toolbar, campaign show actions

- [ ] **Step 1: Dispatch `anysys-ux-designer`** with the approved spec path and screenshot paths `/tmp/email-*.png` if still available; require designs that reuse AdminPage spacing/typography tokens

- [ ] **Step 2: Human reviews Figma** — do not start Task 8 until approved

---

### Task 8: Implement Figma polish

**Files:** (exact set from Task 7 output — expected candidates)
- `app/components/emails/sparkline_component.*` / shared KPI partial or `Emails::MetricCardComponent`
- `app/components/emails/campaign_builder_component.html.erb` (token classes)
- `app/views/admin/modules/emails/templates/_workspace.html.erb`
- `app/views/admin/modules/emails/suppressions/index.html.erb` toolbar
- Template index row_actions rendering (controller or component)
- Component specs as needed

- [ ] **Step 1: Implement against Figma** — Tailwind only; no new CSS framework

- [ ] **Step 2: Component/request specs for structure** (CSS class presence only if already patterned in suite)

- [ ] **Step 3: If Stimulus added/changed — `npx vitest run --coverage` must show 100% on touched files**

- [ ] **Step 4: Browser smoke**

```bash
# server already: SKIP_AUTH=1 on :3000
npx playwright screenshot --viewport-size=1280,900 \
  "http://127.0.0.1:3000/81721200/admin/modules/emails/templates" /tmp/email-content-after.png
npx playwright screenshot --viewport-size=1280,900 \
  "http://127.0.0.1:3000/81721200/admin/modules/emails/suppressions" /tmp/email-suppressions-after.png
npx playwright screenshot --viewport-size=1280,900 \
  "http://127.0.0.1:3000/81721200/admin/modules/emails/dashboard" /tmp/email-analytics-after.png
```

Verify sidebar labels Content/Analytics; Suppressions title; Overview|Health tabs.

---

### Task 9: Full email-module verification

- [ ] **Step 1: RSpec email scope**

Run: `bundle exec rspec spec/models/emails spec/services/emails spec/services/email spec/services/feature_modules/email spec/jobs/emails spec/requests/admin/modules/emails spec/requests/emails spec/components/emails spec/routing/admin/modules/emails --format progress`

Expected: 0 failures

- [ ] **Step 2: Vitest if JS touched**

Run: `npx vitest run --coverage`

Expected: touched files 100% lines/branches

- [ ] **Step 3: Manual gating check** — toggle `(removed) campaigns_enabled` false in Settings → Email; confirm sidebar Audience + Content only; Analytics/Campaigns hidden; Settings only under top Settings nav at `/…/settings/modules/emails`

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Mailchimp sidebar peers + gating | Task 1 |
| Settings under `/settings/modules/emails`, not sidebar | Task 1 |
| Messages under Content | Task 1–2 |
| Suppressions title fix + active-tab titles | Task 2 |
| Analytics Overview \| Health + redirects | Task 3 |
| Recurrence presets | Task 4 |
| Campaign show AdminPage + Archived labels | Task 5 |
| Prune leftovers | Task 6 |
| Figma then polish | Tasks 7–8 |
| Success criteria / verification | Task 9 |

No TBD placeholders. RRULE mapping matches spec. `retired` value retained with Archived label.

