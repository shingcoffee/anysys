# Flowchart Status Draft/Active Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add draft/active workflow to flowcharts where only active flowcharts can be referenced and only draft flowcharts can be edited.

**Architecture:** Extend existing status enum with `draft` value, add model validation to block edits on active flowcharts, add controller actions for activate/deactivate, update UI to show status and respect read-only state.

**Tech Stack:** Ruby on Rails, RSpec, Stimulus JS, TailwindCSS, ViewComponent

---

## File Structure

**Model:**
- `app/models/flowchart.rb` — add draft enum value, referenceable scope, edit restriction validation

**Controller:**
- `app/controllers/flowcharts_controller.rb` — add activate/deactivate actions

**Routes:**
- `config/routes.rb` — add member routes for activate/deactivate

**Views/Components:**
- `app/components/flowchart_list_table_component.rb` — add status badge helper
- `app/components/flowchart_list_table_component.html.erb` — render status badge
- `app/views/flowcharts/show.html.erb` — show status badge and activate/deactivate buttons
- `app/views/flowcharts/_editor.html.erb` — pass read-only flag, show banner for active flowcharts

**JavaScript:**
- `app/javascript/controllers/flowchart_canvas_controller.js` — respect read-only mode
- `app/javascript/controllers/toolbar_controller.js` — disable save for active flowcharts

**Controllers (flowchart selection):**
- `app/controllers/pages_controller.rb` — use referenceable scope for flowchart dropdowns

**Specs:**
- `spec/models/flowchart_spec.rb` — enum, scopes, edit validation
- `spec/controllers/flowcharts_controller_spec.rb` — activate/deactivate actions
- `spec/factories/flowcharts.rb` — add draft trait

---

### Task 1: Update Flowchart Model — Enum and Scopes

**Files:**
- Modify: `app/models/flowchart.rb:18` (enum definition)
- Modify: `app/models/flowchart.rb:46-60` (scopes section)

- [ ] **Step 1: Write failing test for draft enum value**

In `spec/models/flowchart_spec.rb`, add after the existing validations describe block:

```ruby
describe 'status enum' do
  let(:entity) { create(:entity, customer: customer) }

  it 'supports draft status' do
    flowchart = Flowchart.new(
      name: 'Test',
      configuration: valid_configuration.to_json,
      type: :customer_specific,
      entity: entity,
      customer: customer,
      status: :draft
    )
    expect(flowchart).to be_valid
    expect(flowchart.draft?).to be true
  end

  it 'defaults new flowcharts to draft' do
    flowchart = Flowchart.new(
      name: 'Test',
      configuration: valid_configuration.to_json,
      type: :customer_specific,
      entity: entity,
      customer: customer
    )
    expect(flowchart.status).to eq('draft')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "status enum" --format documentation`

Expected: FAIL — draft status not recognized or default is active

- [ ] **Step 3: Update enum in model**

In `app/models/flowchart.rb`, change line 18 from:

```ruby
enum :status, { active: 0, deleted: 1 }, default: :active
```

to:

```ruby
enum :status, { active: 0, deleted: 1, draft: 2 }, default: :draft
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "status enum" --format documentation`

Expected: PASS

- [ ] **Step 5: Write failing test for referenceable scope**

Add to `spec/models/flowchart_spec.rb` inside the scopes describe block:

```ruby
describe '.referenceable' do
  let(:entity) { create(:entity, customer: customer) }
  let!(:draft_flowchart) { Flowchart.create!(name: 'Draft', configuration: valid_configuration.to_json, type: :customer_specific, entity: entity, customer: customer, status: :draft) }
  let!(:active_flowchart) { Flowchart.create!(name: 'Active', configuration: valid_configuration.to_json, type: :customer_specific, entity: entity, customer: customer, status: :active) }

  it 'returns only active flowcharts' do
    expect(Flowchart.referenceable).to include(active_flowchart)
    expect(Flowchart.referenceable).not_to include(draft_flowchart)
  end
end
```

- [ ] **Step 6: Run test to verify it fails**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "referenceable" --format documentation`

Expected: FAIL — undefined method `referenceable`

- [ ] **Step 7: Add referenceable scope**

In `app/models/flowchart.rb`, add after line 53 (after the `customer_specific` scope):

```ruby
scope :referenceable, -> { where(status: :active) }
```

- [ ] **Step 8: Run test to verify it passes**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "referenceable" --format documentation`

Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add app/models/flowchart.rb spec/models/flowchart_spec.rb
git commit -m "$(cat <<'EOF'
feat(flowchart): add draft status and referenceable scope

