# AI Assistant Workspace Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or the repository's anysys-* SDLC agents to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `/:cid/admin/assistant` into a polished responsive conversation-and-artifact workspace with an immediately accessible Preview panel, a clickable page thumbnail, and an accessible large rendered-page viewer.

**Architecture:** Keep the existing controller, conversation, artifact resolution, routes, and Turbo stream boundary. Update ViewComponents and Tailwind layout, add two focused Stimulus controllers for mobile tabs and the native preview dialog, and reuse the existing authorized page preview/detail URLs without storing screenshots.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2+, ViewComponent, TailwindCSS, StimulusJS, Turbo Streams, RSpec, Vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-07-ai-assistant-workspace-redesign-design.md`

**UX:** `docs/superpowers/specs/2026-09-07-ai-assistant-workspace-redesign-ux.md`

## Global Constraints

- Preserve all existing user changes in the dirty worktree.
- Do not commit; the human reviewer will commit manually.
- No new route, migration, table, screenshot file, background job, model, assistant tool, or provider behavior.
- Every user-facing string must use I18n with matching `en` and `zh-CN` keys.
- Tailwind only for styling; Stimulus only for JavaScript; ViewComponent owns reusable markup.
- Keep `data-dashboard-region="chat"`, `data-dashboard-region="overview"`, `SpeechToText::Stream::ARTIFACT_ID`, and the existing Turbo stream name unchanged.
- Page previews and details remain server-generated, customer-scoped admin URLs.
- Thumbnail and dialog iframes are non-interactive and must not combine `allow-scripts` with `allow-same-origin`.
- Any changed or added JavaScript under `app/javascript/**` must finish at 100% lines and branches under `npx vitest run --coverage`.
- Apply the redesign to every tenant's `/:cid/admin/assistant`, not only customer `81721200`.

---

### Task 1: Responsive workspace shell and mobile tabs

**Owner:** `anysys-frontend-developer`

**Files:**

- Modify: `app/components/admin/assistants/workspace_component.rb`
- Modify: `app/components/admin/assistants/workspace_component.html.erb`
- Create: `app/javascript/controllers/assistant_workspace_controller.js`
- Modify: `spec/components/admin/assistants/workspace_component_spec.rb`
- Create: `spec/javascript/controllers/assistant_workspace_controller.test.js`
- Modify: `config/locales/speech_to_text.en.yml`
- Modify: `config/locales/speech_to_text.zh-CN.yml`

**Interfaces:**

- Consumes: `SpeechToText::AssistantPanelComponent`, `SpeechToText::ArtifactPaneComponent`.
- Produces: `assistant-workspace` controller targets named `tab` and `panel`; tab/panel identifiers `"conversation"` and `"preview"`.

- [ ] **Step 1: Write failing component specs**

Add expectations equivalent to:

```ruby
expect(page).to have_css("[data-controller~='assistant-workspace']")
expect(page).to have_css("[role='tablist']")
expect(page).to have_button(I18n.t("speech_to_text.assistant.tabs.conversation"))
expect(page).to have_button(I18n.t("speech_to_text.assistant.tabs.preview"))
expect(page).to have_css("[role='tabpanel'][data-assistant-workspace-id='conversation']")
expect(page).to have_css("[role='tabpanel'][data-assistant-workspace-id='preview']")
expect(rendered_content).to include("lg:grid-cols-[minmax(0,1fr)_minmax(22rem,0.48fr)]")
```

The unavailable state must not render the mobile tablist or either interactive controller.

- [ ] **Step 2: Run the component spec and verify RED**

Run:

```bash
bundle exec rspec spec/components/admin/assistants/workspace_component_spec.rb
```

Expected: failures for missing tablist/controller/responsive grid.

- [ ] **Step 3: Write failing Vitest coverage**

Cover:

```javascript
it("starts on the conversation panel")
it("selects preview from a clicked tab")
it("ignores an unknown tab id")
it("updates aria-selected, tabindex, and hidden classes")
it("supports direct selectTab calls whose event has no currentTarget")
```

The controller API is:

```javascript
static targets = ["tab", "panel"]
static values = { active: { type: String, default: "conversation" } }

select(event)
selectTab(id)
```

- [ ] **Step 4: Run the JS test and verify RED**

Run:

```bash
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/assistant_workspace_controller.test.js
```

Expected: module-not-found failure.

- [ ] **Step 5: Implement the responsive shell and controller**

Use the following behavior:

```javascript
select(event) {
  this.selectTab(event.currentTarget?.dataset.assistantWorkspaceId)
}

selectTab(id) {
  if (!this.tabTargets.some((tab) => tab.dataset.assistantWorkspaceId === id)) return
  this.activeValue = id
  this.tabTargets.forEach((tab) => {
    const active = tab.dataset.assistantWorkspaceId === id
    tab.setAttribute("aria-selected", String(active))
    tab.tabIndex = active ? 0 : -1
  })
  this.panelTargets.forEach((panel) => {
    const active = panel.dataset.assistantWorkspaceId === id
    panel.classList.toggle("hidden", !active)
    panel.tabIndex = active ? 0 : -1
  })
}
```

In ERB:

- render the tablist only for the available branch;
- keep tab and panel IDs fully I18n-backed;
- use `hidden lg:flex` for the inactive mobile panel so both panels remain visible at `lg`;
- use a desktop grid with conversation first and Preview second;
- set page title in `before_render` alongside the existing edge container width.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```bash
bundle exec rspec spec/components/admin/assistants/workspace_component_spec.rb
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/assistant_workspace_controller.test.js
```

Expected: zero failures.

---

### Task 2: Page thumbnail and large preview dialog

**Owner:** `anysys-frontend-developer`

**Files:**

- Modify: `app/components/speech_to_text/artifact_pane_component.rb`
- Modify: `app/components/speech_to_text/artifact_pane_component.html.erb`
- Create: `app/components/speech_to_text/artifact_preview_dialog_component.rb`
- Create: `app/components/speech_to_text/artifact_preview_dialog_component.html.erb`
- Create: `app/javascript/controllers/artifact_preview_controller.js`
- Modify: `spec/components/speech_to_text/artifact_pane_component_spec.rb`
- Create: `spec/components/speech_to_text/artifact_preview_dialog_component_spec.rb`
- Create: `spec/javascript/controllers/artifact_preview_controller.test.js`
- Modify: `config/locales/speech_to_text.en.yml`
- Modify: `config/locales/speech_to_text.zh-CN.yml`

**Interfaces:**

- Consumes: `ArtifactPaneComponent#preview_url`, `#open_url`, `#kind_label`, and the existing Turbo replacement root.
- Produces: `ArtifactPreviewDialogComponent.new(name:, preview_url:, details_url:)`.

- [ ] **Step 1: Write failing page-artifact component specs**

Require:

```ruby
expect(page).to have_css("[data-controller~='artifact-preview']")
expect(page).to have_button(
  I18n.t("speech_to_text.assistant.artifact.view_larger_label", name: page_record.name)
)
expect(page).to have_css("iframe[data-artifact-thumbnail][sandbox='allow-same-origin']")
expect(page).to have_css("iframe[data-artifact-thumbnail][tabindex='-1']")
expect(page).to have_css("dialog[aria-modal='true']")
expect(page).to have_link(
  I18n.t("speech_to_text.assistant.artifact.open_preview"),
  href: admin_maintenance_page_preview_path(customer.id, page_record)
)
expect(page).to have_link(
  I18n.t("speech_to_text.assistant.artifact.open_details"),
  href: admin_maintenance_page_path(customer.id, page_record)
)
```

Also assert:

- page artifact iframe sandbox does not include `allow-scripts` or `allow-forms`;
- entity and flowchart artifacts do not render thumbnail/dialog markup;
- empty state renders no dead links or dialog;
- links use `target="_blank"` and `rel="noopener"`.

- [ ] **Step 2: Run component specs and verify RED**

Run:

```bash
bundle exec rspec \
  spec/components/speech_to_text/artifact_pane_component_spec.rb \
  spec/components/speech_to_text/artifact_preview_dialog_component_spec.rb
```

Expected: missing component/markup failures.

- [ ] **Step 3: Write failing dialog-controller tests**

Cover every branch:

```javascript
it("opens with showModal and remembers the trigger")
it("falls back to the open attribute without showModal")
it("closes through dialog.close")
it("falls back to removing open when close is unavailable")
it("closes only when backdrop click targets the dialog itself")
it("prevents the native cancel event and closes")
it("restores trigger focus after close")
it("does not throw when the trigger cannot be focused")
```

Controller API:

```javascript
static targets = ["dialog", "trigger"]

open(event)
close()
backdrop(event)
cancel(event)
```

- [ ] **Step 4: Run the JS test and verify RED**

Run:

```bash
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/artifact_preview_controller.test.js
```

Expected: module-not-found failure.

- [ ] **Step 5: Implement the ViewComponents and controller**

Dialog behavior:

```javascript
open(event) {
  this.returnFocus = event.currentTarget || (this.hasTriggerTarget ? this.triggerTarget : null)
  if (typeof this.dialogTarget.showModal === "function") this.dialogTarget.showModal()
  else this.dialogTarget.setAttribute("open", "")
}

close() {
  if (typeof this.dialogTarget.close === "function") this.dialogTarget.close()
  else this.dialogTarget.removeAttribute("open")
  this.returnFocus?.focus?.()
}

backdrop(event) {
  if (event.target === this.dialogTarget) this.close()
}

cancel(event) {
  event.preventDefault()
  this.close()
}
```

Thumbnail structure:

- fixed-aspect clipped surface;
- iframe at `h-[200%] w-[200%] origin-top-left scale-50`;
- `pointer-events-none`, `tabindex="-1"`, and translated title;
- full-surface sibling button overlay with visible “View larger” treatment.

Dialog structure:

- native `<dialog>`;
- translated title and close label;
- large non-interactive iframe using the same preview URL;
- footer buttons for preview and details;
- responsive full-height mobile treatment and bounded desktop width.

- [ ] **Step 6: Run focused component and JS tests**

Run:

```bash
bundle exec rspec \
  spec/components/speech_to_text/artifact_pane_component_spec.rb \
  spec/components/speech_to_text/artifact_preview_dialog_component_spec.rb
npx vitest run --config config/javascript/vitest.config.js \
  spec/javascript/controllers/artifact_preview_controller.test.js
```

Expected: zero failures.

---

### Task 3: Authorization, tenant, and stream regression audit

**Owners:** `anysys-backend-developer` and `anysys-security-engineer`

**Files:**

- Modify only if a real gap is found: `spec/requests/admin/assistants_spec.rb`
- Create if useful: `spec/services/speech_to_text/stream_spec.rb`
- Do not change routes, controllers, models, database files, or authorization code unless a failing regression test proves a defect.

**Interfaces:**

- Consumes: existing `Admin::AssistantsController`, `SpeechToText::Assistant::Artifact.resolve`, and `SpeechToText::Stream.broadcast_artifact`.
- Produces: regression evidence that links and Turbo replacement remain current-customer/current-user scoped.

- [ ] **Step 1: Add failing regression coverage only for observable gaps**

Candidate expectations:

```ruby
expect(response.body).to include(
  admin_maintenance_page_preview_path(customer.id, own_page)
)
expect(response.body).not_to include(
  admin_maintenance_page_preview_path(other_customer.id, other_page)
)
```

For stream rendering, stub `Turbo::StreamsChannel.broadcast_replace_to` and assert the rendered HTML keeps `id="speech_to_text_artifact"` and uses the conversation customer.

- [ ] **Step 2: Run the relevant request/service specs**

Run:

```bash
bundle exec rspec \
  spec/requests/admin/assistants_spec.rb \
  spec/services/speech_to_text/stream_spec.rb
```

If no service spec is created, omit that path.

- [ ] **Step 3: Keep production unchanged unless RED proves a defect**

Record explicitly that no new route or authorization surface was needed.

---

### Task 4: Integrated QA and release verification

**Owners:** `anysys-qa-engineer`, then `anysys-release-engineer`

**Files:**

- Modify tests only when integration coverage is missing.
- Rebuild generated asset: `app/assets/builds/tailwind.css`
- Do not commit.

- [ ] **Step 1: Run all affected Ruby specs**

```bash
bundle exec rspec \
  spec/components/admin/assistants/workspace_component_spec.rb \
  spec/components/speech_to_text/assistant_panel_component_spec.rb \
  spec/components/speech_to_text/artifact_pane_component_spec.rb \
  spec/components/speech_to_text/artifact_preview_dialog_component_spec.rb \
  spec/requests/admin/assistants_spec.rb
```

- [ ] **Step 2: Prove JavaScript coverage**

```bash
npx vitest run --coverage
```

Expected: 100% lines and branches for all files under `app/javascript/**`, including both new controllers.

- [ ] **Step 3: Build Tailwind**

```bash
bin/rails tailwindcss:build
```

- [ ] **Step 4: Restart the development server using project conventions**

Use:

```bash
SKIP_AUTH=1 E2E_STUB_ASSISTANT=1 bin/rails server -b 0.0.0.0 -p 3000
```

Ensure stale `public/assets` digests are not shadowing sources.

- [ ] **Step 5: Browser smoke test**

At `1440x1000`, `900x1000`, and `390x844`:

- page title is AI Assistant;
- no horizontal overflow;
- desktop shows conversation and Preview side by side;
- tablet/mobile expose Conversation and Preview tabs;
- selecting Preview preserves conversation/composer state;
- page thumbnail is recognizable and keyboard-focusable through its overlay button;
- clicking opens the large dialog;
- Escape closes and focus returns;
- Open preview and Open details use customer `81721200`;
- browser console has no relevant errors or iframe sandbox warning.

- [ ] **Step 6: Parallel final review**

Dispatch:

- `anysys-tech-lead` for AGENTS.md, I18n, ViewComponent, Tailwind, Stimulus, and test-scope compliance.
- `anysys-code-reviewer` for correctness, accessibility, responsive behavior, Turbo replacement safety, and security.

- [ ] **Step 7: Review the final diff without committing**

```bash
git status --short
git diff --check
git diff --stat
```

Confirm only intended files changed in this enhancement and preserve all pre-existing user changes.
