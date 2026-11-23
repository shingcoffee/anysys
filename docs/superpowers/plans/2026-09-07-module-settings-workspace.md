# Platform Module Settings Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the platform module-settings catalog and all nested module settings pages with one consistent, responsive, localized workspace while preserving existing behavior and routes.

**Architecture:** Introduce shared ViewComponents for the workspace shell, navigation, summaries, section cards, setting rows, form actions, and responsive collections. Migrate existing module-specific components onto those primitives in vertical slices, keeping controllers and persistence behavior unchanged and using Stimulus only where existing client-side behavior needs refinement.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, TailwindCSS, StimulusJS, I18n, RSpec, Vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-07-module-settings-workspace-design.md`

## Global Constraints

- Existing routes, controller authorization, persistence, provider discovery, tenant behavior, and business logic must remain unchanged.
- Only the fixed platform owner under customer `81721200` may access these surfaces.
- Use ViewComponent for rendered UI, Tailwind utilities for styling, and Stimulus for JavaScript behavior.
- Do not add custom CSS, another CSS framework, custom JavaScript outside Stimulus, or another JavaScript framework.
- Every new or changed displayed string must use I18n with matching `en` and `zh-CN` keys and interpolation variables.
- English translations must preserve existing wording byte-for-byte when existing specs depend on that wording.
- Every changed JavaScript file must retain 100% Vitest line and branch coverage.
- Use TDD: add or change a test, observe the expected failure, then implement the minimum production change.
- Do not change files under `app/services/page_layout_templates/templates/`.
- Do not commit; the human reviewer will commit manually.

---

### Task 1: Shared module-settings workspace primitives

**Files:**
- Create: `app/components/admin/maintenance/platform/module_settings/shell_component.rb`
- Create: `app/components/admin/maintenance/platform/module_settings/shell_component.html.erb`
- Create: `app/components/admin/maintenance/platform/module_settings/summary_component.rb`
- Create: `app/components/admin/maintenance/platform/module_settings/summary_component.html.erb`
- Create: `app/components/admin/maintenance/platform/module_settings/section_card_component.rb`
- Create: `app/components/admin/maintenance/platform/module_settings/section_card_component.html.erb`
- Create: `app/components/admin/maintenance/platform/module_settings/setting_row_component.rb`
- Create: `app/components/admin/maintenance/platform/module_settings/setting_row_component.html.erb`
- Create: `app/components/admin/maintenance/platform/module_settings/form_actions_component.rb`
- Create: `app/components/admin/maintenance/platform/module_settings/form_actions_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/module_settings/nav_component.rb`
- Modify: `app/components/admin/maintenance/platform/module_settings/nav_component.html.erb`
- Modify: `config/locales/maint_platform.en.yml`
- Modify: `config/locales/maint_platform.zh-CN.yml`
- Create: `spec/components/admin/maintenance/platform/module_settings/shell_component_spec.rb`
- Create: `spec/components/admin/maintenance/platform/module_settings/summary_component_spec.rb`
- Create: `spec/components/admin/maintenance/platform/module_settings/section_card_component_spec.rb`
- Create: `spec/components/admin/maintenance/platform/module_settings/setting_row_component_spec.rb`
- Create: `spec/components/admin/maintenance/platform/module_settings/form_actions_component_spec.rb`
- Modify: `spec/components/admin/maintenance/platform/module_settings/nav_component_spec.rb`

**Interfaces:**
- Produces: `ShellComponent.new(feature_module:, customer_id:, current:, health: nil, primary_action: nil)`
- Produces: shell content slot for every overview and nested module page.
- Produces: stable nav IDs `overview`, `configuration`, `providers`, `resources`, `operations`, and `developer`.
- Produces: `SummaryComponent.new(items:, warnings: [])`, where each item has `label`, `value`, and optional `status`.
- Produces: `SectionCardComponent.new(title:, description: nil, action: nil)`.
- Produces: `SettingRowComponent.new(label:, description: nil, state: nil, disabled_reason: nil)`.
- Produces: `FormActionsComponent.new(cancel_path:, submit_label:, sticky: false)`.

- [ ] **Step 1: Write failing component specs**

Add examples asserting that the shell renders breadcrumbs, module identity,
scope messaging, semantic health/status text, and the active navigation item;
that irrelevant navigation items are absent; and that each primitive renders
its slots and accessibility attributes.

```ruby
expect(page).to have_css("[data-module-settings-shell='true']")
expect(page).to have_css("[aria-current='page']", text: I18n.t("maint_platform.module_settings.show.nav.providers"))
expect(page).to have_text(I18n.t("maint_platform.module_settings.workspace.platform_scope"))
```

- [ ] **Step 2: Run the primitive specs and verify RED**

Run:

```bash
bundle exec rspec \
  spec/components/admin/maintenance/platform/module_settings/shell_component_spec.rb \
  spec/components/admin/maintenance/platform/module_settings/summary_component_spec.rb \
  spec/components/admin/maintenance/platform/module_settings/section_card_component_spec.rb \
  spec/components/admin/maintenance/platform/module_settings/setting_row_component_spec.rb \
  spec/components/admin/maintenance/platform/module_settings/form_actions_component_spec.rb \
  spec/components/admin/maintenance/platform/module_settings/nav_component_spec.rb
