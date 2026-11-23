# Email Module UI/UX Phase 2 Simplification & Premium Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate Email module navigation into 4 main sections (Overview, Campaigns, Audience, Settings) and refactor related views to feature premium stat card hover-lifts, accent colors, and modern gradient-filled SVG trend lines.

**Architecture:** 
1. Update `FeatureModules::Email::Registration` to return exactly 4 sidebar items (`overview`, `campaigns`, `audience`, `settings`).
2. Create/update shared tabs partials to support the 4 consolidated menus.
3. Update views under Overview and Campaigns to use consistent breadcrumbs, headers, and tabs.
4. Redesign stats cards and SVG trend lines to render premium UI gradients and shadows.

**Tech Stack:** Ruby on Rails, ViewComponent, TailwindCSS.

## Global Constraints

- No hard-coded user-facing strings; all UI text must use I18n for both `en` and `zh-CN`.
- All CSS styling must use TailwindCSS.
- Follow existing codebase ViewComponent patterns.
- Do not add new linters or tools.

---

### Task 1: Update Locales for 4-Item Sidebar and Overview Navigation

**Files:**
- Modify: `config/locales/feature_modules.en.yml`
- Modify: `config/locales/feature_modules.zh-CN.yml`

**Interfaces:**
- Produces: Updated locale keys with 4 main entries (`overview`, `campaigns`, `audience`, `settings`) and appropriate translation tags.

- [ ] **Step 1: Update English translations**
Edit `config/locales/feature_modules.en.yml` to set the new 4 sidebar entries and add dashboard/analytics keys under tabs.
```yaml
# config/locales/feature_modules.en.yml
en:
  feature_modules:
    email:
      name: "Email"
      entries:
        overview: "Overview"
        campaigns: "Campaigns"
        audience: "Audience"
        settings: "Settings"
      tabs:
        dashboard: "Dashboard"
        contacts: "Contacts"
        lists: "Lists"
        segments: "Segments"
        tags: "Tags"
        signup_forms: "Signup Forms"
        block_list: "Block-List"
        templates: "Templates"
        reports: "Reports"
        deliverability: "Deliverability"
        engagement: "Engagement"
        streams: "Streams"
        suppressions: "Suppressions"
        preference_topics: "Preference Topics"
```

- [ ] **Step 2: Update Chinese translations**
Edit `config/locales/feature_modules.zh-CN.yml` similarly.
```yaml
# config/locales/feature_modules.zh-CN.yml
zh-CN:
  feature_modules:
    email:
      name: "邮件"
      entries:
        overview: "概览"
        campaigns: "营销活动"
        audience: "受众"
        settings: "设置"
      tabs:
        dashboard: "仪表盘"
        contacts: "联系人"
        lists: "列表"
        segments: "分群"
        tags: "标签"
        signup_forms: "注册表单"
        block_list: "屏蔽名单"
        templates: "模板"
        reports: "报告"
        deliverability: "送达率"
        engagement: "互动"
        streams: "邮件流"
        suppressions: "退信名单"
        preference_topics: "偏好主题"
```

- [ ] **Step 3: Stage Locales**
```bash
git add config/locales/feature_modules.en.yml config/locales/feature_modules.zh-CN.yml
```

---

### Task 2: Refactor Email Module Sidebar Registration

**Files:**
- Modify: `app/services/feature_modules/email/registration.rb`
- Modify: `spec/services/feature_modules/email/registration_spec.rb`

**Interfaces:**
- Produces: Exactly 4 sidebar entries for `email` module assignment.

- [ ] **Step 1: Simplify `sidebar_contributions` in `Registration`**
Edit `app/services/feature_modules/email/registration.rb` to return only 4 main entries (`overview`, `campaigns`, `audience`, `settings`) and ensure tab highlights map correctly.
```ruby
      def self.sidebar_contributions(context)
        customer = context&.current_customer
        base = "/#{customer.id}/admin/modules/emails"

        entries = [
          entry("overview", "#{base}/dashboard", tab_paths: %w[dashboard reports deliverability engagement])
        ]

        if campaigns_enabled?(customer)
          entries << entry("campaigns", "#{base}/campaigns", tab_paths: %w[campaigns automations templates])
        else
          entries << entry("campaigns", "#{base}/automations", tab_paths: %w[automations templates])
        end

        entries.concat([
          entry("audience", "#{base}/contacts",
                tab_paths: %w[contacts lists segments tags signup_forms block_list]),
          entry("settings", "#{base}/streams", tab_paths: %w[streams suppressions preference_topics])
        ])

        {
          entries: entries,
          settings: [ModuleContribution.new(label: I18n.t("feature_modules.email.settings.daily_cap"), entry_key: "daily_cap")]
        }
      end
```