- Add draft (value: 2) to status enum
- Change default from active to draft
- Add referenceable scope for active-only queries

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add Edit Restriction Validation

**Files:**
- Modify: `app/models/flowchart.rb:44` (validations section)
- Modify: `app/models/flowchart.rb:172+` (private methods)

- [ ] **Step 1: Write failing test for edit restriction**

Add to `spec/models/flowchart_spec.rb`:

```ruby
describe 'edit restriction' do
  let(:entity) { create(:entity, customer: customer) }

  context 'when flowchart is draft' do
    let(:flowchart) { Flowchart.create!(name: 'Draft FC', configuration: valid_configuration.to_json, type: :customer_specific, entity: entity, customer: customer, status: :draft) }

    it 'allows editing' do
      flowchart.name = 'Updated Name'
      expect(flowchart).to be_valid
      expect(flowchart.save).to be true
    end
  end

  context 'when flowchart is active' do
    let(:flowchart) { Flowchart.create!(name: 'Active FC', configuration: valid_configuration.to_json, type: :customer_specific, entity: entity, customer: customer, status: :active) }

    it 'blocks editing non-status fields' do
      flowchart.name = 'Updated Name'
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:base]).to include('Cannot edit an active flowchart. Deactivate it first.')
    end

    it 'allows status changes' do
      flowchart.status = :draft
      expect(flowchart).to be_valid
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "edit restriction" --format documentation`

Expected: FAIL — active flowchart edit should be blocked but isn't

- [ ] **Step 3: Add validation to model**

In `app/models/flowchart.rb`, add after line 44 (after the existing validations):

```ruby
validate :must_be_draft_to_edit, on: :update
```

Then add the private method after line 241 (in the private section, before `generate_uuid`):

```ruby
def must_be_draft_to_edit
  return if status_changed?
  return if draft?

  errors.add(:base, 'Cannot edit an active flowchart. Deactivate it first.')
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "edit restriction" --format documentation`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/flowchart.rb spec/models/flowchart_spec.rb
git commit -m "$(cat <<'EOF'
feat(flowchart): add edit restriction for active flowcharts

Only draft flowcharts can be edited. Status changes are still
allowed to support activate/deactivate transitions.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add Routes for Activate/Deactivate

**Files:**
- Modify: `config/routes.rb:76-90`

- [ ] **Step 1: Add member routes**

In `config/routes.rb`, update the flowcharts resource block (around line 76) to add activate and deactivate:

```ruby
resources :flowcharts do
  member do
    patch :autosave
    patch :restore
    get :copy
    post :trace
    get :versions
    post :restore_version
    get :generate_docs
    post :activate
    post :deactivate
  end
  collection do
    get :trash
    delete :empty_trash
  end
end
```

- [ ] **Step 2: Verify routes exist**

Run: `bundle exec rails routes | grep -E "activate|deactivate" | grep flowchart`

