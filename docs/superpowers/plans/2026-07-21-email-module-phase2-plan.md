# Email Module Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate Email module navigation into 4 main sections: Overview, Campaigns, Audience, Settings.

**Architecture:** Update `Registration` to return 4 sidebar entries. Create/modify shared tabs partials to include the consolidated views.

**Tech Stack:** Ruby on Rails, ViewComponent, TailwindCSS.

## Global Constraints

- No hard-coded user-facing strings; all UI text must use I18n for both `en` and `zh-CN`.
- All CSS styling must use TailwindCSS.
- Follow existing codebase ViewComponent patterns.
- Do not add new linters or tools.

---

### Task 1: Update Locales and Registration

**Files:**
- Modify: `config/locales/feature_modules.en.yml`
- Modify: `config/locales/feature_modules.zh-CN.yml`
- Modify: `app/services/feature_modules/email/registration.rb`
- Modify: `spec/services/feature_modules/email/registration_spec.rb`

**Interfaces:**
- Produces: Updated locale keys and flattened 4-item sidebar.

- [ ] **Step 1: Update Locales**
In both `en` and `zh-CN`, replace `dashboard` with `overview`, merge analytics tabs into overview tabs, and merge content tabs into campaigns tabs.

- [ ] **Step 2: Update `Registration.rb`**
Return `overview`, `campaigns`, `audience`, and `settings` as the main entries.

- [ ] **Step 3: Update `registration_spec.rb`**
Assert the new 4-item structure.

- [ ] **Step 4: Commit**
```bash
git add config/locales/feature_modules.* app/services/feature_modules/email/registration.rb spec/services/feature_modules/email/registration_spec.rb
git commit -m "refactor: consolidate email sidebar into 4 items"
```

---

### Task 2: Implement Overview Tabs (Dashboard + Analytics)

**Files:**
- Create: `app/views/admin/modules/emails/shared/_overview_tabs.html.erb`
- Modify: `app/views/admin/modules/emails/dashboard/show.html.erb`
- Modify: `app/views/admin/modules/emails/reports/index.html.erb`
- Modify: `app/views/admin/modules/emails/deliverability/index.html.erb`
- Modify: `app/views/admin/modules/emails/engagement/index.html.erb`
- Delete: `app/views/admin/modules/emails/shared/_analytics_tabs.html.erb`

**Interfaces:**
- Produces: Overview tabs (Dashboard | Reports | Deliverability | Engagement)

- [ ] **Step 1: Create `_overview_tabs.html.erb`**
```erb
<%
  tabs = [
    { label: t("feature_modules.email.tabs.dashboard"), path: admin_modules_emails_dashboard_path(current_customer.id), active: active_tab == :dashboard },
    { label: t("feature_modules.email.tabs.reports"), path: admin_modules_emails_reports_path(current_customer.id), active: active_tab == :reports },
    { label: t("feature_modules.email.tabs.deliverability"), path: admin_modules_emails_deliverability_index_path(current_customer.id), active: active_tab == :deliverability },
    { label: t("feature_modules.email.tabs.engagement"), path: admin_modules_emails_engagement_index_path(current_customer.id), active: active_tab == :engagement }
  ]
%>
<%= render Emails::TabsComponent.new(tabs: tabs) %>
```

- [ ] **Step 2: Inject tabs into views**
Update dashboard, reports, deliverability, and engagement views to render `_overview_tabs` and set `title`/`breadcrumbs` to "Overview". Delete `_analytics_tabs.html.erb`.

- [ ] **Step 3: Commit**
```bash
git add app/views/admin/modules/emails/shared/ app/views/admin/modules/emails/{dashboard,reports,deliverability,engagement}/
git commit -m "feat: implement overview tabs"
```

---

### Task 3: Implement Campaigns Tabs (Campaigns + Automations + Templates + Assets)

**Files:**
- Create: `app/views/admin/modules/emails/shared/_campaigns_tabs.html.erb`
- Modify: `app/views/admin/modules/emails/campaigns/index.html.erb`
- Modify: `app/views/admin/modules/emails/automations/index.html.erb`
- Modify: `app/views/admin/modules/emails/templates/index.html.erb`
- Modify: `app/views/admin/modules/emails/assets/index.html.erb`
- Delete: `app/views/admin/modules/emails/shared/_content_tabs.html.erb`

**Interfaces:**
- Produces: Campaigns tabs

- [ ] **Step 1: Create `_campaigns_tabs.html.erb`**
```erb
<%
  is_campaigns_enabled = FeatureModules::Email::Registration.campaigns_enabled?(current_customer)
  tabs = []
  if is_campaigns_enabled
    tabs << { label: t("feature_modules.email.tabs.campaigns"), path: admin_modules_emails_campaigns_path(current_customer.id), active: active_tab == :campaigns }
  end
  tabs.concat([
    { label: t("feature_modules.email.tabs.automations"), path: admin_modules_emails_automations_path(current_customer.id), active: active_tab == :automations },
    { label: t("feature_modules.email.tabs.templates"), path: admin_modules_emails_templates_path(current_customer.id), active: active_tab == :templates },
    { label: t("feature_modules.email.tabs.assets"), path: admin_modules_emails_assets_path(current_customer.id), active: active_tab == :assets }
  ])
%>
<%= render Emails::TabsComponent.new(tabs: tabs) %>
```

- [ ] **Step 2: Inject tabs into views**
Update campaigns, automations, templates, and assets views to render `_campaigns_tabs` and set `title`/`breadcrumbs` to "Campaigns". Delete `_content_tabs.html.erb`.

- [ ] **Step 3: Commit**
```bash
git add app/views/admin/modules/emails/shared/ app/views/admin/modules/emails/{campaigns,automations,templates,assets}/
git commit -m "feat: implement campaigns tabs"
```

---

### Task 4: Fix Specs

**Files:**
- Modify: `spec/requests/admin/modules/emails/dashboard_spec.rb` (if exists)
- Modify: `spec/requests/admin/modules/emails/automations_spec.rb`
- Modify: `spec/requests/admin/modules/emails/campaigns_spec.rb`
- Modify: `spec/requests/admin/modules/emails/templates_spec.rb`
- Modify: `spec/requests/admin/modules/emails/assets_spec.rb`

**Interfaces:**
- Produces: Passing specs.

- [ ] **Step 1: Update request specs**
Ensure request specs check for the new translated titles ("Overview", "Campaigns") where applicable.

- [ ] **Step 2: Commit**
```bash
git commit -am "test: fix specs for phase 2 email module simplification"
```