- [ ] **Step 2: Update `registration_spec.rb`**
Edit `spec/services/feature_modules/email/registration_spec.rb` to assert the 4-item structure.
```ruby
# spec/services/feature_modules/email/registration_spec.rb
require "rails_helper"

RSpec.describe FeatureModules::Email::Registration do
  let(:customer) { create(:customer) }
  let(:context) { double("Context", current_customer: customer) }

  it "returns exactly 4 sidebar contributions" do
    contributions = described_class.sidebar_contributions(context)
    entries = contributions[:entries]
    expect(entries.size).to eq(4)
    expect(entries.map(&:entry_key)).to match_array(%w[overview campaigns audience settings])
  end
end
```

- [ ] **Step 3: Run Registration Spec**
```bash
bundle exec rspec spec/services/feature_modules/email/registration_spec.rb
```
Expected: PASS

- [ ] **Step 4: Stage Registration changes**
```bash
git add app/services/feature_modules/email/registration.rb spec/services/feature_modules/email/registration_spec.rb
```

---

### Task 3: Implement Reusable Navigation Tab Partials

**Files:**
- Create: `app/views/admin/modules/emails/shared/_overview_tabs.html.erb`
- Create: `app/views/admin/modules/emails/shared/_campaigns_tabs.html.erb`
- Delete: `app/views/admin/modules/emails/shared/_content_tabs.html.erb`
- Delete: `app/views/admin/modules/emails/shared/_analytics_tabs.html.erb`

**Interfaces:**
- Produces: Navigation tabs matching the simplified menu categories.

- [ ] **Step 1: Create `_overview_tabs.html.erb`**
Write the following contents:
```erb
<%# app/views/admin/modules/emails/shared/_overview_tabs.html.erb %>
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

- [ ] **Step 2: Create `_campaigns_tabs.html.erb`**
Write the following contents:
```erb
<%# app/views/admin/modules/emails/shared/_campaigns_tabs.html.erb %>
<%
  is_campaigns_enabled = FeatureModules::Email::Registration.campaigns_enabled?(current_customer)
  tabs = []
  if is_campaigns_enabled
    tabs << { label: t("feature_modules.email.tabs.campaigns"), path: admin_modules_emails_campaigns_path(current_customer.id), active: active_tab == :campaigns }
  end
  tabs.concat([
    { label: t("feature_modules.email.tabs.automations"), path: admin_modules_emails_automations_path(current_customer.id), active: active_tab == :automations },
    { label: t("feature_modules.email.tabs.templates"), path: admin_modules_emails_templates_path(current_customer.id), active: active_tab == :templates }
  ])
%>
<%= render Emails::TabsComponent.new(tabs: tabs) %>
```

- [ ] **Step 3: Remove old content/analytics tab files**
```bash
rm -f app/views/admin/modules/emails/shared/_content_tabs.html.erb
rm -f app/views/admin/modules/emails/shared/_analytics_tabs.html.erb
git add app/views/admin/modules/emails/shared/
```

---

### Task 4: Upgrade Overview Sub-views & Visual Redesigns

**Files:**
- Modify: `app/views/admin/modules/emails/dashboard/show.html.erb`
- Modify: `app/components/emails/reports_component.html.erb`
- Modify: `app/components/emails/deliverability_component.html.erb`
- Modify: `app/components/emails/engagement_component.html.erb`
- Modify: `app/components/emails/sparkline_component.rb`
- Modify: `app/components/emails/sparkline_component.html.erb`

**Interfaces:**
- Produces: Polished metric card layouts with colored left borders, interactive animations on hover, and modern trend-line SVGs with fading gradient fills.

- [ ] **Step 1: Redesign Dashboard show view**
Apply breadcrumbs to point to "Overview" and use `_overview_tabs`. Refactor stat cards to have left border accents, shadow effects, and transform hover effects. Redesign daily trend charts using linear area-gradients in the SVG lines.
```erb
<%# app/views/admin/modules/emails/dashboard/show.html.erb %>
<%
  quick_actions = [
    { label: t("admin_modules.emails.dashboard.quick_actions.new_template"), path: new_admin_modules_emails_template_path(current_customer_id), variant: :primary, icon: :plus },
    { label: t("admin_modules.emails.dashboard.quick_actions.new_automation"), path: new_admin_modules_emails_automation_path(current_customer_id), variant: :secondary, icon: :plus }
  ]
  if FeatureModules::Email::Registration.campaigns_enabled?(current_customer)
    quick_actions << { label: t("admin_modules.emails.dashboard.quick_actions.new_campaign"), path: new_admin_modules_emails_campaign_path(current_customer_id), variant: :secondary, icon: :plus }
  end
