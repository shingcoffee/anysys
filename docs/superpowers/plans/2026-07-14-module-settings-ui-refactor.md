# Module Settings UI/UX Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **No-commit override:** per explicit user/project preference, do NOT run `git commit` at any point in this plan. Leave all changes uncommitted in the working tree for manual review. Steps below omit the "Commit" step from the standard template for this reason.

**Goal:** Refactor the platform owner's Module Settings UI (`/:cid/admin/maintenance/platform/module_settings`) — the show page, index page, and the SMS/Email platform credential form components it links to — for a more professional, scannable, at-ease experience, per the approved design at `docs/superpowers/specs/2026-07-14-module-settings-ui-refactor-design.md`.

**Architecture:** Pure view/ViewComponent-layer changes. No new database columns, migrations, routes, or controller logic. The show page moves from a single long scroll of ~9-10 stacked cards to: a compact header (absorbing the old "Module Info" card), one consolidated "Module Controls" card (replacing 3 near-duplicate toggle cards), and a two-tab layout (Settings / Technical Reference) using the already-present-but-unused `tabs_controller.js` Stimulus controller. The Configuration Schema form becomes type-aware (boolean → toggle checkbox, number/integer → number field). Two credential form components get design-token fixes for consistency.

**Tech Stack:** Rails 8.1 views/ViewComponents, Tailwind (existing design tokens only), Stimulus (`tabs_controller.js`, already implemented, zero JS changes), RSpec (request + component specs), Rails I18n (en + zh-CN).

---

## Task 1: I18n keys (en + zh-CN)

**Files:**
- Modify: `config/locales/maint_platform.en.yml`
- Modify: `config/locales/maint_platform.zh-CN.yml`

- [ ] **Step 1: Add new keys to `maint_platform.en.yml`**

In the `module_settings.index` block (currently lines 322-327), add `stats_summary` after `description`:

```yaml
      index:
        title: Module Settings
        description: Platform-wide module configuration and settings
        stats_summary: "%{total} total · %{active} active · %{required} required"
        owner_access: Platform Owner Access
        owner_access_hint: Changes here affect all customers using these modules.
        empty: No modules available
```

In the `module_settings.show` block, **remove** the now-unused `module_information` key (line 330: `module_information: Module Information`) since the "Module Info" card is absorbed into the page header — `module_key` and `version` stay (reused as `sr-only` labels in the new header). Add `controls_title`, `controls_subtitle`, and a `tabs` block right after `handoff_on_label` (currently line 342) and before the `sms:` block:

```yaml
        handoff_on_label: Handoff enabled
        controls_title: Module Controls
        controls_subtitle: Platform-wide switches that control this module's availability, requirement, and handoff eligibility.
        tabs:
          nav_label: Module settings sections
          settings: Settings
          technical: Technical Reference
          no_settings: This module has no additional settings to configure.
```

- [ ] **Step 2: Add the matching keys to `maint_platform.zh-CN.yml`**

In the `module_settings.index` block (currently lines 322-327):

```yaml
      index:
        title: 模块设置
        description: 平台级模块配置
        stats_summary: "共 %{total} 个 · %{active} 个已启用 · %{required} 个必需"
        owner_access: 平台所有者访问
        owner_access_hint: 此处的更改会影响所有使用这些模块的客户。
        empty: 暂无可用模块
```

Remove `module_information: 模块信息` (line 330) to match the English file. Add after `handoff_on_label` (currently line 342):

```yaml
        handoff_on_label: 已启用交接
        controls_title: 模块控制
        controls_subtitle: 控制此模块可用性、是否必需及可否交接的平台级开关。
        tabs:
          nav_label: 模块设置分区
          settings: 设置
          technical: 技术参考
          no_settings: 此模块暂无更多设置。
```

- [ ] **Step 3: Add SMS credential form legend key to both locale files**

`maint_platform.en.yml`, inside `sms.credentials.form` (currently ends at `secret_keep_hint`, find it near the `sms:` block under `credentials.form`):

```yaml
          provider_fields_legend: "%{provider} Settings"
```

`maint_platform.zh-CN.yml`, same nesting:

```yaml
          provider_fields_legend: "%{provider} 设置"
```

- [ ] **Step 4: Verify YAML parses and keys resolve**

Run: `bin/rails runner "puts I18n.t('maint_platform.module_settings.show.tabs.settings', locale: :en); puts I18n.t('maint_platform.module_settings.show.tabs.settings', locale: :'zh-CN'); puts I18n.t('maint_platform.sms.credentials.form.provider_fields_legend', provider: 'Aliyun', locale: :en)"`
Expected: prints `Settings`, `设置`, `Aliyun Settings` with no YAML/translation-missing errors.

---

## Task 2: Restructure the show page

**Files:**
- Modify: `app/views/admin/maintenance/platform/module_settings/show.html.erb` (full rewrite)

- [ ] **Step 1: Replace the file contents**

