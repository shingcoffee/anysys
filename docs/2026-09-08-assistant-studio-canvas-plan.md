# AI Assistant Studio canvas Implementation Plan

> Execute inline. Do not auto-commit.

**Goal:** Restyle `GET /:cid/admin/assistant` into a flush, almost borderless studio (chat + living preview) without changing capabilities or English copy.

**Architecture:** Visual-only pass on existing ViewComponents. Keep Stimulus controllers, Turbo targets, and artifact security attributes.

**Tech Stack:** Rails 8.1 ViewComponent, Tailwind, Stimulus, RSpec, Vitest.

## Global Constraints

- Tailwind only, Stimulus only, ViewComponent encapsulation
- I18n: no new hard-coded user-facing strings; English byte-identical
- Keep `data-dashboard-region="chat"` / `"overview"`, tab ids, composer id, artifact sandbox
- Do not commit unless the user asks

### Task 1: Workspace flush split

- Modify `app/components/admin/assistants/workspace_component.html.erb`
- Update `spec/components/admin/assistants/workspace_component_spec.rb` grid class assertion

### Task 2: Chat panel + messages

- Modify `app/components/speech_to_text/assistant_panel_component.html.erb`
- Modify `app/components/speech_to_text/message_component.rb`
- Update panel + request specs so `what` is empty-state only

### Task 3: Living preview pane

- Modify `app/components/speech_to_text/artifact_pane_component.html.erb`
- Keep artifact pane spec security/link assertions

### Task 4: Verify

- `bundle exec rspec` on touched component + request specs
- `npx vitest run spec/javascript/controllers/assistant_workspace_controller.test.js`
- Smoke `/81721200/admin/assistant`