%>
<%= render AdminPageComponent.new(
      breadcrumbs: [{ label: t("admin_modules.nav.modules") }, { label: t("feature_modules.email.entries.overview") }, { label: t("feature_modules.email.tabs.dashboard") }],
      title: t("feature_modules.email.entries.overview"),
      description: t("admin_modules.emails.dashboard.description"),
      actions: quick_actions
    ) do %>

  <%= render "admin/modules/emails/shared/overview_tabs", active_tab: :dashboard %>

  <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
    <% [
      { key: :sent,         value: @stats[:totals][:sent], border: "border-l-indigo-500 text-indigo-600 dark:text-indigo-400" },
      { key: :delivered,    value: @stats[:totals][:delivered], border: "border-l-emerald-500 text-emerald-600 dark:text-emerald-400" },
      { key: :bounced,      value: @stats[:totals][:bounced], border: "border-l-rose-500 text-rose-600 dark:text-rose-400" },
      { key: :complained,   value: @stats[:totals][:complained], border: "border-l-orange-500 text-orange-600 dark:text-orange-400" },
      { key: :suppressed,   value: @stats[:totals][:suppressed], border: "border-l-amber-500 text-amber-600 dark:text-amber-400" },
      { key: :opened,       value: @stats[:totals][:opened], border: "border-l-sky-500 text-sky-600 dark:text-sky-400" },
      { key: :clicked,      value: @stats[:totals][:clicked], border: "border-l-pink-500 text-pink-600 dark:text-pink-400" },
      { key: :unsubscribed, value: @stats[:totals][:unsubscribed], border: "border-l-violet-500 text-violet-600 dark:text-violet-400" }
    ].each do |stat| %>
      <div class="bg-white dark:bg-zinc-800 p-4 rounded shadow-sm border border-zinc-200 dark:border-zinc-700 border-l-4 <%= stat[:border].split(' ').first %> hover:shadow-md hover:-translate-y-0.5 transition-all duration-200 transform">
        <div class="text-sm text-zinc-500 dark:text-zinc-400 mb-1 font-medium"><%= t("admin_modules.emails.dashboard.stats.#{stat[:key]}") %></div>
        <div class="text-2xl font-semibold text-zinc-900 dark:text-white"><%= number_with_delimiter(stat[:value]) %></div>
      </div>
    <% end %>
  </div>

  <h3 class="text-lg font-semibold text-zinc-900 dark:text-white mb-4"><%= t("admin_modules.emails.dashboard.daily_trend") %></h3>

  <div class="bg-white dark:bg-zinc-800 rounded shadow-sm border border-zinc-200 dark:border-zinc-700 overflow-hidden mb-8">
    <table class="w-full text-left border-collapse">
      <thead>
        <tr class="border-b border-zinc-200 dark:border-zinc-700 bg-zinc-50/50 dark:bg-zinc-900/50">
          <th class="p-4 text-sm font-semibold text-zinc-500 dark:text-zinc-400"><%= t("admin_modules.emails.dashboard.stats.metric") %></th>
          <th class="p-4 text-sm font-semibold text-zinc-500 dark:text-zinc-400"><%= t("admin_modules.emails.dashboard.stats.trend_30_days") %></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-zinc-200 dark:divide-zinc-700">
        <%
          metrics = [
            { key: :sent, color: "indigo" },
            { key: :delivered, color: "emerald" },
            { key: :bounced, color: "rose" },
            { key: :opened, color: "sky" },
            { key: :clicked, color: "pink" }
          ]
          daily_data = @stats[:daily]
          width = 300
          height = 40
        %>
        <% metrics.each do |metric| %>
          <% 
            values = daily_data.map { |d| d[metric[:key]] }
            max = values.max || 0
            max = 1 if max.zero?
            points = values.map.with_index do |val, i|
              x = (i.to_f / [values.size - 1, 1].max) * width
              y = height - ((val.to_f / max) * height)
              y = [[y, 2].max, height - 2].min
              "#{x},#{y}"
            end.join(" ")
            
            fill_points = "0,#{height} #{points} #{width},#{height}"
            color_hex = case metric[:color]
                        when "indigo" then "rgb(99,102,241)"
                        when "emerald" then "rgb(16,185,129)"
                        when "rose" then "rgb(244,63,94)"
                        when "sky" then "rgb(14,165,233)"
                        when "pink" then "rgb(236,72,153)"
                        end
          %>
          <tr>
            <td class="p-4 text-sm text-zinc-900 dark:text-white font-medium w-1/4">
              <%= t("admin_modules.emails.dashboard.stats.#{metric[:key]}") %>
            </td>
            <td class="p-4 w-3/4">
              <svg class="w-full h-10 text-<%= metric[:color] %>-500 overflow-visible" viewBox="0 0 <%= width %> <%= height %>" preserveAspectRatio="none">
                <defs>
                  <linearGradient id="gradient-<%= metric[:key] %>" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stop-color="<%= color_hex %>" stop-opacity="0.2"/>
                    <stop offset="100%" stop-color="<%= color_hex %>" stop-opacity="0"/>
                  </linearGradient>
                </defs>
                <polygon points="<%= fill_points %>" fill="url(#gradient-<%= metric[:key] %>)" />
                <polyline points="<%= points %>" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
