# Flowchart Status: Draft/Active Workflow

## Overview

Add draft/active workflow to flowcharts. Only active flowcharts can be referenced by other resources (pages, etc.). Only draft flowcharts can be edited.

## Status Enum

Update existing enum from `{ active: 0, deleted: 1 }` to:

```ruby
enum :status, { active: 0, deleted: 1, draft: 2 }, default: :draft
```

- Existing records remain `active` (value 0) — no data migration needed
- New flowcharts default to `draft`

## Scopes

### New scope: `referenceable`

```ruby
scope :referenceable, -> { where(status: :active) }
```

Used when other resources need to select a flowchart (dropdowns, validations).

### Existing scope: `visible`

Unchanged — returns non-deleted records (both `active` and `draft`).

## Edit Restriction

Only draft flowcharts can be edited. Active flowcharts are read-only.

**Model validation:**

```ruby
validate :must_be_draft_to_edit, on: :update

def must_be_draft_to_edit
  return if status_changed? # Allow status transitions
  return if draft?
  
  errors.add(:base, "Cannot edit an active flowchart. Deactivate it first.")
end
```

**Controller enforcement:**

Block update action for active flowcharts (except status changes via activate/deactivate).

**UI enforcement:**

- Disable save button for active flowcharts
- Hide/disable element editing controls
- Show read-only banner: "This flowchart is active and cannot be edited. Deactivate to make changes."

## API Endpoints

### Activate

```
POST /customers/:customer_id/flowcharts/:id/activate
```

- Transitions `draft` → `active`
- Returns 422 if already active or deleted
- Response: redirect to show page with flash notice

### Deactivate

```
POST /customers/:customer_id/flowcharts/:id/deactivate
```

- Transitions `active` → `draft`
- Allowed even if referenced by other resources
- Returns 422 if already draft or deleted
- Response: redirect to show page with flash notice

## Routes

```ruby
resources :flowcharts do
  member do
    post :activate
    post :deactivate
  end
end
```

## UI Changes

### Flowchart List

- Add status badge next to each flowchart name
  - Draft: gray badge "Draft"
  - Active: green badge "Active"

### Flowchart Detail/Editor

- Show status badge in header
- For draft flowcharts:
  - Show "Activate" button
  - Editing enabled
- For active flowcharts:
  - Show "Deactivate" button
  - Show read-only banner
  - Disable all editing controls (canvas interactions, property panels, save)

### Flowchart Selection Dropdowns (in Pages, etc.)

- Use `Flowchart.referenceable` scope
- Only show active flowcharts

## Affected Files

### Model
- `app/models/flowchart.rb` — enum, scopes, validation

### Controller
- `app/controllers/flowcharts_controller.rb` — activate/deactivate actions, edit restriction

### Routes
- `config/routes.rb` — member routes

### Views/Components
- Flowchart list component — status badge
- Flowchart editor toolbar — activate/deactivate buttons, read-only state
- Page flowchart selection — use referenceable scope

### JavaScript
- Canvas controller — respect read-only mode
- Toolbar controller — disable save for active flowcharts

### Specs
- `spec/models/flowchart_spec.rb` — enum, scopes, edit validation
- `spec/requests/flowcharts_spec.rb` — activate/deactivate endpoints
- Controller/feature specs for UI behavior

## Test Scenarios

1. New flowchart defaults to draft status
2. Draft flowchart can be edited and saved
3. Draft flowchart can be activated
4. Active flowchart cannot be edited (model validation fails)
5. Active flowchart can be deactivated
6. Deactivated flowchart can be edited again
7. Flowchart selection dropdowns only show active flowcharts
8. Active flowchart can be deactivated even if referenced
9. Deleted flowcharts cannot be activated or deactivated