```

Expected: failures because the shared components and new navigation model do
not exist.

- [ ] **Step 3: Implement the shared components**

Use restrained shadcn-inspired composition translated to project conventions:
semantic cards, badges, alerts, separators, field-like rows, and accessible
navigation. Keep layout classes inside component templates and expose content
through slots rather than module-specific conditionals.

The navigation mapping must retain existing route helpers:

```ruby
SECTION_IDS = {
  "authentication" => %i[overview configuration developer],
  "captcha" => %i[overview providers resources developer],
  "email" => %i[overview providers developer],
  "payment" => %i[overview providers operations developer],
  "sms" => %i[overview providers resources developer],
  "speech_to_text" => %i[overview providers developer]
}.freeze
```

Translate stable navigation labels under
`maint_platform.module_settings.show.nav` and workspace copy under
`maint_platform.module_settings.workspace`, preserving en/zh-CN parity.

- [ ] **Step 4: Run the primitive specs and verify GREEN**

Run the command from Step 2. Expected: all examples pass with no warnings.

- [ ] **Step 5: Run locale parity and formatting checks**

Run:

```bash
bundle exec ruby -e 'require "yaml"; en=YAML.load_file("config/locales/maint_platform.en.yml"); zh=YAML.load_file("config/locales/maint_platform.zh-CN.yml"); abort "locale roots missing" unless en["en"] && zh["zh-CN"]'
git diff --check
```

Expected: exit 0.

### Task 2: Catalog and common module overview

**Files:**
- Modify: `app/components/admin/maintenance/platform/module_catalog_component.rb`
- Modify: `app/components/admin/maintenance/platform/module_catalog_component.html.erb`
- Modify: `app/views/admin/maintenance/platform/module_settings/index.html.erb`
- Modify: `app/views/admin/maintenance/platform/module_settings/show.html.erb`
- Modify: `app/components/admin/maintenance/platform/module_settings/show_component.rb`
- Modify: `app/components/admin/maintenance/platform/module_settings/show_component.html.erb`
- Modify: `config/locales/maint_platform.en.yml`
- Modify: `config/locales/maint_platform.zh-CN.yml`
- Modify: `spec/components/admin/maintenance/platform/module_catalog_component_spec.rb`
- Modify: `spec/components/admin/maintenance/platform/module_settings/show_component_spec.rb`
- Modify: `spec/e2e/module_settings_layout.app.spec.js`

**Interfaces:**
- Consumes: all Task 1 shared components.
- Produces: catalog cards with configuration health and predictable Configure actions.
- Produces: overview/configuration/developer panes rendered inside `ShellComponent`.

- [ ] **Step 1: Write failing catalog and overview specs**

Assert that every module entry has status, health/assignment context where
available, and a Configure link; the overview presents availability before
module-specific settings; and developer metadata is absent from routine panes.

```ruby
expect(page).to have_css("[data-module-card]", count: modules.count)
expect(page).to have_link(I18n.t("maint_platform.module_settings.index.configure"))
expect(page).to have_css("[data-module-settings-section='availability']")
expect(page).not_to have_css("[data-developer-reference]", visible: true)
```

Update the E2E expectations for desktop and mobile workspace geometry and
active navigation.

- [ ] **Step 2: Run tests and verify RED**

```bash
bundle exec rspec \
  spec/components/admin/maintenance/platform/module_catalog_component_spec.rb \
  spec/components/admin/maintenance/platform/module_settings/show_component_spec.rb