```erb
<%# app/views/platform/module_settings/show.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: t("maint_platform.module_settings.breadcrumbs.maintenance"), path: admin_maintenance_path(current_customer_id) },
  { label: t("maint_platform.module_settings.breadcrumbs.module_settings"), path: admin_maintenance_platform_module_settings_path(current_customer_id) },
  { label: @feature_module.name, path: nil }
]) %>

<div class="mb-6">
  <div class="flex items-center gap-3">
    <div class="w-10 h-10 rounded-lg bg-surface-active flex items-center justify-center">
      <svg class="w-5 h-5 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M21 7.5l-9-5.25L3 7.5m18 0l-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9"/>
      </svg>
    </div>
    <div>
      <h1 class="text-subtitle flex items-center gap-2 flex-wrap">
        <%= @feature_module.name %>
        <% if @feature_module.active? %>
          <%= render BadgeComponent.new(variant: :success, size: :sm) do %><%= t("common.status.active") %><% end %>
        <% else %>
          <%= render BadgeComponent.new(variant: :default, size: :sm) do %><%= t("common.status.inactive") %><% end %>
        <% end %>
        <% if @feature_module.required? %>
          <%= render BadgeComponent.new(variant: :warning, size: :sm) do %><%= t("common.labels.required") %><% end %>
        <% end %>
      </h1>
      <p class="text-body-sm"><%= @feature_module.description %></p>
      <div class="mt-1 flex items-center gap-1.5">
        <span class="sr-only"><%= t("maint_platform.module_settings.show.module_key") %>:</span>
        <span class="text-mono text-xs bg-surface-active px-1.5 py-0.5 rounded"><%= @feature_module.key %></span>
        <span class="text-caption" aria-hidden="true">&middot;</span>
        <span class="sr-only"><%= t("maint_platform.module_settings.show.version") %>:</span>
        <span class="text-caption"><%= @feature_module.version || "1.0" %></span>
      </div>
    </div>
  </div>
</div>

<%= render AlertComponent.new(message: notice, type: :success, auto_dismiss: true) if notice.present? %>
<%= render AlertComponent.new(message: alert, type: :error) if alert.present? %>

<div class="space-y-6">
  <%# Platform Warning %>
  <%= render AlertComponent.new(message: t("maint_platform.module_settings.show.platform_warning_html"), type: :warning) %>

  <%# Module Controls %>
  <div class="card overflow-hidden">
    <div class="px-6 py-4 border-b border-border-subtle">
      <h2 class="section-header"><%= t("maint_platform.module_settings.show.controls_title") %></h2>
      <p class="mt-0.5 text-caption"><%= t("maint_platform.module_settings.show.controls_subtitle") %></p>
    </div>
    <ul class="divide-y divide-border-subtle">
      <li class="px-6 py-4 flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 max-w-2xl">
          <h3 class="text-body text-text-primary font-medium"><%= t("maint_platform.module_settings.show.module_status") %></h3>
          <p class="text-caption"><%= t("maint_platform.module_settings.show.module_status_hint_html") %></p>
          <% if @feature_module.mandatory? %>
            <p class="mt-1 text-caption"><%= t("maint_platform.module_settings.show.locked_hint") %></p>
          <% end %>
        </div>
        <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
              url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module),
              field: "status_active",
              on: @feature_module.active?,
              disabled: @feature_module.mandatory?,
              on_label: t("common.status.active"), off_label: t("common.status.inactive")
            ) %>
      </li>
      <li class="px-6 py-4 flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 max-w-2xl">
          <h3 class="text-body text-text-primary font-medium"><%= t("maint_platform.module_settings.show.required_module") %></h3>
          <p class="text-caption"><%= t("maint_platform.module_settings.show.required_module_hint_html") %></p>
        </div>
        <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
              url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module),
              field: "required",
              on: @feature_module.required?,
              disabled: @feature_module.mandatory? || !@feature_module.active?,
              confirm: @feature_module.required? ? nil : t("maint_platform.module_settings.show.required_confirm"),
              on_label: t("maint_platform.module_settings.show.required_on_label"), off_label: t("common.labels.optional")
            ) %>
      </li>
      <li class="px-6 py-4 flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 max-w-2xl">
          <h3 class="text-body text-text-primary font-medium"><%= t("maint_platform.module_settings.show.handoff_target") %></h3>
          <p class="text-caption"><%= t("maint_platform.module_settings.show.handoff_target_hint_html") %></p>
        </div>
        <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
              url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module),
              field: "handoff_enabled",
              on: @feature_module.handoff_enabled?,
              disabled: !@feature_module.active?,
              on_label: t("maint_platform.module_settings.show.handoff_on_label"), off_label: t("common.status.disabled")
            ) %>
      </li>
    </ul>
  </div>

  <%# ── Tabs: Settings (default) / Technical Reference ─────────────── %>
  <% schema = @feature_module.configuration_schema_json || {} %>
  <% settings_tab_has_content = @feature_module.key.in?(%w[sms email payment]) || schema.any? %>
  <div data-controller="tabs" data-tabs-active-value="settings">
    <div class="border-b border-border-subtle">
      <nav class="-mb-px flex gap-6" aria-label="<%= t("maint_platform.module_settings.show.tabs.nav_label") %>">
        <a href="#" data-tabs-target="tab" data-tabs-id="settings" data-action="tabs#select"
           class="whitespace-nowrap border-b-2 border-indigo-500 px-1 py-3 text-sm font-medium text-indigo-600">
          <%= t("maint_platform.module_settings.show.tabs.settings") %>
        </a>
        <a href="#" data-tabs-target="tab" data-tabs-id="technical" data-action="tabs#select"
           class="whitespace-nowrap border-b-2 border-transparent px-1 py-3 text-sm font-medium text-gray-500">
          <%= t("maint_platform.module_settings.show.tabs.technical") %>
        </a>
      </nav>
    </div>

    <div data-tabs-target="panel" data-tabs-id="settings" class="pt-6 space-y-6">
      <%# Module-Specific Configuration (SMS) %>
      <% if @feature_module.key == "sms" %>
        <div class="card overflow-hidden">
          <div class="px-6 py-4 border-b border-border-subtle">
            <h2 class="section-header"><%= t("maint_platform.module_settings.show.sms.title") %></h2>
            <p class="mt-0.5 text-caption"><%= t("maint_platform.module_settings.show.sms.subtitle") %></p>
          </div>
          <ul class="divide-y divide-border-subtle">
            <li class="hover:bg-canvas-elevated transition-colors">
              <%= link_to admin_maintenance_platform_module_settings_sms_credentials_path(current_customer_id), class: "flex items-center justify-between gap-4 px-6 py-4" do %>
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-lg bg-surface-active flex items-center justify-center">
                    <svg class="w-4 h-4 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.75">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/>
                    </svg>
                  </div>
                  <div>
                    <h3 class="text-body text-text-primary font-medium"><%= t("maint_platform.module_settings.show.sms.credentials") %></h3>
                    <p class="text-caption"><%= t("maint_platform.module_settings.show.sms.credentials_desc") %></p>
                  </div>
                </div>
                <svg class="w-5 h-5 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/>
                </svg>
              <% end %>
            </li>
            <li class="hover:bg-canvas-elevated transition-colors">
              <%= link_to admin_maintenance_platform_module_settings_sms_templates_path(current_customer_id), class: "flex items-center justify-between gap-4 px-6 py-4" do %>
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-lg bg-surface-active flex items-center justify-center">
                    <svg class="w-4 h-4 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.75">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6z"/>
                    </svg>
                  </div>
                  <div>
                    <h3 class="text-body text-text-primary font-medium"><%= t("maint_platform.module_settings.show.sms.templates") %></h3>
                    <p class="text-caption"><%= t("maint_platform.module_settings.show.sms.templates_desc") %></p>
                  </div>
                </div>
                <svg class="w-5 h-5 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/>
                </svg>
              <% end %>
            </li>
          </ul>
        </div>
      <% end %>

      <%# Module-Specific Configuration (Email) %>
      <% if @feature_module.key == "email" %>
        <div class="card overflow-hidden">
          <div class="px-6 py-4 border-b border-border-subtle">
            <h2 class="section-header"><%= t("maint_platform.module_settings.show.email.title") %></h2>
            <p class="mt-0.5 text-caption"><%= t("maint_platform.module_settings.show.email.subtitle") %></p>
          </div>
          <ul class="divide-y divide-border-subtle">
            <li class="hover:bg-canvas-elevated transition-colors">
              <%= link_to admin_maintenance_platform_module_settings_emails_credentials_path(current_customer_id), class: "flex items-center justify-between gap-4 px-6 py-4" do %>
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-lg bg-surface-active flex items-center justify-center">
                    <svg class="w-4 h-4 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.75">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/>
                    </svg>
                  </div>
                  <div>
                    <h3 class="text-body text-text-primary font-medium"><%= t("maint_platform.module_settings.show.email.credentials") %></h3>
                    <p class="text-caption"><%= t("maint_platform.module_settings.show.email.credentials_desc") %></p>
                  </div>
                </div>
                <svg class="w-5 h-5 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/>
                </svg>
              <% end %>
            </li>
          </ul>
        </div>
      <% end %>

      <%# Module-Specific Configuration (Payment Tenders) %>
      <% if @feature_module.key == "payment" %>
        <div class="card overflow-hidden">
          <div class="px-6 py-4 border-b border-border-subtle">
            <h2 class="section-header"><%= t("maint_platform.module_settings.show.payment.title") %></h2>
            <p class="mt-0.5 text-caption"><%= t("maint_platform.module_settings.show.payment.subtitle") %></p>
          </div>
          <ul class="divide-y divide-border-subtle">
            <% @platform_gateways.each do |gw, pg| %>
              <li class="flex items-center justify-between gap-4 px-6 py-4">
                <div>
                  <h3 class="text-body text-text-primary font-medium"><%= gw.display_name %></h3>
                  <p class="text-caption"><%= gw.key %></p>
                </div>
                <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
                      url: admin_maintenance_platform_module_settings_payments_platform_gateway_path(current_customer_id, gw.key),
                      field: "available",
                      on: pg.available?,
                      on_label: t("maint_platform.module_settings.show.payment.available"), off_label: t("maint_platform.module_settings.show.payment.unavailable")
                    ) %>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <%# Configuration Schema Card — type-aware default inputs %>
      <% if schema.any? %>
        <div class="card overflow-hidden">
          <div class="px-6 py-4 border-b border-border-subtle">
            <h2 class="section-header"><%= t("maint_platform.module_settings.show.schema.title") %></h2>
            <p class="mt-0.5 text-caption"><%= t("maint_platform.module_settings.show.schema.subtitle") %></p>
          </div>
          <%= form_with url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module), method: :patch, local: true do %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-border-subtle">
                <thead class="table-header">
                  <tr>
                    <th class="px-6 py-3 text-left text-label"><%= t("maint_platform.module_settings.show.schema.setting") %></th>
                    <th class="px-6 py-3 text-left text-label"><%= t("common.labels.type") %></th>
                    <th class="px-6 py-3 text-left text-label"><%= t("maint_platform.module_settings.show.schema.default") %></th>
                    <th class="px-6 py-3 text-left text-label"><%= t("common.labels.description") %></th>
                  </tr>
                </thead>
                <tbody class="bg-surface divide-y divide-border-subtle">
                  <% schema.each do |key, schema_def| %>
                    <% field_name = "config_defaults[#{key}]" %>
                    <tr class="table-row">
                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class="text-body text-text-primary font-medium"><%= key.humanize %></span>
                        <% if schema_def["required"] %>
                          <span class="ml-1 text-danger">*</span>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <%= render BadgeComponent.new(variant: :info, size: :sm) do %><%= schema_def["type"] %><% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <% case schema_def["type"] %>
                        <% when "boolean" %>
                          <%= hidden_field_tag field_name, "0", id: nil %>
                          <label class="inline-flex items-center cursor-pointer">
                            <%= check_box_tag field_name, "1", ActiveModel::Type::Boolean.new.cast(schema_def["default"]), class: "sr-only peer" %>
                            <span class="relative inline-flex h-6 w-11 flex-shrink-0 rounded-full border-2 border-transparent bg-border peer-checked:bg-accent transition-colors duration-200 ease-in-out">
                              <span class="pointer-events-none inline-block h-5 w-5 translate-x-0 peer-checked:translate-x-5 transform rounded-full bg-surface shadow ring-0 transition duration-200 ease-in-out"></span>
                            </span>
                          </label>
                        <% when "number", "integer" %>
                          <%= number_field_tag field_name, schema_def["default"], class: "input-field" %>
                        <% else %>
                          <%= text_field_tag field_name, schema_def["default"], class: "input-field" %>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 text-body-sm"><%= schema_def["description"] %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
            <div class="px-6 py-4 border-t border-border-subtle bg-surface-subtle">
              <%= render ButtonComponent.new(variant: :primary, size: :md, tag: :button, type: :submit) do %>
                <%= t("maint_platform.module_settings.show.schema.save_defaults") %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <% unless settings_tab_has_content %>
        <div class="card p-12 text-center">
          <p class="text-body-sm italic"><%= t("maint_platform.module_settings.show.tabs.no_settings") %></p>
        </div>
      <% end %>
    </div>

    <div data-tabs-target="panel" data-tabs-id="technical" class="pt-6 space-y-6 hidden">
      <%# Models Card %>
      <div class="card overflow-hidden">
        <div class="px-6 py-4 border-b border-border-subtle">
          <div class="flex items-center justify-between">
            <h2 class="section-header"><%= t("maint_platform.module_settings.show.models.title") %></h2>
            <span class="text-caption"><%= t("maint_platform.module_settings.show.models.count", count: @module_models.size) %></span>
          </div>
        </div>
        <% if @module_models.any? %>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-border-subtle">
              <thead class="table-header">
                <tr>
                  <th class="px-6 py-3 text-left text-label"><%= t("maint_platform.module_settings.show.models.class") %></th>
                  <th class="px-6 py-3 text-left text-label"><%= t("maint_platform.module_settings.show.models.table_name") %></th>
                  <th class="px-6 py-3 text-center text-label"><%= t("maint_platform.module_settings.show.models.columns") %></th>
                  <th class="px-6 py-3 text-center text-label"><%= t("maint_platform.module_settings.show.models.associations") %></th>
                  <th class="px-6 py-3 text-center text-label"><%= t("maint_platform.module_settings.show.models.extendable") %></th>
                </tr>
              </thead>
              <tbody class="bg-surface divide-y divide-border-subtle">
                <% @module_models.each do |model| %>
                  <tr class="table-row">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class="text-mono text-sm text-text-primary"><%= model[:name] %></span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class="text-mono text-sm bg-surface-active px-1.5 py-0.5 rounded"><%= model[:table_name] %></span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-center text-body-sm">
                      <%= model[:columns_count] %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-center text-body-sm">
                      <%= model[:associations_count] %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-center">
                      <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
                            url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module),
                            field: "extendable",
                            on: @feature_module.extendable_model?(model[:name]),
                            on_label: t("maint_platform.module_settings.show.models.allowed"), off_label: t("maint_platform.module_settings.show.models.not_allowed"),
                            extra_params: { extendable_model: model[:name] }
                          ) %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% else %>
          <div class="p-6 text-center">
            <p class="text-body-sm italic"><%= t("maint_platform.module_settings.show.models.empty") %></p>
          </div>
        <% end %>
      </div>

      <%# Routes Card %>
      <div class="card overflow-hidden">
        <div class="px-6 py-4 border-b border-border-subtle">
          <div class="flex items-center justify-between">
            <h2 class="section-header"><%= t("maint_platform.module_settings.show.routes.title") %></h2>
            <span class="text-caption"><%= t("maint_platform.module_settings.show.routes.count", count: @module_routes.size) %></span>
          </div>
        </div>
        <% if @module_routes.any? %>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-border-subtle">
              <thead class="table-header">
                <tr>
                  <th class="px-6 py-3 text-left text-label w-24"><%= t("maint_platform.module_settings.show.routes.method") %></th>
                  <th class="px-6 py-3 text-left text-label"><%= t("maint_platform.module_settings.show.routes.path") %></th>
                  <th class="px-6 py-3 text-left text-label"><%= t("maint_platform.module_settings.show.routes.action") %></th>
                </tr>
              </thead>
              <tbody class="bg-surface divide-y divide-border-subtle">
                <% @module_routes.each do |route| %>
                  <tr class="table-row">
                    <td class="px-6 py-3 whitespace-nowrap">
                      <%
                        method_variant = case route[:method]
                        when "GET"          then :success
                        when "POST"         then :info
                        when "PATCH", "PUT" then :warning
                        when "DELETE"       then :danger
                        else                     :default
                        end
                      %>
                      <%= render BadgeComponent.new(variant: method_variant, size: :sm) do %><%= route[:method] %><% end %>
                    </td>
                    <td class="px-6 py-3">
                      <span class="text-mono text-xs text-text-primary"><%= route[:path] %></span>
                    </td>
                    <td class="px-6 py-3">
                      <span class="text-mono text-xs text-text-muted"><%= route[:controller_action] %></span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% else %>
          <div class="p-6 text-center">
            <p class="text-body-sm italic"><%= t("maint_platform.module_settings.show.routes.empty") %></p>
          </div>
        <% end %>
      </div>

      <%# Integration Contract (Handoff) Card %>
      <%= render Admin::Maintenance::Platform::ModuleHandoffComponent.new(feature_module: @feature_module) %>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Confirm the file compiles by loading the page**

Run: `bin/rails runner "puts ActionView::Base.new(ActionView::LookupContext.new(ActionController::Base.view_paths), {}, nil).render(template: 'admin/maintenance/platform/module_settings/show') rescue puts $!.class" 2>&1 | tail -5`

This is a syntax sanity check only — full behavioral verification happens via the request spec in Task 6 (ERB template errors surface as `ActionView::Template::Error` / `SyntaxError` at render time, not at this point, so treat any Ruby `SyntaxError` here as a real failure; other errors are expected since instance variables aren't set — that's fine, we only care that ERB parses).

Simpler and more reliable: just run the Task 6 request specs after this step (they exercise this template through the real controller with real instance variables) rather than trying to isolate ERB syntax checking.

---

## Task 3: Index page — stats strip + key pill

**Files:**
- Modify: `app/views/admin/maintenance/platform/module_settings/index.html.erb`

- [ ] **Step 1: Replace the file contents**

```erb
<%# app/views/platform/module_settings/index.html.erb %>
<% total_count    = @available_modules.size %>
<% active_count   = @available_modules.count(&:active?) %>
<% required_count = @available_modules.count(&:required?) %>
<%= render AdminPageComponent.new(
  breadcrumbs: [
    { label: t("maint_platform.module_settings.breadcrumbs.maintenance"), path: admin_maintenance_path(current_customer_id) },
    { label: t("maint_platform.module_settings.breadcrumbs.module_settings") }
  ],
  title: t("maint_platform.module_settings.index.title"),
  description: t("maint_platform.module_settings.index.description")
) do %>
  <% if @available_modules.any? %>
    <div class="mb-4 text-caption">
      <%= t("maint_platform.module_settings.index.stats_summary", total: total_count, active: active_count, required: required_count) %>
    </div>
  <% end %>

  <div class="card overflow-hidden">
  <div class="px-6 py-4 border-b border-border-subtle">
    <div class="flex items-center gap-2">
      <svg class="w-5 h-5 text-warning" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
      </svg>
      <span class="section-header"><%= t("maint_platform.module_settings.index.owner_access") %></span>
    </div>
    <p class="mt-1 text-caption"><%= t("maint_platform.module_settings.index.owner_access_hint") %></p>
  </div>

  <% if @available_modules.any? %>
    <ul class="divide-y divide-border-subtle">
      <% @available_modules.each do |fm| %>
        <li class="hover:bg-canvas-elevated transition-colors">
          <%= link_to admin_maintenance_platform_module_setting_path(current_customer_id, fm),
                class: "block px-6 py-4" do %>
            <div class="flex items-center justify-between gap-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <h3 class="text-body text-text-primary font-medium truncate"><%= fm.display_name %></h3>
                  <% if fm.required? %>
                    <%= render BadgeComponent.new(variant: :warning, size: :sm) do %><%= t("common.labels.required") %><% end %>
                  <% end %>
                  <% if fm.active? %>
                    <%= render BadgeComponent.new(variant: :success, size: :sm) do %><%= t("common.status.active") %><% end %>
                  <% else %>
                    <%= render BadgeComponent.new(variant: :default, size: :sm) do %><%= t("common.status.inactive") %><% end %>
                  <% end %>
                </div>
                <p class="mt-0.5 text-caption line-clamp-1"><%= fm.description %></p>
                <div class="mt-1.5 flex items-center gap-3 text-caption">
                  <span class="text-mono text-xs bg-surface-active px-1.5 py-0.5 rounded"><%= fm.key %></span>
                </div>
              </div>
              <svg class="w-5 h-5 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
              </svg>
            </div>
          <% end %>
        </li>
      <% end %>
    </ul>
  <% else %>
    <div class="p-12 text-center">
      <div class="w-12 h-12 rounded-full bg-surface-active flex items-center justify-center mx-auto mb-3">
        <svg class="w-6 h-6 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
        </svg>
      </div>
      <p class="text-body-sm"><%= t("maint_platform.module_settings.index.empty") %></p>
    </div>
  <% end %>
  </div>