Expected output should include:
```
activate_flowchart POST /:customer_id/flowcharts/:id/activate
deactivate_flowchart POST /:customer_id/flowcharts/:id/deactivate
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "$(cat <<'EOF'
feat(routes): add activate/deactivate routes for flowcharts

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Add Controller Actions

**Files:**
- Modify: `app/controllers/flowcharts_controller.rb:18` (before_action)
- Modify: `app/controllers/flowcharts_controller.rb:160+` (new actions)

- [ ] **Step 1: Write failing test for activate action**

Add to `spec/controllers/flowcharts_controller_spec.rb`:

```ruby
describe 'POST #activate' do
  context 'when flowchart is draft' do
    let(:draft_flowchart) { Flowchart.create!(valid_attributes.merge(status: :draft)) }

    it 'activates the flowchart' do
      post :activate, params: { customer_id: customer.id, id: draft_flowchart.to_param }
      draft_flowchart.reload
      expect(draft_flowchart.status).to eq('active')
    end

    it 'redirects to show page with notice' do
      post :activate, params: { customer_id: customer.id, id: draft_flowchart.to_param }
      expect(response).to redirect_to(flowchart_path(customer.id, draft_flowchart))
      expect(flash[:notice]).to eq('Flowchart activated successfully.')
    end
  end

  context 'when flowchart is already active' do
    let(:active_flowchart) { Flowchart.create!(valid_attributes.merge(status: :active)) }

    it 'returns unprocessable_entity' do
      post :activate, params: { customer_id: customer.id, id: active_flowchart.to_param }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'sets an alert flash' do
      post :activate, params: { customer_id: customer.id, id: active_flowchart.to_param }
      expect(flash[:alert]).to eq('Flowchart is already active.')
    end
  end

  context 'when flowchart is deleted' do
    let(:deleted_flowchart) { Flowchart.create!(valid_attributes.merge(status: :deleted)) }

    it 'returns not found' do
      expect {
        post :activate, params: { customer_id: customer.id, id: deleted_flowchart.to_param }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb -e "POST #activate" --format documentation`

Expected: FAIL — unknown action `activate`

- [ ] **Step 3: Write failing test for deactivate action**

Add to `spec/controllers/flowcharts_controller_spec.rb`:

```ruby
describe 'POST #deactivate' do
  context 'when flowchart is active' do
    let(:active_flowchart) { Flowchart.create!(valid_attributes.merge(status: :active)) }

    it 'deactivates the flowchart to draft' do
      post :deactivate, params: { customer_id: customer.id, id: active_flowchart.to_param }
      active_flowchart.reload
      expect(active_flowchart.status).to eq('draft')
    end

    it 'redirects to show page with notice' do
      post :deactivate, params: { customer_id: customer.id, id: active_flowchart.to_param }
      expect(response).to redirect_to(flowchart_path(customer.id, active_flowchart))
      expect(flash[:notice]).to eq('Flowchart deactivated successfully.')
    end
  end

  context 'when flowchart is already draft' do
    let(:draft_flowchart) { Flowchart.create!(valid_attributes.merge(status: :draft)) }

    it 'returns unprocessable_entity' do
      post :deactivate, params: { customer_id: customer.id, id: draft_flowchart.to_param }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'sets an alert flash' do
      post :deactivate, params: { customer_id: customer.id, id: draft_flowchart.to_param }
      expect(flash[:alert]).to eq('Flowchart is already a draft.')
    end
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb -e "POST #deactivate" --format documentation`

Expected: FAIL — unknown action `deactivate`

- [ ] **Step 5: Add before_action for new actions**

In `app/controllers/flowcharts_controller.rb`, update line 18:

```ruby
before_action :find_flowchart, only: [:show, :edit, :update, :destroy, :autosave, :copy, :trace, :versions, :restore_version, :generate_docs, :activate, :deactivate]
```

- [ ] **Step 6: Add activate action**

Add after the `generate_docs` action (around line 162):

```ruby
def activate
  if @flowchart.active?
    flash[:alert] = 'Flowchart is already active.'
    redirect_to flowchart_path(current_customer_id, @flowchart), status: :unprocessable_entity
  else
    @flowchart.update!(status: :active)
    redirect_to flowchart_path(current_customer_id, @flowchart), notice: 'Flowchart activated successfully.'
  end
end

def deactivate
  if @flowchart.draft?
    flash[:alert] = 'Flowchart is already a draft.'
    redirect_to flowchart_path(current_customer_id, @flowchart), status: :unprocessable_entity
  else
    @flowchart.update!(status: :draft)
    redirect_to flowchart_path(current_customer_id, @flowchart), notice: 'Flowchart deactivated successfully.'
  end
end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb -e "activate\|deactivate" --format documentation`

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add app/controllers/flowcharts_controller.rb spec/controllers/flowcharts_controller_spec.rb
git commit -m "$(cat <<'EOF'
feat(flowcharts): add activate and deactivate controller actions

- POST /flowcharts/:id/activate transitions draft -> active
- POST /flowcharts/:id/deactivate transitions active -> draft
- Returns 422 if already in target state
- Deleted flowcharts not accessible (default scope)

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Update Factory with Draft Trait

**Files:**
- Modify: `spec/factories/flowcharts.rb`

- [ ] **Step 1: Add draft and active traits to factory**

In `spec/factories/flowcharts.rb`, add after the `customer_specific_type` trait (around line 242):

```ruby
trait :draft do
  status { :draft }
end

trait :active_status do
  status { :active }
end
```

- [ ] **Step 2: Verify factory works**

Run: `bundle exec rails runner "puts FactoryBot.build(:flowchart, :draft).status"`

Expected: `draft`

- [ ] **Step 3: Commit**

```bash
git add spec/factories/flowcharts.rb
git commit -m "$(cat <<'EOF'
test(factories): add draft and active_status traits to flowchart factory

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Add Status Badge to Flowchart List

**Files:**
- Modify: `app/components/flowchart_list_table_component.rb`
- Modify: `app/components/flowchart_list_table_component.html.erb`

- [ ] **Step 1: Add status badge helper method**

In `app/components/flowchart_list_table_component.rb`, add after the `type_badge_variant` method:

```ruby
def status_badge_variant(flowchart)
  flowchart.active? ? :success : :default
end

def status_badge_text(flowchart)
  flowchart.active? ? 'Active' : 'Draft'
end
```

- [ ] **Step 2: Add status column to table header**

In `app/components/flowchart_list_table_component.html.erb`, add a new column header after the Type header (around line 49):

```erb
<th scope="col" class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
```

- [ ] **Step 3: Add status badge cell to table rows**

In `app/components/flowchart_list_table_component.html.erb`, add after the Type cell (around line 103, after the closing `</td>` for type):

```erb
<!-- Status -->
<td class="px-4 py-3">
  <%= render BadgeComponent.new(variant: status_badge_variant(flowchart), size: :sm) do %>
    <%= status_badge_text(flowchart) %>
  <% end %>
</td>
```

- [ ] **Step 4: Verify visually**

Run: `bundle exec rails server` and navigate to flowcharts list. Verify status badge appears.

- [ ] **Step 5: Commit**

```bash
git add app/components/flowchart_list_table_component.rb app/components/flowchart_list_table_component.html.erb
git commit -m "$(cat <<'EOF'
feat(ui): add status badge to flowchart list table

Shows Draft (gray) or Active (green) badge for each flowchart.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Update Flowchart Show Page with Status and Actions

**Files:**
- Modify: `app/views/flowcharts/show.html.erb`

- [ ] **Step 1: Add status badge to header**

In `app/views/flowcharts/show.html.erb`, update the header section (around line 13-14) to include status badge:

```erb
<%# Header %>
<header class="mb-8 flex items-center justify-between">
  <div class="flex items-center gap-3">
    <h1 class="text-2xl font-bold text-gray-900"><%= @flowchart.name %></h1>
    <%= render BadgeComponent.new(variant: @flowchart.active? ? :success : :default, size: :md) do %>
      <%= @flowchart.active? ? 'Active' : 'Draft' %>
    <% end %>
  </div>

  <div class="flex items-center gap-2">
    <% if @flowchart.draft? %>
      <%= button_to activate_flowchart_path(current_customer_id, @flowchart),
          method: :post,
          class: "inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-white bg-green-600 border border-green-600 rounded-lg transition-all hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-600" do %>
        <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        Activate
      <% end %>
    <% else %>
      <%= button_to deactivate_flowchart_path(current_customer_id, @flowchart),
          method: :post,
          data: { turbo_confirm: "Deactivating will allow editing but may break pages that reference this flowchart. Continue?" },
          class: "inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg transition-all hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500" do %>
        <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
        </svg>
        Deactivate
      <% end %>
    <% end %>

    <%= link_to edit_flowchart_path(current_customer_id, @flowchart), class: "inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-white bg-indigo-600 border border-indigo-600 rounded-lg transition-all hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-600 #{@flowchart.active? ? 'opacity-50 cursor-not-allowed pointer-events-none' : ''}" do %>
      <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
      </svg>
      Edit
    <% end %>

    <%= button_to flowchart_path(current_customer_id, @flowchart),
        method: :delete,
        data: { turbo_confirm: "Are you sure you want to delete this flowchart?" },
        class: "inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-white bg-red-600 border border-red-600 rounded-lg transition-all hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-600" do %>
      <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
      </svg>
      Delete
    <% end %>
  </div>
</header>
```

- [ ] **Step 2: Verify visually**

Run: `bundle exec rails server` and navigate to a flowchart show page. Verify:
- Status badge appears next to name
- Activate button appears for draft flowcharts
- Deactivate button appears for active flowcharts
- Edit button is disabled for active flowcharts

- [ ] **Step 3: Commit**

```bash
git add app/views/flowcharts/show.html.erb
git commit -m "$(cat <<'EOF'
feat(ui): add status badge and activate/deactivate buttons to flowchart show

- Status badge next to flowchart name
- Activate button for draft flowcharts
- Deactivate button with confirmation for active flowcharts
- Edit button disabled for active flowcharts

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Update Editor with Read-Only Mode

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js`
- Modify: `app/javascript/controllers/toolbar_controller.js`

- [ ] **Step 1: Pass read-only flag to editor**

In `app/views/flowcharts/_editor.html.erb`, add a new data attribute on line 9 (after `flowchart-type-value`):

```erb
data-flowchart-canvas-read-only-value="<%= @flowchart.active? %>"
```

- [ ] **Step 2: Add read-only banner**

In `app/views/flowcharts/_editor.html.erb`, add after the opening `<div class="h-full flex flex-col"` and before the toolbar (around line 10):

```erb
<% if @flowchart.active? %>
  <div class="bg-amber-50 border-b border-amber-200 px-4 py-2 flex items-center justify-between">
    <div class="flex items-center gap-2">
      <svg class="w-5 h-5 text-amber-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
      </svg>
      <span class="text-sm font-medium text-amber-800">This flowchart is active and cannot be edited. Deactivate to make changes.</span>
    </div>
    <%= button_to deactivate_flowchart_path(current_customer_id, @flowchart),
        method: :post,
        data: { turbo_confirm: "Deactivating will allow editing but may break pages that reference this flowchart. Continue?" },
        class: "inline-flex items-center px-3 py-1.5 text-xs font-medium text-amber-700 bg-amber-100 border border-amber-300 rounded-md hover:bg-amber-200 transition-colors" do %>
      Deactivate to Edit
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 3: Add read-only value to canvas controller**

In `app/javascript/controllers/flowchart_canvas_controller.js`, add to the static values object:

```javascript
readOnly: { type: Boolean, default: false }
```

- [ ] **Step 4: Respect read-only in canvas interactions**

In `app/javascript/controllers/flowchart_canvas_controller.js`, find the method that handles element dragging/creation and add at the start:

```javascript
if (this.readOnlyValue) return
```

Add this check to these methods:
- `addElement` (or equivalent element creation method)
- `deleteElement` (or equivalent)
- `startDragging` (or equivalent drag method)
- Any method that modifies the flowchart

- [ ] **Step 5: Update toolbar to disable save for active flowcharts**

In `app/javascript/controllers/toolbar_controller.js`, add a static value:

```javascript
static values = {
  readOnly: { type: Boolean, default: false }
}
```

Then in the `save` method (around line 89), add at the start:

```javascript
if (this.readOnlyValue) {
  this._showNotification("Cannot save an active flowchart. Deactivate first.", "error")
  return
}
```

- [ ] **Step 6: Pass read-only to toolbar**

In `app/views/flowcharts/_editor.html.erb`, update the toolbar div (around line 12) to include:

```erb
data-toolbar-read-only-value="<%= @flowchart.active? %>"
```

- [ ] **Step 7: Verify visually**

Run the server and test:
1. Open a draft flowchart editor — should be editable
2. Activate the flowchart
3. Open the editor again — should show read-only banner, save should be blocked

- [ ] **Step 8: Commit**

```bash
git add app/views/flowcharts/_editor.html.erb app/javascript/controllers/flowchart_canvas_controller.js app/javascript/controllers/toolbar_controller.js
git commit -m "$(cat <<'EOF'
feat(ui): add read-only mode to flowchart editor for active flowcharts

- Show warning banner with deactivate button
- Block save action with error notification
- Pass readOnly value to canvas and toolbar controllers

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Update Pages Controller to Use Referenceable Scope

**Files:**
- Modify: `app/controllers/pages_controller.rb:121`
- Modify: `app/controllers/pages_controller.rb:347`
- Modify: `app/controllers/pages_controller.rb:357`

- [ ] **Step 1: Update flowchart queries in pages controller**

In `app/controllers/pages_controller.rb`, update line 121:

From:
```ruby
@flowcharts = Flowchart.accessible.recent
```

To:
```ruby
@flowcharts = Flowchart.accessible.referenceable.recent
```

Update `load_entity_options` method (around line 347):

From:
```ruby
@flowcharts_with_entities = Flowchart.for_current_customer
                                     .where.not(entity_id: nil)
                                     .includes(:entity)
                                     .order(:name)
```

To:
```ruby
@flowcharts_with_entities = Flowchart.for_current_customer
                                     .referenceable
                                     .where.not(entity_id: nil)
                                     .includes(:entity)
                                     .order(:name)
```

Update `load_flows_for_page` method (around line 357):

From:
```ruby
@entity_flows = if entity_id.present?
                  Flowchart.for_current_customer
                           .where(entity_id: entity_id)
                           .active
                else
                  []
                end
```

To:
```ruby
@entity_flows = if entity_id.present?
                  Flowchart.for_current_customer
                           .referenceable
                           .where(entity_id: entity_id)
                else
                  []
                end
```

Note: `.active` was already being used here but `.referenceable` is more semantic.

- [ ] **Step 2: Verify behavior**

Create a draft flowchart and an active flowchart, then verify only the active one appears in page flowchart dropdowns.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/pages_controller.rb
git commit -m "$(cat <<'EOF'
feat(pages): use referenceable scope for flowchart dropdowns

Only active flowcharts appear in flowchart selection dropdowns
when creating or editing pages.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Update Existing Controller Specs for Default Draft Status

**Files:**
- Modify: `spec/controllers/flowcharts_controller_spec.rb`

- [ ] **Step 1: Update specs that expect active default**

In `spec/controllers/flowcharts_controller_spec.rb`, the existing specs create flowcharts that will now default to draft. Update the `let(:flowchart)` definition (around line 43) and any specs that check status:

The `let(:flowchart)` should explicitly set status if needed:
```ruby
let(:flowchart) { Flowchart.create!(valid_attributes.merge(status: :draft)) }
```

Or for tests that need active:
```ruby
let(:active_flowchart) { Flowchart.create!(valid_attributes.merge(status: :active)) }
```

Update the destroy spec that checks status changes to deleted (around line 237):
```ruby
it 'changes the flowchart status to deleted' do
  flowchart = Flowchart.create!(valid_attributes.merge(status: :draft))
  delete :destroy, params: { customer_id: customer.id, id: flowchart.to_param }
  expect(flowchart.reload.status).to eq('deleted')
end
```

- [ ] **Step 2: Run full controller spec**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb --format documentation`

Expected: PASS (all tests green)

- [ ] **Step 3: Commit**

```bash
git add spec/controllers/flowcharts_controller_spec.rb
git commit -m "$(cat <<'EOF'
test(flowcharts): update controller specs for draft default status

Explicitly set status in specs that depend on specific states.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Run Full Test Suite and Fix Any Regressions

**Files:**
- Various spec files as needed

- [ ] **Step 1: Run model specs**

Run: `bundle exec rspec spec/models/flowchart_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 2: Run controller specs**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 3: Run related specs**

Run: `bundle exec rspec spec/models/flowchart_version_spec.rb spec/components/flowchart_info_card_component_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 4: Fix any failures**

If any specs fail due to the new default status, update them to explicitly set the status they need.

- [ ] **Step 5: Final commit if fixes needed**

```bash
git add -A
git commit -m "$(cat <<'EOF'
test: fix specs affected by draft default status change

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

After completing all tasks:

1. **Model changes:**
   - Status enum now has `draft` (2) in addition to `active` (0) and `deleted` (1)
   - New flowcharts default to `draft`
   - `referenceable` scope returns only active flowcharts
   - Active flowcharts cannot be edited (validation blocks non-status changes)

2. **Controller changes:**
   - `POST /flowcharts/:id/activate` — transitions draft → active
   - `POST /flowcharts/:id/deactivate` — transitions active → draft

3. **UI changes:**
   - Flowchart list shows status badge (Draft/Active)
   - Flowchart show page has status badge and activate/deactivate buttons
   - Editor shows read-only banner for active flowcharts
   - Save is blocked for active flowcharts

4. **Integration:**
   - Page flowchart dropdowns only show active flowcharts
