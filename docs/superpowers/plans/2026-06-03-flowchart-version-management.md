# Flowchart Version Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins view, diff, and create-new-version-from past versions of a flowchart directly from the list page via a version-history modal.

**Architecture:** Thin backend (add `versions#show`; unify restore in `versions#create` to always leave an explicit version entry). A Stimulus-driven modal on the index page lists versions and offers a read-only canvas **preview** (reusing `FlowchartCanvas`), a raw **side-by-side JSON diff** computed client-side, and **new-version-from** (POST to the restore endpoint).

**Tech Stack:** Rails 8, ViewComponent, StimulusJS, TailwindCSS, importmap (no npm build), RSpec, Trailblazer/Reform (unused here — pure controller/model work).

**Spec:** `docs/superpowers/specs/2026-06-03-flowchart-version-management-design.md`

---

## File Structure

- `config/routes.rb` — add `:show` to the nested `versions` resource (modify).
- `app/controllers/admin/maintenance/flowchart_versions_controller.rb` — add `show`; enhance `create` (modify).
- `app/javascript/flowchart/version_diff.js` — pure JSON line-diff util (create).
- `spec/javascript/version_diff_harness.mjs` — node assertion harness for the diff util (create; no JS test runner in repo).
- `app/components/flowchart_versions_modal_component.rb` + `.html.erb` — modal shell (create).
- `app/javascript/controllers/flowchart_versions_controller.js` — modal orchestration (create).
- `app/views/admin/maintenance/flowcharts/index.html.erb` — wrap in controller, render modal, add "Versions" row action + clickable count (modify).
- `spec/requests/maintenance/flowchart_versions_spec.rb` — extend for `show` + enhanced `create` (modify).
- `spec/components/flowchart_versions_modal_component_spec.rb` — component render (create).

---

### Task 1: Backend — `versions#show` (fetch one version's configuration)

**Files:**
- Modify: `config/routes.rb` (the `resources :versions` line, ~line 213)
- Modify: `app/controllers/admin/maintenance/flowchart_versions_controller.rb`
- Test: `spec/requests/maintenance/flowchart_versions_spec.rb`

- [ ] **Step 1: Write the failing request spec**

Append inside the top-level `RSpec.describe` in `spec/requests/maintenance/flowchart_versions_spec.rb` (reuse the file's existing `let`/login helpers; if it has a `sign_in`/owner setup, mirror it):

```ruby
describe "GET show" do
  let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer, entity: entity) }
  let!(:version) { flowchart.create_version_snapshot!(description: "v-test"); flowchart.flowchart_versions.ordered.first }

  it "returns the version configuration for the tenant" do
    get "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/versions/#{version.id}.json"
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["version_number"]).to eq(version.version_number)
    expect(body["configuration"]).to be_present
  end

  it "404s for a version that belongs to another flowchart" do
    other = create(:flowchart, :simple, :draft, customer: customer, entity: entity)
    other.create_version_snapshot!
    foreign = other.flowchart_versions.ordered.first
    get "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/versions/#{foreign.id}.json"
    expect(response).to have_http_status(:not_found)
  end
end
```

> If the existing spec defines `customer`/`entity`/auth differently, match those names. The two `it`s are the contract; adapt only the setup plumbing.

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb -e "GET show"`
Expected: FAIL — `No route matches [GET] .../versions/:id` (routing error).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, change:
```ruby
resources :versions, only: %i[index create], controller: "maintenance/flowchart_versions"
```
to:
```ruby
resources :versions, only: %i[index show create], controller: "maintenance/flowchart_versions"
```

- [ ] **Step 4: Implement `show`**

In `app/controllers/admin/maintenance/flowchart_versions_controller.rb`, add a `show` action after `index`:
```ruby
def show
  version = @flowchart.flowchart_versions.find(params[:id])
  render json: {
    id: version.id,
    version_number: version.version_number,
    description: version.description,
    created_at: version.created_at.iso8601,
    configuration: version.configuration
  }
end
```
`find` raises `ActiveRecord::RecordNotFound` for a foreign id → Rails renders 404. `find_flowchart` already scopes via `Flowchart.accessible`, so a cross-tenant flowchart id is also blocked.

- [ ] **Step 5: Run the spec to confirm it passes**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb -e "GET show"`
Expected: PASS (2 examples).

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/maintenance/flowchart_versions_controller.rb spec/requests/maintenance/flowchart_versions_spec.rb
git commit -m "feat(flowcharts): add versions#show for preview/diff"
```

---

### Task 2: Backend — enhance `create` to always leave an explicit version entry

**Files:**
- Modify: `app/controllers/admin/maintenance/flowchart_versions_controller.rb`
- Test: `spec/requests/maintenance/flowchart_versions_spec.rb`

- [ ] **Step 1: Write/extend the failing spec**

Add inside the existing `describe "POST create"` (or create that block) in the versions request spec:
```ruby
describe "POST create (restore as new version)" do
  let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer, entity: entity) }

  it "preserves current state and adds an explicit restored version" do
    flowchart.create_version_snapshot!(description: "v1")
    target = flowchart.flowchart_versions.ordered.first
    target_config = target.configuration

    expect {
      post "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/versions.json",
           params: { version_id: target.id }
    }.to change { flowchart.flowchart_versions.count }.by(2) # preserve + restored

    expect(response).to have_http_status(:ok)
    expect(flowchart.reload.configuration).to eq(target_config)
    expect(flowchart.flowchart_versions.ordered.first.description).to eq("Restored from v#{target.version_number}")
  end

  it "is blocked for an active (non-draft) flowchart" do
    flowchart.create_version_snapshot!
    target = flowchart.flowchart_versions.ordered.first
    flowchart.update_column(:status, Flowchart.statuses[:active])
    post "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/versions.json",
         params: { version_id: target.id }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