<% end %>
```

- [ ] **Step 2: Redesign `sparkline_component` ruby class**
Add customizable support for passing colors to sparklines.
```ruby
# app/components/emails/sparkline_component.rb
# frozen_string_literal: true

module Emails
  class SparklineComponent < ApplicationComponent
    attr_reader :values, :color, :width, :height

    def initialize(values:, color: "indigo", width: 300, height: 40)
      @values = values
      @color  = color
      @width  = width
      @height = height
    end

    def points
      return "" if values.empty?
      max = values.max || 0
      max = 1 if max.zero?
      values.map.with_index do |val, i|
        x = (i.to_f / [values.size - 1, 1].max) * width
        y = height - ((val.to_f / max) * height)
        y = [[y, 2].max, height - 2].min
        "#{x},#{y}"
      end.join(" ")
    end

    def fill_points
      "0,#{height} #{points} #{width},#{height}"
    end

    def color_hex
      case color
      when "indigo" then "rgb(99,102,241)"
      when "emerald" then "rgb(16,185,129)"
      when "rose" then "rgb(244,63,94)"
      when "sky" then "rgb(14,165,233)"
      when "pink" then "rgb(236,72,153)"
      else "rgb(99,102,241)"
      end
    end
  end
end
```

- [ ] **Step 3: Redesign `sparkline_component` template**
Update template to draw linear gradient-filled area polygons under trend lines.
```erb
<% % if values.any? %>
  <svg class="w-full h-10 text-<%= color %>-500 overflow-visible" viewBox="0 0 <%= width %> <%= height %>" preserveAspectRatio="none">
    <defs>
      <linearGradient id="sparkline-grad-<%= object_id %>" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="<%= color_hex %>" stop-opacity="0.15"/>
        <stop offset="100%" stop-color="<%= color_hex %>" stop-opacity="0"/>
      </linearGradient>
    </defs>
    <polygon points="<%= fill_points %>" fill="url(#sparkline-grad-<%= object_id %>)" />
    <polyline points="<%= points %>" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
  </svg>
<% else %>
  <div class="h-10 flex items-center text-xs text-zinc-400"><%= t("common.labels.no_data", default: "No data") %></div>