```

Expected: failures for missing workspace/card structure.

- [ ] **Step 3: Implement catalog and overview migration**

Render module settings through `ShellComponent`. Reorganize common content:

- Overview: summary, availability, requirement state, and next actions.
- Configuration: Authentication signup and schema-backed defaults.
- Developer: handoff, models, tokens, extendability, and technical schema.

Keep all existing form URLs, parameter names, confirmations, and update
behavior. Replace large mixed blocks with `SectionCardComponent` and
`SettingRowComponent`.

- [ ] **Step 4: Run component specs and verify GREEN**

Run the Step 2 command. Expected: all pass.

- [ ] **Step 5: Run the targeted layout browser spec**

```bash
npx playwright test spec/e2e/module_settings_layout.app.spec.js
```

Expected: desktop and mobile assertions pass.

### Task 3: Unified provider and credential workspaces

**Files:**
- Create: `app/components/admin/maintenance/platform/module_settings/provider_workspace_component.rb`
- Create: `app/components/admin/maintenance/platform/module_settings/provider_workspace_component.html.erb`
- Create: `app/components/admin/maintenance/platform/module_settings/credential_panel_component.rb`
- Create: `app/components/admin/maintenance/platform/module_settings/credential_panel_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/emails/settings_component.rb`
- Modify: `app/components/admin/maintenance/platform/emails/settings_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/emails/credential_form_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/sms/settings_component.rb`
- Modify: `app/components/admin/maintenance/platform/sms/settings_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/sms/credential_form_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/captcha/settings_component.rb`
- Modify: `app/components/admin/maintenance/platform/captcha/settings_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/speech_to_text/settings_component.rb`
- Modify: `app/components/admin/maintenance/platform/speech_to_text/settings_component.html.erb`
- Modify: nested Email, SMS, Captcha, and Speech-to-Text view files under `app/views/admin/maintenance/platform/`
- Modify: `config/locales/maint_platform.en.yml`
- Modify: `config/locales/maint_platform.zh-CN.yml`
- Create: `spec/components/admin/maintenance/platform/module_settings/provider_workspace_component_spec.rb`
- Create: `spec/components/admin/maintenance/platform/module_settings/credential_panel_component_spec.rb`
- Modify: provider component and credential-form specs under `spec/components/admin/maintenance/platform/`

**Interfaces:**
- Consumes: `ShellComponent`, `SectionCardComponent`, `SettingRowComponent`, and `FormActionsComponent`.
- Produces: assignment → provider → health/test → credentials → advanced-options flow.
- Preserves: existing form objects, URLs, secret-preservation behavior, and connection-test endpoints.

- [ ] **Step 1: Write failing shared-provider specs**

Cover configured, incomplete, inactive, connection-failure, create, and edit
states. Assert that secret fields do not expose stored values and that
connection tests are adjacent to health information.

```ruby
expect(page).to have_css("[data-provider-workspace='true']")
expect(page).to have_text(I18n.t("maint_platform.module_settings.workspace.provider_health"))
expect(page).not_to have_field(type: "password", with: credential.password)
```

- [ ] **Step 2: Run provider specs and verify RED**

```bash
bundle exec rspec \
  spec/components/admin/maintenance/platform/module_settings/provider_workspace_component_spec.rb \
  spec/components/admin/maintenance/platform/module_settings/credential_panel_component_spec.rb \
  spec/components/admin/maintenance/platform/emails \
  spec/components/admin/maintenance/platform/sms/settings_component_spec.rb \
  spec/components/admin/maintenance/platform/sms/credential_form_component_spec.rb \
  spec/components/admin/maintenance/platform/captcha/settings_component_spec.rb \
  spec/components/admin/maintenance/platform/speech_to_text/settings_component_spec.rb
```

Expected: failures for missing shared provider structure.

- [ ] **Step 3: Implement the provider workspace migration**

Compose existing provider/status components inside the shared workspace.
Ensure show/edit/new pages retain module identity and active Providers
navigation. Use a narrow form column, grouped fields, inline errors, and shared
form actions. Do not modify controllers or persistence services.

- [ ] **Step 4: Run provider specs and verify GREEN**

Run the Step 2 command. Expected: all pass.

- [ ] **Step 5: Run provider request/controller regressions**

```bash
bundle exec rspec \
  spec/requests/platform/emails/credentials_spec.rb \
  spec/requests/platform/sms/credentials_spec.rb \
  spec/controllers/admin/maintenance/platform/captcha/settings_controller_spec.rb \
  spec/routing/admin/maintenance/platform/speech_to_text/settings_routing_spec.rb