```

> If a `POST create` block already exists asserting the old single-snapshot behavior, **rewrite** that example to the `by(2)` expectation above (stale-test policy: production behavior changed intentionally). Keep the active-flowchart guard example.

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb -e "restore as new version"`
Expected: FAIL — version count changes by 1, not 2.

- [ ] **Step 3: Enhance `create`**

In `flowchart_versions_controller.rb`, replace the `create` body:
```ruby
def create
  version = @flowchart.flowchart_versions.find(params[:version_id])
  @flowchart.create_version_snapshot!(description: "Before restore to v#{version.version_number}")
  @flowchart.update!(configuration: version.configuration)
  # Always leave an explicit version entry for the restored state so
  # "create new version from vN" (and editor Restore) produce a fresh,
  # inspectable version rather than only mutating the live configuration.
  @flowchart.create_version_snapshot!(description: "Restored from v#{version.version_number}")
  render json: { success: true, configuration: @flowchart.configuration, version_number: @flowchart.flowchart_versions.maximum(:version_number) }
end
```

- [ ] **Step 4: Run the spec to confirm it passes**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb`
Expected: PASS (all examples in the file).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/flowchart_versions_controller.rb spec/requests/maintenance/flowchart_versions_spec.rb
git commit -m "feat(flowcharts): restore always creates an explicit new version entry"
```

---

### Task 3: JS — `version_diff.js` pure line-diff util + node harness

**Files:**
- Create: `app/javascript/flowchart/version_diff.js`
- Test: `spec/javascript/version_diff_harness.mjs`

- [ ] **Step 1: Write the failing harness**

Create `spec/javascript/version_diff_harness.mjs`:
```js
import { versionDiff } from "../../app/javascript/flowchart/version_diff.js"

let pass = 0, fail = 0
const ck = (name, cond) => { if (cond) pass++; else { fail++; console.log(`FAIL: ${name}`) } }

// Identical configs (different key order) → all context rows, no add/del.
const a = JSON.stringify({ b: 1, a: 2 })
const b = JSON.stringify({ a: 2, b: 1 })
let rows = versionDiff(a, b)
ck("identical → no add/del", rows.every(r => r.type === "context"))

// A changed value → one del + one add for that line.
rows = versionDiff(JSON.stringify({ x: 1 }), JSON.stringify({ x: 2 }))
ck("change → has del", rows.some(r => r.type === "del" && /"x": 1/.test(r.left)))
ck("change → has add", rows.some(r => r.type === "add" && /"x": 2/.test(r.right)))

// An added key → an add row appears.
rows = versionDiff(JSON.stringify({ x: 1 }), JSON.stringify({ x: 1, y: 9 }))
ck("addition → has add row", rows.some(r => r.type === "add" && /"y": 9/.test(r.right)))

// Accepts already-parsed objects too.
rows = versionDiff({ x: 1 }, { x: 1 })
ck("accepts objects", rows.every(r => r.type === "context"))

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail ? 1 : 0)
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node spec/javascript/version_diff_harness.mjs`
Expected: FAIL — `Cannot find module .../version_diff.js`.