<% end %>
```

---

## Task 4: Email credential form — design-token fixes

**Files:**
- Modify: `app/components/admin/maintenance/platform/emails/credential_form_component.html.erb`

- [ ] **Step 1: Replace the two `<legend>` tags' classes**

Find (appears twice, for `smtp_legend` and `dkim_legend`):
```erb
      <legend class="text-sm font-semibold text-gray-700 uppercase tracking-wide pb-1 border-b border-gray-200 w-full"><%= t("maint_platform.emails.credentials.form.smtp_legend") %></legend>
```
```erb
      <legend class="text-sm font-semibold text-gray-700 uppercase tracking-wide pb-1 border-b border-gray-200 w-full"><%= t("maint_platform.emails.credentials.form.dkim_legend") %></legend>
```

Replace both with the `text-label` design token (drop the now-redundant manual size/weight/uppercase/tracking/color utilities it already provides):
```erb
      <legend class="text-label pb-1 border-b border-border-subtle w-full"><%= t("maint_platform.emails.credentials.form.smtp_legend") %></legend>
```
```erb
      <legend class="text-label pb-1 border-b border-border-subtle w-full"><%= t("maint_platform.emails.credentials.form.dkim_legend") %></legend>
```

- [ ] **Step 2: Replace the three hardcoded checkbox classes**

Find (appears for `enable_starttls`, `ssl`, `dkim_enabled`):
```erb
            <%= f.check_box :enable_starttls, class: "h-4 w-4 rounded border-gray-300 text-blue-600" %>