```

Expected: all pass, proving routes and behavior remain unchanged.

### Task 4: Resource and operations collections

**Files:**
- Create: `app/components/admin/maintenance/platform/module_settings/responsive_collection_component.rb`
- Create: `app/components/admin/maintenance/platform/module_settings/responsive_collection_component.html.erb`
- Create: `app/components/admin/maintenance/platform/module_settings/empty_section_component.rb`
- Create: `app/components/admin/maintenance/platform/module_settings/empty_section_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/sms/template_form_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/captcha/protected_pages_component.rb`
- Modify: `app/components/admin/maintenance/platform/captcha/protected_pages_component.html.erb`
- Modify: `app/components/payments/admin/webhook_event_table_component.html.erb`
- Modify: SMS template and payment webhook view files under `app/views/admin/maintenance/platform/`
- Modify: `config/locales/maint_platform.en.yml`
- Modify: `config/locales/maint_platform.zh-CN.yml`
- Create: `spec/components/admin/maintenance/platform/module_settings/responsive_collection_component_spec.rb`
- Create: `spec/components/admin/maintenance/platform/module_settings/empty_section_component_spec.rb`
- Modify: SMS template, Captcha protected-pages, and webhook table specs
- Modify: `spec/e2e/module_settings_layout.app.spec.js`

**Interfaces:**
- Consumes: shared shell and section components.
- Produces: equivalent desktop-table and mobile-summary-card representations.
- Preserves: SMS template CRUD, Captcha surface/page updates, webhook redrive URLs, and eligibility rules.

- [ ] **Step 1: Write failing resource/operations specs**

Assert that collections expose desktop and mobile representations, equivalent
record labels/actions, consistent empty states, active Resources/Operations
navigation, and no routine mobile horizontal-scroll dependency.

- [ ] **Step 2: Run specs and verify RED**

```bash
bundle exec rspec \
  spec/components/admin/maintenance/platform/module_settings/responsive_collection_component_spec.rb \
  spec/components/admin/maintenance/platform/module_settings/empty_section_component_spec.rb \
  spec/components/admin/maintenance/platform/sms/template_form_component_spec.rb \
  spec/components/admin/maintenance/platform/captcha/protected_pages_component_spec.rb \
  spec/components/payments/admin/webhook_event_table_component_spec.rb
```

Expected: failures for missing responsive collection primitives.

- [ ] **Step 3: Implement resource and operations migration**

Render SMS templates and Captcha resources in the shared Resources area.
Render payment webhooks in Operations. Keep destructive confirmations and
redrive behavior. Use semantic badges and explicit text for states rather than
color alone.

- [ ] **Step 4: Run component and request specs**

Run the Step 2 command, then:

```bash
bundle exec rspec \
  spec/requests/platform/sms/templates_spec.rb \
  spec/requests/admin/maintenance/platform/payments/webhook_events_spec.rb \
  spec/routing/admin/maintenance/platform/captcha/surfaces_routing_spec.rb
```

Expected: all pass.

- [ ] **Step 5: Run responsive E2E checks**

```bash
npx playwright test spec/e2e/module_settings_layout.app.spec.js
```

Expected: all module-settings layout cases pass.

### Task 5: Catalog and responsive interaction coverage

**Files:**
- Modify only if needed: `app/javascript/controllers/module_settings_catalog_controller.js`
- Modify only if needed: `app/javascript/controllers/captcha_page_list_controller.js`
- Modify: matching files under `spec/javascript/controllers/`
- Modify: `spec/e2e/module_settings_layout.app.spec.js`

**Interfaces:**
- Consumes: server-rendered I18n values and data attributes.
- Produces: accessible filtering/disclosure behavior with no literal user-facing JavaScript strings.

- [ ] **Step 1: Add failing interaction tests**

Cover keyboard-operable filtering, empty filtered state, provider/resource
disclosures where added, and every new branch.

- [ ] **Step 2: Run focused Vitest and verify RED**

```bash
npx vitest run \
  spec/javascript/controllers/module_settings_catalog_controller.test.js \
  spec/javascript/controllers/captcha_page_list_controller.test.js \
  --coverage