- [ ] **Step 3: Implement the util**

Create `app/javascript/flowchart/version_diff.js`:
```js
/**
 * Pure side-by-side line diff for two flowchart configurations.
 * Produces rows { type: "context"|"add"|"del", left, right } from a
 * stable-key pretty-print of each config so semantically-equal configs with
 * different key ordering do not show spurious differences.
 */

function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys)
  if (value && typeof value === "object") {
    return Object.keys(value).sort().reduce((acc, k) => {
      acc[k] = sortKeys(value[k])
      return acc
    }, {})
  }
  return value
}

function parse(config) {
  return typeof config === "string" ? JSON.parse(config) : config
}

function prettyLines(config) {
  return JSON.stringify(sortKeys(parse(config)), null, 2).split("\n")
}

/**
 * @param {string|object} leftConfig
 * @param {string|object} rightConfig
 * @returns {Array<{type:string,left:?string,right:?string}>}
 */
export function versionDiff(leftConfig, rightConfig) {
  const a = prettyLines(leftConfig)
  const b = prettyLines(rightConfig)
  const m = a.length, n = b.length

  // LCS length table (suffix form).
  const dp = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0))
  for (let i = m - 1; i >= 0; i--) {
    for (let j = n - 1; j >= 0; j--) {
      dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1])
    }
  }

  const rows = []
  let i = 0, j = 0
  while (i < m && j < n) {
    if (a[i] === b[j]) {
      rows.push({ type: "context", left: a[i], right: b[j] }); i++; j++
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      rows.push({ type: "del", left: a[i], right: null }); i++
    } else {
      rows.push({ type: "add", left: null, right: b[j] }); j++
    }
  }
  while (i < m) { rows.push({ type: "del", left: a[i], right: null }); i++ }
  while (j < n) { rows.push({ type: "add", left: null, right: b[j] }); j++ }
  return rows
}

export default versionDiff
```

- [ ] **Step 4: Run the harness + syntax check to confirm pass**

Run: `node --check app/javascript/flowchart/version_diff.js && node spec/javascript/version_diff_harness.mjs`
Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/flowchart/version_diff.js spec/javascript/version_diff_harness.mjs
git commit -m "feat(flowcharts): pure JSON line-diff util for version compare"
```

---

### Task 4: Frontend — `FlowchartVersionsModalComponent`

**Files:**
- Create: `app/components/flowchart_versions_modal_component.rb`
- Create: `app/components/flowchart_versions_modal_component.html.erb`
- Test: `spec/components/flowchart_versions_modal_component_spec.rb`

- [ ] **Step 1: Write the failing component spec**

Create `spec/components/flowchart_versions_modal_component_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartVersionsModalComponent, type: :component do
  it "renders the hidden modal shell with list, content and action targets" do
    render_inline(described_class.new(customer_id: "81721200"))

    expect(page).to have_css("[data-flowchart-versions-target='modal']", visible: :all)
    expect(page).to have_css("[data-flowchart-versions-target='list']", visible: :all)
    expect(page).to have_css("[data-flowchart-versions-target='content']", visible: :all)
    expect(page).to have_css("[data-flowchart-versions-target='diffButton']", visible: :all)
    expect(page).to have_css("[data-flowchart-versions-target='newButton']", visible: :all)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec rspec spec/components/flowchart_versions_modal_component_spec.rb`
Expected: FAIL — `uninitialized constant FlowchartVersionsModalComponent`.

- [ ] **Step 3: Implement the component class**

Create `app/components/flowchart_versions_modal_component.rb`:
```ruby
# frozen_string_literal: true