```
```erb
            <%= f.check_box :ssl, class: "h-4 w-4 rounded border-gray-300 text-blue-600" %>
```
```erb
      <%= f.check_box :dkim_enabled, class: "h-4 w-4 rounded border-gray-300 text-blue-600" %>
```

Replace with the design-token classes already established elsewhere in the app (e.g. `billing/admin/coupon_form_component.html.erb`):
```erb
            <%= f.check_box :enable_starttls, class: "h-4 w-4 rounded border-border-subtle text-accent focus:ring-accent" %>
```
```erb
            <%= f.check_box :ssl, class: "h-4 w-4 rounded border-border-subtle text-accent focus:ring-accent" %>
```
```erb
      <%= f.check_box :dkim_enabled, class: "h-4 w-4 rounded border-border-subtle text-accent focus:ring-accent" %>
```

- [ ] **Step 3: Replace the hand-rolled DNS TXT hint box classes**

Find:
```erb
      <% if (dns_hint = credential.dkim_dns_txt_record) %>
        <div class="rounded-md bg-blue-50 border border-blue-200 p-4 space-y-2">
          <p class="text-sm font-medium text-blue-800"><%= t("maint_platform.emails.credentials.form.dns_txt_hint") %></p>
          <pre class="text-xs font-mono text-blue-900 break-all whitespace-pre-wrap"><%= dns_hint %></pre>
        </div>
      <% end %>