```

Expected: new assertions fail for missing behavior.

- [ ] **Step 3: Implement minimal Stimulus changes**

Use Stimulus values for every message and label. Do not add text literals to
controller methods. Keep filtering DOM-driven and preserve server-rendered
fallback content.

- [ ] **Step 4: Run full JavaScript coverage**

```bash
npx vitest run --coverage
```

Expected: 100% lines and branches for all files under `app/javascript/**`.

- [ ] **Step 5: Run targeted Playwright coverage**

```bash
npx playwright test spec/e2e/module_settings_layout.app.spec.js
```

Expected: all desktop/mobile interaction and layout cases pass.

### Task 6: QA authorization, localization, and cross-surface regression

**Files:**
- Modify or create request/system/component specs under `spec/` only.
- Modify locale files only if parity defects are discovered before production changes are finalized.

**Interfaces:**
- Consumes: completed module-settings workspace.
- Produces: regression proof for owner-only access, route preservation, locale parity, and all six module surfaces.

- [ ] **Step 1: Add failing regression examples for uncovered acceptance criteria**

Cover anonymous, admin, member, wrong-customer, and platform-owner access;
active navigation on every nested page; and all six registered modules.

- [ ] **Step 2: Run the new specs and verify meaningful failures**

Run only the new/modified spec files. Expected: failures must identify an
uncovered UI or regression requirement rather than test setup errors.

- [ ] **Step 3: Make the smallest production/test alignment fixes**

If a regression exposes a production defect, return to the owning component
task and fix it test-first. If an existing spec asserts intentionally replaced
markup while behavior is preserved, update the stale assertion.

- [ ] **Step 4: Run the complete affected Rails test slice**

```bash
bundle exec rspec \
  spec/components/admin/maintenance/platform/module_catalog_component_spec.rb \
  spec/components/admin/maintenance/platform/module_settings \
  spec/components/admin/maintenance/platform/emails \
  spec/components/admin/maintenance/platform/sms \
  spec/components/admin/maintenance/platform/captcha \
  spec/components/admin/maintenance/platform/speech_to_text \
  spec/components/payments/admin/webhook_event_table_component_spec.rb \
  spec/requests/platform/emails/credentials_spec.rb \
  spec/requests/platform/sms/credentials_spec.rb \
  spec/requests/platform/sms/templates_spec.rb
```

Expected: all pass.

- [ ] **Step 5: Validate localization and diff hygiene**

```bash
bundle exec rails runner 'I18n.available_locales.each { |locale| I18n.with_locale(locale) { I18n.t!("maint_platform.module_settings.index.title") } }'
git diff --check
```

Expected: exit 0.

### Task 7: Release verification and final review

**Files:**
- No production edits unless a failing verification is reproduced with a test first.

**Interfaces:**
- Consumes: all completed tasks.
- Produces: test, asset, browser, convention, and correctness evidence.

- [ ] **Step 1: Run the full Rails suite in parallel**

```bash
bin/rails parallel:prepare && bin/rails parallel:spec
```

Expected: all examples pass. If parallel execution is unavailable, record the
reason and run `bundle exec rspec`.

- [ ] **Step 2: Run full JavaScript coverage and E2E**

```bash
npx vitest run --coverage
npx playwright test spec/e2e/module_settings_layout.app.spec.js
```

Expected: Vitest reports 100% lines and branches; Playwright passes.

- [ ] **Step 3: Rebuild assets and restart development**

```bash
rm -f public/assets/.manifest.json
bin/rails tailwindcss:build
pkill -f "bin/rails server" || true
SKIP_AUTH=1 nohup bin/rails server -b 0.0.0.0 -p 3000 > log/server.out 2>&1 &
```

If stale digested assets shadow source, run:

```bash
bin/rails assets:clobber
bin/rails tailwindcss:build
```

- [ ] **Step 4: Smoke-test all primary and nested surfaces**

Check HTTP responses and visually inspect desktop, tablet, and mobile layouts
for the catalog; all six module overviews; Email/SMS credentials; SMS
templates; Captcha settings/resources; Speech-to-Text settings; payment
gateway controls; and payment webhook events.

- [ ] **Step 5: Run parallel convention and correctness reviews**

Dispatch `anysys-tech-lead` and `anysys-code-reviewer` against the complete
working-tree diff. Resolve every confirmed critical/high issue and every
AGENTS.md violation, reproducing behavioral defects with a failing test first.

- [ ] **Step 6: Re-run affected verification after review fixes**

Run the specs covering fixed files, full Vitest coverage if JavaScript changed,
and the module-settings Playwright suite. Finish with:

```bash
git status --short
git diff --check
```

Expected: only intentional uncommitted project changes remain and diff check
passes.