# Hidden version-history modal rendered once on the flowcharts index page.
# Parameterized at open time (flowchart id/name) by the `flowchart-versions`
# Stimulus controller; this component only renders the static shell + targets.
class FlowchartVersionsModalComponent < ApplicationComponent
  attr_reader :customer_id

  def initialize(customer_id:)
    @customer_id = customer_id
  end
end
```

- [ ] **Step 4: Implement the template**

Create `app/components/flowchart_versions_modal_component.html.erb`:
```erb
<div data-flowchart-versions-target="modal"
     class="hidden fixed inset-0 z-50 overflow-hidden">
  <div class="absolute inset-0 bg-slate-900/40 backdrop-blur-[2px]"
       data-action="click->flowchart-versions#close"></div>
  <div class="absolute inset-0 flex items-center justify-center p-4">
    <div class="relative w-full max-w-4xl bg-white rounded-xl shadow-2xl ring-1 ring-black/5 max-h-[85vh] flex flex-col">
      <div class="flex items-center justify-between px-4 py-3 border-b border-slate-100">
        <h3 class="text-sm font-semibold text-slate-900">
          Versions — <span data-flowchart-versions-target="title"></span>
        </h3>
        <button type="button" data-action="click->flowchart-versions#close"
                class="text-slate-400 hover:text-slate-600 p-1 rounded-md hover:bg-slate-100">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
        </button>
      </div>

      <div data-flowchart-versions-target="error"
           class="hidden mx-4 mt-3 px-3 py-2 rounded-md bg-red-50 text-red-700 text-xs"></div>

      <div class="flex-1 min-h-0 grid grid-cols-1 md:grid-cols-[18rem,1fr]">
        <aside class="border-r border-slate-100 overflow-y-auto">
          <ul data-flowchart-versions-target="list" class="divide-y divide-slate-100 text-sm">
            <li class="px-4 py-6 text-center text-slate-400 text-xs">Loading versions…</li>
          </ul>
        </aside>
        <section data-flowchart-versions-target="content"
                 class="overflow-auto p-3 text-xs text-slate-500">
          Select a version to preview, or pick two to diff.
        </section>
      </div>

      <div class="flex items-center justify-end gap-2 px-4 py-3 border-t border-slate-100 bg-slate-50/50">
        <button type="button" data-flowchart-versions-target="diffButton" disabled
                data-action="click->flowchart-versions#diff"
                class="px-3 py-1.5 text-xs font-medium text-slate-700 bg-white border border-slate-200 rounded-md hover:bg-slate-50 disabled:opacity-50 disabled:cursor-not-allowed">
          Diff selected
        </button>
        <button type="button" data-flowchart-versions-target="newButton" disabled
                data-action="click->flowchart-versions#newVersionFrom"
                class="px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed">
          New version from
        </button>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Run the spec to confirm it passes**

Run: `bundle exec rspec spec/components/flowchart_versions_modal_component_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/components/flowchart_versions_modal_component.rb app/components/flowchart_versions_modal_component.html.erb spec/components/flowchart_versions_modal_component_spec.rb
git commit -m "feat(flowcharts): version-history modal component shell"
```

---

### Task 5: Frontend — `flowchart_versions_controller.js` (Stimulus)

**Files:**
- Create: `app/javascript/controllers/flowchart_versions_controller.js`

> No JS test runner exists; verify with `node --check` and the diff harness (Task 3). The controller is registered automatically by the `pin_all_from app/javascript/controllers` importmap rule as identifier `flowchart-versions`.

- [ ] **Step 1: Implement the controller**