```

Replace with the same semantic tokens `AlertComponent` uses internally for `type: :info` (this box isn't an `AlertComponent` — it needs a multi-line `<pre>` block, which that component's single-line layout doesn't support — but it should use the identical color tokens for visual consistency):
```erb
      <% if (dns_hint = credential.dkim_dns_txt_record) %>
        <div class="rounded-lg bg-info-subtle border border-info/20 p-4 space-y-2">
          <p class="text-sm font-medium text-info"><%= t("maint_platform.emails.credentials.form.dns_txt_hint") %></p>
          <pre class="text-xs font-mono text-text-primary break-all whitespace-pre-wrap"><%= dns_hint %></pre>
        </div>
      <% end %>
```

- [ ] **Step 4: Run the component spec to confirm no regressions**

Run: `bundle exec rspec spec/components/admin/maintenance/platform/emails/credential_form_component_spec.rb`
Expected: all examples pass (none of them assert on the specific classes changed, only on field names/values/text — verified during planning).

---

## Task 5: SMS credential form — fieldset grouping

**Files:**
- Modify: `app/components/admin/maintenance/platform/sms/credential_form_component.html.erb`

- [ ] **Step 1: Wrap the per-adapter config-field groups in a `<fieldset>`/`<legend>`**

Find:
```erb
  <% adapters.each do |adapter| %>
    <div data-sms-credential-form-target="fields" data-provider="<%= adapter.key %>"
         class="grid grid-cols-1 gap-4 md:grid-cols-2 <%= "hidden" unless adapter.key.to_s == selected_provider %>">
      <% adapter.config_fields.each do |field| %>
        <div>
          <label class="form-label" for="<%= config_field_id(field) %>"><%= field_label(adapter, field) %></label>
          <% if field[:type] == :password %>
            <%# Never echo the stored secret into HTML — render blank with a
                dot-mask placeholder, mirroring the access_key_secret field.
                A blank submit is treated as "keep existing" by the writer. %>
            <%= password_field_tag config_field_name(field), "",
                  id: config_field_id(field), class: "input-field mt-1", autocomplete: "new-password",
                  placeholder: credential.config_value(field[:name]).present? ? "••••••••" : nil %>
          <% else %>
            <%= text_field_tag config_field_name(field), credential.config_value(field[:name]),
                  id: config_field_id(field), class: "input-field mt-1" %>
          <% end %>
        </div>
      <% end %>
    </div>
  <% end %>