<% end %>
```

- [ ] **Step 4: Update Reports view**
Edit `app/components/emails/reports_component.html.erb` to standard breadcrumbs pointing to `Overview` and use `_overview_tabs`. Refactor stat cards to have left border accents and hover lifts, and pass correct colors to the sparkline renders.

- [ ] **Step 5: Redesign Deliverability view**
Edit `app/components/emails/deliverability_component.html.erb` to use `Overview` headers and `_overview_tabs`. Add colored border accents to metric cards.

- [ ] **Step 6: Redesign Engagement view**
Edit `app/components/emails/engagement_component.html.erb` similarly with standard `_overview_tabs` and beautiful border-accent metric cards.

- [ ] **Step 7: Run ViewComponent Specs**
```bash
bundle exec rspec spec/components/emails/sparkline_component_spec.rb
```
Expected: PASS

- [ ] **Step 8: Stage Visual Redesigns**
```bash
git add app/views/admin/modules/emails/dashboard/show.html.erb app/components/emails/
```

---

### Task 5: Adapt Campaigns and Templates Sub-views

**Files:**
- Modify: `app/views/admin/modules/emails/campaigns/index.html.erb`
- Modify: `app/views/admin/modules/emails/automations/index.html.erb`
- Modify: `app/views/admin/modules/emails/templates/index.html.erb`

**Interfaces:**
- Produces: Consistent `Campaigns` headers and tabs across campaigns, automations, and templates.

- [ ] **Step 1: Redesign Campaigns index view**
Update title and breadcrumbs to say "Campaigns", and render the updated `_campaigns_tabs`.
```erb
<%# app/views/admin/modules/emails/campaigns/index.html.erb %>
<%= render AdminPageComponent.new(
      breadcrumbs: [{ label: t("admin_modules.nav.modules") }, { label: t("feature_modules.email.entries.campaigns") }, { label: t("feature_modules.email.tabs.campaigns") }],
      title: t("feature_modules.email.entries.campaigns"),
      description: t("admin_modules.emails.campaigns.index.description"),
      actions: [{ label: t("admin_modules.emails.campaigns.actions.new_campaign"), path: new_admin_modules_emails_campaign_path(current_customer_id), variant: :primary, icon: :plus }]
    ) do %>
  <%= render "admin/modules/emails/shared/campaigns_tabs", active_tab: :campaigns %>
  <%= render AdminTableComponent.new(
        rows:       @rows,
        columns:    @columns,
        search_url: admin_modules_emails_campaigns_path(current_customer_id)
      ) %>
<% end %>
```

- [ ] **Step 2: Redesign Automations index view**
Update title/breadcrumbs to "Campaigns" and render `_campaigns_tabs`.
```erb
<%# app/views/admin/modules/emails/automations/index.html.erb %>
<%= render AdminPageComponent.new(
      breadcrumbs: [{ label: t("admin_modules.nav.modules") }, { label: t("feature_modules.email.entries.campaigns") }, { label: t("feature_modules.email.tabs.automations") }],
      title: t("feature_modules.email.entries.campaigns"),
      description: t("admin_modules.emails.automations.index.description"),
      actions: [{ label: t("admin_modules.emails.automations.actions.new_automation"), path: new_admin_modules_emails_automation_path(current_customer_id), variant: :primary, icon: :plus }]
    ) do %>
  <%= render "admin/modules/emails/shared/campaigns_tabs", active_tab: :automations %>
  <%= render AdminTableComponent.new(
        rows:       @rows,
        columns:    @columns,
        search_url: admin_modules_emails_automations_path(current_customer_id)
      ) %>
<% end %>
```

- [ ] **Step 3: Redesign Templates index view**
Update title/breadcrumbs to "Campaigns" and render `_campaigns_tabs`.
```erb
<%# app/views/admin/modules/emails/templates/index.html.erb %>
<%= render AdminPageComponent.new(
      breadcrumbs: [{ label: t("admin_modules.nav.modules") }, { label: t("feature_modules.email.entries.campaigns") }, { label: t("feature_modules.email.tabs.templates") }],
      title: t("feature_modules.email.entries.campaigns"),
      description: t("admin_modules.emails.templates.index.description"),
      actions: [{ label: t("admin_modules.emails.templates.actions.new_template"), path: new_admin_modules_emails_template_path(current_customer_id), variant: :primary, icon: :plus }]
    ) do %>
  <%= render "admin/modules/emails/shared/campaigns_tabs", active_tab: :templates %>
  <%= render AdminTableComponent.new(
        rows:       @rows,
        columns:    @columns,
        search_url: admin_modules_emails_templates_path(current_customer_id)
      ) %>
<% end %>
```

- [ ] **Step 4: Stage modified index views**
```bash
git add app/views/admin/modules/emails/campaigns/index.html.erb app/views/admin/modules/emails/automations/index.html.erb app/views/admin/modules/emails/templates/index.html.erb
```

---

### Task 6: Request Specs and Final Validation

**Files:**
- Modify: `spec/routing/admin/modules/emails/emails_routing_spec.rb`

- [ ] **Step 1: Run all email module specs**
Ensure that routing and controller request specs pass properly under the new headers.
```bash
bundle exec rspec spec/routing/admin/modules/emails/emails_routing_spec.rb
```
Expected: PASS

- [ ] **Step 2: Clean up assets manifest and reload tailwind build**
Remove the asset manifest and build assets to verify Tailwind compiles fine.
```bash
rm -f public/assets/.manifest.json
bin/rails tailwindcss:build
```
Expected: Successful assets precompilation without CSS syntax errors.