Create `app/javascript/controllers/flowchart_versions_controller.js`:
```js
import { Controller } from "@hotwired/stimulus"
import { getCSRFToken, escapeHtml } from "utils"
import { versionDiff } from "flowchart/version_diff"
import { FlowchartCanvas } from "flowchart/canvas"

// Version-history modal on the flowcharts index page. Lists versions for a
// flowchart and offers: read-only canvas preview, raw JSON side-by-side diff
// (client-side), and create-new-version-from (POST to the restore endpoint).
export default class extends Controller {
  static targets = ["modal", "title", "list", "content", "diffButton", "newButton", "error"]
  static values = { customerId: String }

  connect() {
    this.flowchartId = null
    this.versions = []
    this.selected = [] // selected version ids (max 2)
  }

  open(event) {
    if (event) event.preventDefault()
    const params = event?.params || {}
    this.flowchartId = params.flowchartId
    this.flowchartName = params.flowchartName || "Flowchart"
    this.selected = []
    if (this.hasTitleTarget) this.titleTarget.textContent = this.flowchartName
    this._clearError()
    if (this.hasContentTarget) this.contentTarget.textContent = "Select a version to preview, or pick two to diff."
    this.modalTarget.classList.remove("hidden")
    this.loadVersions()
  }

  close(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.add("hidden")
    this._previewCanvas = null
    if (this.hasContentTarget) this.contentTarget.innerHTML = ""
  }

  async loadVersions() {
    const res = await this._fetch(this._base(), { headers: { Accept: "application/json" } })
    if (!res) return
    if (!res.ok) return this._error(`Failed to load versions (${res.status})`)
    this.versions = await res.json()
    this._renderList()
    this._updateButtons()
  }

  toggleSelect(event) {
    const id = String(event.params.id)
    const idx = this.selected.indexOf(id)
    if (idx >= 0) {
      this.selected.splice(idx, 1)
    } else {
      this.selected.push(id)
      if (this.selected.length > 2) this.selected.shift() // keep last two
    }
    this._renderList()
    this._updateButtons()
  }

  async view(event) {
    if (event) event.preventDefault()
    const id = String(event.params.id)
    const data = await this._showVersion(id)
    if (!data) return
    this._renderPreview(data.configuration)
  }

  async diff(event) {
    if (event) event.preventDefault()
    if (this.selected.length !== 2) return
    const [a, b] = this.selected
    const [va, vb] = await Promise.all([this._showVersion(a), this._showVersion(b)])
    if (!va || !vb) return
    this._renderDiff(va, vb)
  }

  async newVersionFrom(event) {
    if (event) event.preventDefault()
    if (this.selected.length !== 1) return
    const id = this.selected[0]
    const res = await this._fetch(this._base(), {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": getCSRFToken(), Accept: "application/json" },
      body: JSON.stringify({ version_id: id })
    })
    if (!res) return
    if (res.status === 422) {
      const body = await res.json().catch(() => ({}))
      return this._error(body.message || "Cannot create a version while the flowchart is active. Deactivate it first.")
    }
    if (!res.ok) return this._error(`Failed to create version (${res.status})`)
    this._clearError()
    this.selected = []
    await this.loadVersions()
    this._bumpRowCount()
  }

  // ---- private ----

  _base() {
    return `/${this.customerIdValue}/admin/maintenance/flowcharts/${this.flowchartId}/versions`
  }

  async _showVersion(id) {
    const res = await this._fetch(`${this._base()}/${id}.json`, { headers: { Accept: "application/json" } })
    if (!res) return null
    if (!res.ok) { this._error(`Failed to load version (${res.status})`); return null }
    return res.json()
  }

  async _fetch(url, opts) {
    try { return await fetch(url, opts) }
    catch (e) { this._error(`Network error: ${e.message}`); return null }
  }

  _renderList() {
    if (!this.hasListTarget) return
    if (this.versions.length === 0) {
      this.listTarget.innerHTML = `<li class="px-4 py-6 text-center text-slate-400 text-xs">No versions yet.</li>`
      return
    }
    this.listTarget.innerHTML = this.versions.map(v => {
      const id = String(v.id)
      const checked = this.selected.includes(id)
      return `
        <li class="px-3 py-2 flex items-start gap-2 ${checked ? "bg-indigo-50/60" : ""}">
          <input type="checkbox" ${checked ? "checked" : ""}
                 data-action="change->flowchart-versions#toggleSelect"
                 data-flowchart-versions-id-param="${escapeHtml(id)}"
                 class="mt-0.5">
          <div class="flex-1 min-w-0">
            <div class="text-xs font-medium text-slate-800">v${escapeHtml(String(v.version_number))}</div>
            <div class="text-[11px] text-slate-500 truncate">${escapeHtml(v.description || "")}</div>
            <div class="text-[10px] text-slate-400">${escapeHtml(v.created_at || "")}</div>
          </div>
          <button type="button" data-action="click->flowchart-versions#view"
                  data-flowchart-versions-id-param="${escapeHtml(id)}"
                  class="text-[11px] font-medium text-indigo-600 hover:text-indigo-700">View</button>
        </li>`
    }).join("")
  }

  _renderPreview(configuration) {
    const config = typeof configuration === "string" ? JSON.parse(configuration) : configuration
    this.contentTarget.innerHTML = `<div data-preview-canvas class="w-full h-[55vh] border border-slate-200 rounded bg-slate-50"></div>`
    const container = this.contentTarget.querySelector("[data-preview-canvas]")
    const canvas = new FlowchartCanvas(container)
    canvas.isReadOnly = true
    canvas.loadConfiguration(config)
    this._previewCanvas = canvas
  }

  _renderDiff(va, vb) {
    const rows = versionDiff(va.configuration, vb.configuration)
    const side = (text, cls) => `<td class="align-top w-1/2 px-2 py-0.5 font-mono text-[11px] whitespace-pre ${cls}">${text == null ? "" : escapeHtml(text)}</td>`
    const body = rows.map(r => {
      if (r.type === "add") return `<tr class="bg-green-50">${side("", "")}${side(r.right, "text-green-800")}</tr>`
      if (r.type === "del") return `<tr class="bg-red-50">${side(r.left, "text-red-800")}${side("", "")}</tr>`
      return `<tr>${side(r.left, "text-slate-600")}${side(r.right, "text-slate-600")}</tr>`
    }).join("")
    this.contentTarget.innerHTML = `
      <div class="text-[11px] text-slate-500 mb-2">Comparing v${escapeHtml(String(va.version_number))} → v${escapeHtml(String(vb.version_number))}</div>
      <table class="w-full table-fixed border-collapse"><tbody>${body}</tbody></table>`
  }

  _updateButtons() {
    if (this.hasDiffButtonTarget) this.diffButtonTarget.disabled = this.selected.length !== 2
    if (this.hasNewButtonTarget) this.newButtonTarget.disabled = this.selected.length !== 1
  }

  _bumpRowCount() {
    // Best-effort: refresh the list page's turbo-frame so the Versions count updates.
    const frame = document.querySelector("turbo-frame#admin-table")
    if (frame && frame.src) frame.reload?.()
  }

  _error(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  _clearError() {
    if (this.hasErrorTarget) this.errorTarget.classList.add("hidden")
  }
}
```