```

Replace with (adds a `<fieldset>`/`<legend>` wrapper per provider, matching the Email form's grouping pattern — the inner `div` keeps its exact `data-sms-credential-form-target`/`data-provider` attributes and `hidden`-toggling class list unchanged, since those are what the Stimulus controller and existing specs target):
```erb
  <% adapters.each do |adapter| %>
    <fieldset data-sms-credential-form-target="fields" data-provider="<%= adapter.key %>"
         class="<%= "hidden" unless adapter.key.to_s == selected_provider %>">
      <legend class="text-label pb-1 border-b border-border-subtle w-full">
        <%= t("maint_platform.sms.credentials.form.provider_fields_legend", provider: adapter.display_name) %>
      </legend>
      <div class="grid grid-cols-1 gap-4 md:grid-cols-2 mt-4">
        <% adapter.config_fields.each do |field| %>
          <div>
            <label class="form-label" for="<%= config_field_id(field) %>"><%= field_label(adapter, field) %></label>
            <% if field[:type] == :password %>
              <%# Never echo the stored secret into HTML — render blank with a
                  dot-mask placeholder, mirroring the access_key_secret field.
                  A blank submit is treated as "keep existing" by the writer. %>
              <%= password_field_tag config_field_name(field), "",
                    id: config_field_id(field), class: "input-field mt-1", autocomplete: "new-password",
                    placeholder: credential.config_value(field[:name]).present? ? "••••••••" : nil %>
            <% else %>
              <%= text_field_tag config_field_name(field), credential.config_value(field[:name]),
                    id: config_field_id(field), class: "input-field mt-1" %>
            <% end %>
          </div>
        <% end %>
      </div>
    </fieldset>
  <% end %>