- [ ] **Step 2: Syntax check**

Run: `node --check app/javascript/controllers/flowchart_versions_controller.js`
Expected: no output (valid).

- [ ] **Step 3: Confirm `escapeHtml` is exported from utils**

Run: `grep -n "export function escapeHtml" app/javascript/utils/index.js`
Expected: a match. If it's exported elsewhere, adjust the import in Step 1 accordingly (it is used widely by the property editor, so it exists).

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/flowchart_versions_controller.js
git commit -m "feat(flowcharts): version-history modal Stimulus controller"
```

---

### Task 6: Wire the modal into the list page

**Files:**
- Modify: `app/views/admin/maintenance/flowcharts/index.html.erb`
- Test: `spec/requests/maintenance/flowcharts_spec.rb` (smoke — index renders)

- [ ] **Step 1: Add a failing smoke expectation**

In `spec/requests/maintenance/flowcharts_spec.rb`, inside the existing `GET index` context, add:
```ruby
it "renders the version-history modal controller on the list page" do
  get "/#{customer.id}/admin/maintenance/flowcharts"
  expect(response.body).to include('data-controller="flowchart-versions"')
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec rspec spec/requests/maintenance/flowcharts_spec.rb -e "version-history modal"`
Expected: FAIL — body lacks the controller attribute.

- [ ] **Step 3: Wrap the index content and add the row action + clickable count**

Replace `app/views/admin/maintenance/flowcharts/index.html.erb` with:
```erb
<%= render AdminPageComponent.new(
  breadcrumbs: [
    { label: "Maintenance", path: admin_maintenance_path(current_customer_id) },
    { label: "Flowcharts" }
  ],
  title: "Flowchart Definitions",
  description: "Manage business logic flow definitions",
  actions: [
    { label: "New Flowchart", path: new_admin_maintenance_flowchart_path(current_customer_id), variant: :primary, icon: :plus }
  ]
) do %>
  <div data-controller="flowchart-versions"
       data-flowchart-versions-customer-id-value="<%= current_customer_id %>">
    <%= render AdminTableComponent.new(
    rows:        @rows,
    columns:     @columns,
    pagination:  @pagination,
    params:      params.permit(:q, :sort, :dir, :page).to_h.symbolize_keys,
    search:      { param: :q, placeholder: "Search flowcharts…" },
    row_path:    ->(f) { admin_maintenance_flowchart_path(current_customer_id, f) },
    row_actions: ->(f) { [
      { label: "Edit",   path: edit_admin_maintenance_flowchart_path(current_customer_id, f) },
      { label: "Versions", path: "#",
        data: { turbo: "false", action: "flowchart-versions#open",
                "flowchart-versions-flowchart-id-param": f.id,
                "flowchart-versions-flowchart-name-param": f.name } },
      { label: "Copy",   path: admin_maintenance_flowchart_copy_path(current_customer_id, f) },
      { label: "Delete", path: admin_maintenance_flowchart_path(current_customer_id, f),
        method: :delete,
        data: { turbo_confirm: "Delete \"#{f.name}\"? It will be moved to trash." } }
    ] },
    empty_state: {
      title: "No flowcharts yet",
      description: "Create your first flowchart to model business logic.",
      action_path: new_admin_maintenance_flowchart_path(current_customer_id),
      action_text: "Create flowchart"
    }
    ) %>

    <%= render FlowchartVersionsModalComponent.new(customer_id: current_customer_id) %>
  </div>