```

- [ ] **Step 2: Run the component spec to confirm no regressions**

Run: `bundle exec rspec spec/components/admin/maintenance/platform/sms/credential_form_component_spec.rb`
Expected: all examples pass. The spec locates groups via `page.find("[data-provider='...']", visible: :all)` and checks `[:class]` for `"hidden"` — both the attribute and the class list are preserved on the (now `<fieldset>`) element, so no spec changes are needed.

---

## Task 6: Spec coverage for the new markup

**Files:**
- Modify: `spec/requests/admin/maintenance/platform/module_settings_spec.rb`

- [ ] **Step 1: Add tab/controls structural assertions to the existing `GET /show` block**

Find:
```ruby
    describe "GET /show" do
      it "returns 200 with module details" do
        get show_path
        expect(response).to have_http_status(:ok)
      end

      it "renders the Integration Contract section (empty state for a contract-less module)" do
        get show_path
        expect(response.body).to include("Integration Contract")
      end
```

Add two new examples right after the "Integration Contract" one (still inside `describe "GET /show" do`):
```ruby
      it "renders the two-tab layout (Settings default, Technical Reference)" do
        get show_path
        expect(response.body).to include('data-controller="tabs"')
        expect(response.body).to include('data-tabs-id="settings"')
        expect(response.body).to include('data-tabs-id="technical"')
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.tabs.settings"))
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.tabs.technical"))
      end

      it "renders the consolidated Module Controls panel" do
        get show_path
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.controls_title"))
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.module_status"))
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.required_module"))
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.handoff_target"))
      end