<% end %>
```

> Note: AdminTableComponent's desktop view shows the first 2 row actions inline and the rest in the overflow menu (`take(2)` on mobile); "Versions" placed second keeps it prominent. `data: { turbo: "false" }` stops Turbo from intercepting the `#` link so the Stimulus `open` handler runs.

- [ ] **Step 4: Run the smoke spec to confirm it passes**

Run: `bundle exec rspec spec/requests/maintenance/flowcharts_spec.rb -e "version-history modal"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/admin/maintenance/flowcharts/index.html.erb spec/requests/maintenance/flowcharts_spec.rb
git commit -m "feat(flowcharts): open version-history modal from the list page"
```

---

### Task 7: Full verification

- [ ] **Step 1: Rebuild assets and run the touched suite**

```bash
rm -f public/assets/.manifest.json
node --check app/javascript/flowchart/version_diff.js
node --check app/javascript/controllers/flowchart_versions_controller.js
node spec/javascript/version_diff_harness.mjs
bundle exec rspec \
  spec/requests/maintenance/flowchart_versions_spec.rb \
  spec/requests/maintenance/flowcharts_spec.rb \
  spec/components/flowchart_versions_modal_component_spec.rb
```
Expected: harness `5 passed, 0 failed`; all RSpec examples green.

- [ ] **Step 2: Manual smoke (optional, requires a browser/dev server)**

```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```
Visit `/81721200/admin/maintenance/flowcharts`, click a row's **Versions** action, then View / select-two-and-Diff / select-one-and-New-version-from.

---

## Self-Review

**Spec coverage:**
- View a version (read-only canvas preview) → Task 1 (`show`) + Task 5 (`_renderPreview` via `FlowchartCanvas` read-only). ✓
- Create new version from a version (restore-as-new, explicit entry) → Task 2 (`create`) + Task 5 (`newVersionFrom`). ✓
- Diff two versions (raw JSON side-by-side) → Task 3 (`version_diff`) + Task 5 (`diff`/`_renderDiff`). ✓
- Reachable from list page via modal → Task 4 (component) + Task 6 (wiring). ✓
- Auth/tenant (admin/owner, scoped, shared read-only, active→422) → inherited guards (`find_flowchart`/`guard_shared_write!`/`guard_not_draft!`) covered by Task 1/2 specs. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. ✓

**Type/name consistency:** Stimulus identifier `flowchart-versions` and targets (`modal/title/list/content/diffButton/newButton/error`) match between the component template (Task 4) and the controller (Task 5). `versionDiff` export name matches import in Task 5 and the harness in Task 3. The `create` JSON shape `{ success, configuration, version_number }` matches what the editor's existing `restoreVersion` consumes (`data.configuration`). ✓