```

- [ ] **Step 2: Add a boolean-schema round-trip assertion to the mandatory-module context**

Find (inside `describe "PATCH /update — a mandatory module"`):
```ruby
      it "still lets the platform owner edit its config defaults" do
        auth = FeatureModules::Module.find_by(key: "authentication")
        skip "authentication module not seeded" unless auth

        auth.update!(configuration_schema: { "mfa_enabled" => { "type" => "boolean", "default" => false } }.to_json)
        patch admin_maintenance_platform_module_setting_path(platform_customer.id, auth),
              params: { config_defaults: { mfa_enabled: "true" } }

        expect(auth.reload.configuration_schema_json["mfa_enabled"]["default"]).to eq("true")
      end
```

Add a new example right after it (same `describe` block) that renders the actual show page and verifies the boolean field renders as a checkbox with a preceding hidden `"0"` field (so unchecking submits `"0"`, not omitting the key):
```ruby
      it "renders the boolean schema default as a checkbox with an unchecked fallback" do
        auth = FeatureModules::Module.find_by(key: "authentication")
        skip "authentication module not seeded" unless auth

        auth.update!(configuration_schema: { "mfa_enabled" => { "type" => "boolean", "default" => false, "description" => "x" } }.to_json)
        get admin_maintenance_platform_module_setting_path(platform_customer.id, auth)

        expect(response.body).to match(/<input[^>]*type="hidden"[^>]*name="config_defaults\[mfa_enabled\]"[^>]*value="0"/)
        expect(response.body).to match(/<input[^>]*type="checkbox"[^>]*name="config_defaults\[mfa_enabled\]"[^>]*value="1"/)
      end
```

- [ ] **Step 3: Add an index stats-strip assertion**

Find:
```ruby
    describe "GET /index" do
      it "returns 200 and lists all modules (including inactive)" do
        get index_path
        expect(response).to have_http_status(:ok)
      end
    end
```

Replace with:
```ruby
    describe "GET /index" do
      it "returns 200 and lists all modules (including inactive)" do
        get index_path
        expect(response).to have_http_status(:ok)
      end

      it "renders the stats summary with correct counts" do
        get index_path
        modules = FeatureModules::Module.by_name.to_a
        expected = I18n.t("maint_platform.module_settings.index.stats_summary",
                           total: modules.size, active: modules.count(&:active?), required: modules.count(&:required?))
        expect(response.body).to include(expected)
      end
    end
```

- [ ] **Step 4: Run the full request spec file**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`
Expected: all examples pass (0 failures).

---

## Task 7: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Run all specs touched by this plan**

Run:
```bash
bundle exec rspec \
  spec/requests/admin/maintenance/platform/module_settings_spec.rb \
  spec/components/admin/maintenance/platform/emails/credential_form_component_spec.rb \
  spec/components/admin/maintenance/platform/sms/credential_form_component_spec.rb
```
Expected: 0 failures.

- [ ] **Step 2: Rebuild assets and restart the dev server**

Run:
```bash
rm -f public/assets/.manifest.json
SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &
```

- [ ] **Step 3: Manually verify in-browser**

Visit `/81721200/admin/maintenance/platform/module_settings`:
- Confirm the stats strip shows correct total/active/required counts.
- Open a module (e.g. `sms` or `authentication`) and confirm: header shows name/badges/key/version compactly (no separate "Module Information" card); "Module Controls" card shows 3 rows with working toggles; clicking "Technical Reference" switches tabs and shows Models/Routes/Integration Contract; clicking back to "Settings" restores the schema form / module links.
- For the `authentication` module, confirm the `mfa_enabled` row renders as a toggle-style checkbox (not a text box), and `session_timeout`/`max_login_attempts` render as number inputs. Toggle `mfa_enabled` off, click "Save Defaults", and confirm the value persists as unchecked on reload.
- Visit the Email and SMS platform credential forms and confirm the legend/checkbox/DNS-hint styling now uses the app's neutral/accent palette instead of raw gray/blue.

- [ ] **Step 4: Stop the dev server**

Run: `kill %1` (or find and kill the `rails server` process started in Step 2).
