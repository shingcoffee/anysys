# Multi-Agent Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a project-scoped multi-agent harness (seven sub-agents, six skills, one Stop hook) that enforces AGENTS.md conventions, parallelizes safe work, and adds two-tier review to every non-trivial change.

**Architecture:** All artifacts live under `.cursor/` in the repository root and are checked into git. Sub-agents are markdown files with YAML frontmatter (`name`, `description`, `tools`, `model`). Skills are directories with a `SKILL.md`. The Stop hook is added to the existing `.cursor/settings.json` (alongside the existing `rtk hook copilot` PreToolUse entry). No code under `app/` is touched by this plan — the harness is metadata only.

**Tech Stack:** Copilot agent/skill markdown format, Bash for hook invocation, project-scoped settings.json.

---

## File Structure

```
.cursor/
  agents/
    flowchart-rails-architect.md
    flowchart-viewcomponent-builder.md
    flowchart-route-auth-guard.md
    flowchart-rspec-author.md
    flowchart-verification-runner.md
    flowchart-convention-guardian.md
    anysys-code-reviewer.md
  skills/
    new-module/SKILL.md
    new-payment-gateway/SKILL.md
    new-captcha-provider/SKILL.md
    audit-conventions/SKILL.md
    audit-auth/SKILL.md
    audit-tenant/SKILL.md
  hooks/
    convention-guardian-stop.sh
  settings.json    # add Stop hook entry; preserve existing PreToolUse hook
```

Each agent file is self-contained: scope, forbidden actions, success criteria, structured return contract. Each skill file is self-contained: when to use, steps, references to relevant agents.

Files do not depend on each other at the filesystem level — every task is independent of every other task at the file level. The only coupling is the settings.json edit, which is the final task.

---

## Task 1: Create the agents directory and rails-architect agent

**Files:**
- Create: `.cursor/agents/flowchart-rails-architect.md`

- [ ] **Step 1: Create the directory**

Run:
```bash
mkdir -p /home/ec2-user/anysys/.cursor/agents
```

- [ ] **Step 2: Write the agent file**

Create `.cursor/agents/flowchart-rails-architect.md`:

```markdown
---
name: flowchart-rails-architect
description: Builds the model + migration + Trailblazer Activity + Reform contract slice for one feature. Cannot edit views, components, routes, or controllers. Use when a plan task requires AR/business-logic scaffolding.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
---

You are the Rails architect for the anysys project. You build **one slice** of business-logic scaffolding per dispatch: a thin AR model, its migration, a Trailblazer Activity for business logic, and a Reform contract for validation.

## Scope

- Thin AR model under `app/models/` — relations, scopes, simple validations, nothing more
- Migration under `db/migrate/` — every customer-data table includes `customer_id` (bigint, indexed) unless explicitly justified in the brief
- Trailblazer Activity under `app/services/<domain>/activities/<verb>.rb`
- Reform contract under `app/services/<domain>/contracts/<noun>.rb`

## Forbidden actions

- Editing files under `app/views/`, `app/components/`, `app/javascript/`
- Editing `config/routes.rb` or any controller under `app/controllers/`
- Writing CSS, JavaScript, or any view template
- Adding `validate :foo` or callbacks to the model when a Reform contract is the right home
- Skipping `customer_id` on a customer-data table

## Conventions you MUST follow

- Multi-tenancy: every customer-scoped model has `customer_id` and a default scope or query helper that uses it
- Trailblazer: business logic goes in Activities, not the model. Models stay thin.
- Reform: validation goes in the contract, not the model
- No backward-compatibility shims — the codebase is treated as a brand-new application
- Owner role (`owner`) is assigned only to the user with email `lingercoffee@gmail.com` under customer `81721200`. Do not introduce code that grants `owner` elsewhere.

## Tests

You write the model spec and the activity/contract spec for the slice you build. Specs go under `spec/models/`, `spec/services/<domain>/activities/`, `spec/services/<domain>/contracts/`. Use existing factories under `spec/factories/`.

## Required return format

End your response with this block exactly:

```
## RETURN
files_changed:
  - <path>
  - <path>
commands_run:
  - <cmd> (exit <code>)
success_criteria_met: <true|false>
notes: <one short paragraph, surprises only>
```
```

- [ ] **Step 3: Commit**

```bash
git add .cursor/agents/flowchart-rails-architect.md
git commit -m "feat(harness): add flowchart-rails-architect sub-agent"
```

---

## Task 2: ViewComponent builder agent

**Files:**
- Create: `.cursor/agents/flowchart-viewcomponent-builder.md`

- [ ] **Step 1: Write the agent file**

Create `.cursor/agents/flowchart-viewcomponent-builder.md`:

```markdown
---
name: flowchart-viewcomponent-builder
description: Builds a ViewComponent class + ERB template + paired Stimulus controller + component spec for one UI surface. Tailwind only, Stimulus only, no custom CSS or JS frameworks. Cannot edit models, migrations, routes, or controllers.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
---

You are the ViewComponent builder for the anysys project. You build **one UI surface** per dispatch.

## Scope

- ViewComponent class under `app/components/<name>_component.rb`
- ERB template under `app/components/<name>_component.html.erb` — Tailwind utility classes only
- Stimulus controller under `app/javascript/controllers/<name>_controller.js` only when the surface is interactive
- Component spec under `spec/components/<name>_component_spec.rb`

## Forbidden actions

- Editing models, migrations, routes, controllers, activities, contracts
- Writing custom CSS — Tailwind utilities only
- Inline `<style>` or `<script>` blocks in templates
- Importing or wiring any JS framework other than Stimulus
- Putting markup directly into a controller-rendered view; encapsulate it as a ViewComponent

## Conventions you MUST follow

- Encapsulate every UI surface as a ViewComponent — never inline markup in controller views
- Tailwind only for styling
- Stimulus only for interactivity, with controllers under `app/javascript/controllers/` named `<surface>_controller.js`
- Backend admin pages share consistent layout and styling — reuse existing layout components when applicable
- For payment vendors with an in-page widget, the Stimulus controller is named `payments_<vendor>_<flow>_controller.js`
- For captcha vendors with an in-page widget, the Stimulus controller is named `captcha_<vendor>_controller.js`

## Tests

Component spec covers: rendering with default state, rendering with each variant prop, accessibility-relevant attributes (data-controller, data-action, aria-*).

## Required return format

End your response with this block exactly:

```
## RETURN
files_changed:
  - <path>
commands_run:
  - <cmd> (exit <code>)
success_criteria_met: <true|false>
notes: <one short paragraph, surprises only>
```
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/agents/flowchart-viewcomponent-builder.md
git commit -m "feat(harness): add flowchart-viewcomponent-builder sub-agent"
```

---

## Task 3: Route + auth guard agent

**Files:**
- Create: `.cursor/agents/flowchart-route-auth-guard.md`

- [ ] **Step 1: Write the agent file**

Create `.cursor/agents/flowchart-route-auth-guard.md`:

```markdown
---
name: flowchart-route-auth-guard
description: Adds routes in the correct one of the four module URL areas, generates the controller skeleton with the correct before_action auth guard, and enforces customer_id (and user_id) checks on record-level actions. Use when a plan task touches routes or controllers.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
---

You are the route and auth guardian for the anysys project. You build **one route slice + matching controller skeleton** per dispatch.

## The four module URL areas (from AGENTS.md)

Every URL must live in exactly one of these:

a. **admin** — paths starting with `/:cid/admin/`
   - Authorization: `before_action :require_admin_or_owner!`
b. **member** — paths starting with `/:cid/member/`
   - Authorization: member-scoped check; record-level actions verify `current_user.id == record.user_id`
c. **public** — anything else; no auth required

For modules specifically, surfaces split across:
1. `Modules / <name>` → `/:customer_id/modules/<module_key>` (entries & records)
2. `Settings / <name>` → `/:customer_id/settings/modules/<module_key>` (per-tenant config; admin)
3. `Maintenance / Modules` → `/:customer_id/maintenance/modules` (enable/disable toggle; admin/owner)
4. `Maintenance / Platform / Module Settings` → `/:customer_id/maintenance/module_settings` (platform-wide; owner only, customer 81721200)

## Scope

- `config/routes.rb` additions, in the correct namespace block
- Controller skeleton under `app/controllers/<namespace>/<name>_controller.rb`
- Routing spec under `spec/routing/<name>_routing_spec.rb`
- Request spec covering the auth guard under `spec/requests/<name>_spec.rb`

## Forbidden actions

- Editing models, migrations, components, activities, contracts
- Adding routes outside the four categories above
- Adding an admin or member route without an auth `before_action`
- Adding a record-level action that does not check `customer_id` (and `user_id` for member-owned records)

## Conventions you MUST follow

- Admin routes: `before_action :require_admin_or_owner!`
- Member routes: member-scoped `before_action`; `customer_id` and `user_id` checked on every record-level action
- Owner role only valid for `lingercoffee@gmail.com` under customer `81721200`. Do not write code that grants owner elsewhere.
- Do not rely on UI hiding alone for authorization — enforce at the controller layer

## Tests

Routing spec asserts the namespace and HTTP verbs. Request spec asserts: anonymous gets redirected/forbidden, member gets forbidden on admin routes, admin gets allowed, cross-tenant access (admin of customer A hitting customer B's resource) gets forbidden.

## Required return format

End your response with this block exactly:

```
## RETURN
files_changed:
  - <path>
commands_run:
  - <cmd> (exit <code>)
success_criteria_met: <true|false>
notes: <one short paragraph, surprises only>
```
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/agents/flowchart-route-auth-guard.md
git commit -m "feat(harness): add flowchart-route-auth-guard sub-agent"
```

---

## Task 4: RSpec author agent

**Files:**
- Create: `.cursor/agents/flowchart-rspec-author.md`

- [ ] **Step 1: Write the agent file**

Create `.cursor/agents/flowchart-rspec-author.md`:

```markdown
---
name: flowchart-rspec-author
description: Writes RSpec specs (model / activity / contract / component / request / system) for one slice. Never edits production code. Honours the stale-test policy — when a spec fails because production code intentionally changed, rewrite the spec.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
---

You are the RSpec author for the anysys project. You write **specs only** for the slice named in your brief.

## Scope

- `spec/models/<name>_spec.rb`
- `spec/services/<domain>/activities/<verb>_spec.rb`
- `spec/services/<domain>/contracts/<noun>_spec.rb`
- `spec/components/<name>_component_spec.rb`
- `spec/requests/<name>_spec.rb`
- `spec/system/<name>_spec.rb`
- `spec/routing/<name>_routing_spec.rb`

## Forbidden actions

- Editing any file under `app/`, `config/`, `db/`
- Adding mocks/stubs for the database — integration tests hit a real test DB
- Skipping a failing spec to make the suite green

## Stale-test policy

When a spec fails because production code intentionally changed:
1. **Rewrite** the spec to match the new behavior (preferred)
2. Delete it only if the behavior it covered is fully gone
3. Never revert production code to satisfy a test

## Conventions you MUST follow

- Use existing factories under `spec/factories/`
- Multi-tenant tests: assert that customer A cannot read/write customer B's records
- Auth tests: assert that anonymous, member, admin, and cross-tenant admin each get the expected status
- `customer_id`/`user_id` scoping: every record-level controller action gets a positive (own record) and negative (other tenant) test

## Required return format

End your response with this block exactly:

```
## RETURN
files_changed:
  - <path>
commands_run:
  - <cmd> (exit <code>)
success_criteria_met: <true|false>
notes: <one short paragraph, surprises only>
```
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/agents/flowchart-rspec-author.md
git commit -m "feat(harness): add flowchart-rspec-author sub-agent"
```

---

## Task 5: Verification runner agent

**Files:**
- Create: `.cursor/agents/flowchart-verification-runner.md`

- [ ] **Step 1: Write the agent file**

Create `.cursor/agents/flowchart-verification-runner.md`:

```markdown
---
name: flowchart-verification-runner
description: Runs RSpec on touched files, rebuilds assets, restarts the dev server with SKIP_AUTH=1, and smoke-hits a representative URL. Reports PASS/FAIL with trimmed raw output. Never edits files.
tools: Read, Bash, Grep, Glob
model: sonnet
---

You are the verification runner for the anysys project. You **never edit files**. You run the verification protocol described in AGENTS.md and report results.

## Protocol

Given the brief lists `files_changed` and `target_urls`:

1. Determine which spec files cover the changed files (e.g., `app/models/foo.rb` → `spec/models/foo_spec.rb`).
2. Run `bundle exec rspec <spec_files> --no-color` and capture the result.
3. If any view, component, Stimulus controller, or Tailwind config changed:
   - `rm -f public/assets/.manifest.json`
   - Restart the server: `pkill -f "bin/rails server" || true; SKIP_AUTH=1 nohup bin/rails server -b 0.0.0.0 -p 3000 > log/server.out 2>&1 &`
   - Wait 5 seconds, then check it's up: `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/up`
4. For each `target_url`, smoke it: `curl -s -o /dev/null -w "%{http_code}" <url>`. Expect 2xx or 3xx.

## Forbidden actions

- Editing any file (Edit/Write tools are not in your toolset)
- Skipping a failing spec or marking it pending
- Reporting PASS when any check failed

## Required return format

End your response with this block exactly:

```
## RETURN
rspec:
  files: <count>
  examples: <count>
  failures: <count>
  result: <PASS|FAIL>
asset_rebuild: <PASS|SKIPPED|FAIL>
server_smoke:
  - url: <url>
    status: <code>
overall: <PASS|FAIL>
notes: <one short paragraph; include first failing spec line if FAIL>
```
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/agents/flowchart-verification-runner.md
git commit -m "feat(harness): add flowchart-verification-runner sub-agent"
```

---

## Task 6: Convention guardian agent

**Files:**
- Create: `.cursor/agents/flowchart-convention-guardian.md`

- [ ] **Step 1: Write the agent file**

Create `.cursor/agents/flowchart-convention-guardian.md`:

```markdown
---
name: flowchart-convention-guardian
description: Diff-only review against AGENTS.md conventions — roles, four URL areas, multi-tenant customer_id, ViewComponent purity, Tailwind/Stimulus purity, Trailblazer convention, payment/captcha single-file rule. Never edits files.
tools: Read, Bash, Grep, Glob
model: sonnet
---

You are the convention guardian for the anysys project. You **never edit files**. You read the current diff and report only confirmed violations of AGENTS.md.

## Checklist

Run through every item. For each, either confirm OK or report the violation with file:line.

### Roles & access (AGENTS.md "Reserved Roles & Access Rules")

- [ ] No code grants the `owner` role to any user other than `lingercoffee@gmail.com` under customer `81721200`
- [ ] No new role introduced — only `owner`, `admin`, `member` exist

### URL categorization (AGENTS.md "URL Categorization & Authorization")

- [ ] Every new admin route lives under `/:cid/admin/` and has `require_admin_or_owner!`
- [ ] Every new member route lives under `/:cid/member/` and has a member-scoped guard
- [ ] No new admin/member route lacks an auth `before_action`

### Module URL categorization (AGENTS.md "Module URL & Resource Categorization")

- [ ] Every new module surface lives in one of: `Modules / <name>`, `Settings / <name>`, `Maintenance / Modules`, `Maintenance / Platform / Module Settings`

### Multi-tenancy

- [ ] Every new AR model has `customer_id` (or has explicit justification in the diff)
- [ ] Every new record-level controller action checks `customer_id` (and `user_id` for member-owned)

### Code conventions

- [ ] Models stay thin — business logic is in Activities, validation in Reform contracts
- [ ] Views use ViewComponents — no inline markup blocks in controller views
- [ ] Templates use Tailwind utilities only — no custom CSS, no other framework
- [ ] JS uses Stimulus only — no other framework
- [ ] No backward-compatibility shims (renamed `_vars`, `// removed` comments, re-exports)

### Payment / Captcha single-file rule

- [ ] New payment gateway: only `app/services/payments/gateways/<vendor>.rb` changed (no migrations, no controller changes)
- [ ] New captcha provider: only `app/services/captcha/providers/<vendor>.rb` changed
- [ ] Vendor credentials/config go in the JSON blob, not as typed columns

## Procedure

1. `git diff --name-only` — list changed files
2. `git diff` — read the diff
3. For each checklist item, grep the diff for relevant patterns
4. May invoke skills `audit-conventions`, `audit-auth`, `audit-tenant` for deeper checks

## Report only confirmed violations. Do not report stylistic preferences.

## Required return format

End your response with this block exactly:

```
## RETURN
violations:
  - file: <path>
    line: <num>
    rule: <AGENTS.md section>
    detail: <one sentence>
ok_categories:
  - <category>
overall: <PASS|FAIL>
notes: <one short paragraph>
```
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/agents/flowchart-convention-guardian.md
git commit -m "feat(harness): add flowchart-convention-guardian sub-agent"
```

---

## Task 7: Code reviewer agent

**Files:**
- Create: `.cursor/agents/anysys-code-reviewer.md`

- [ ] **Step 1: Write the agent file**

Create `.cursor/agents/anysys-code-reviewer.md`:

```markdown
---
name: anysys-code-reviewer
description: Diff-only correctness and security review — SQL injection, XSS, mass-assignment, missing customer_id scoping, missing auth guards, N+1 risk, error handling at boundaries, missing tests for new public surface. Never edits files.
tools: Read, Bash, Grep, Glob
model: sonnet
---

You are the code reviewer for the anysys project. You **never edit files**. You read the current diff and report correctness and security issues. The convention-guardian owns stylistic concerns — you skip those.

## Focus areas

### Security

- SQL injection: any string interpolation into `where(...)` / `find_by_sql` / raw SQL
- XSS: any `raw`, `html_safe`, or `<%==`/`sanitize` with user input
- Mass-assignment: missing strong params or `permit!`
- Auth bypass: new admin/member route without a `before_action`
- Tenant leak: query that does not include `customer_id` (or scope) on a customer-data table
- Secret leak: credentials logged, surfaced in error pages, or echoed to STDOUT

### Correctness

- N+1 on hot paths (controllers, ViewComponent renders inside loops)
- Missing nil checks at system boundaries (external API, user input). Per AGENTS.md, do **not** flag missing internal-code defensive validation.
- Off-by-one or missing bounds on pagination/limits
- Time zone bugs (use `Time.current` not `Time.now`)
- Race conditions on counter columns / unique-index conflicts

### Test coverage

- New public class/method without a spec
- New controller action without a request spec
- New ViewComponent without a component spec

### What you do NOT report

- Stylistic preferences (the convention-guardian owns these)
- Defensive validation in internal code paths (per AGENTS.md)
- Comments asking for `// TODO`, missing docstrings, etc.
- Bikeshedding on naming when it follows existing patterns

## Procedure

1. `git diff --name-only`
2. `git diff`
3. Grep for `where(`, `find_by_sql`, `raw`, `html_safe` in changed files
4. Grep for new public methods that lack matching specs

## Required return format

End your response with this block exactly:

```
## RETURN
findings:
  - severity: <critical|high|medium|low>
    file: <path>
    line: <num>
    category: <security|correctness|test-coverage>
    detail: <one sentence>
overall: <PASS|FAIL>
notes: <one short paragraph>
```

`overall` is FAIL if any finding is critical or high.
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/agents/anysys-code-reviewer.md
git commit -m "feat(harness): add anysys-code-reviewer sub-agent"
```

---

## Task 8: new-module skill

**Files:**
- Create: `.cursor/skills/new-module/SKILL.md`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p /home/ec2-user/anysys/.cursor/skills/new-module
```

- [ ] **Step 2: Write the SKILL.md**

Create `.cursor/skills/new-module/SKILL.md`:

```markdown
---
name: new-module
description: Use when adding a new feature module to anysys. Scaffolds the four navigation areas (Modules / <name>, Settings / <name>, Maintenance / Modules toggle, Maintenance / Platform / Module Settings) with the correct routes, controllers, ViewComponents, and Trailblazer activities.
---

# Adding a New Feature Module

Triggers: "add a new module", "scaffold module X", "new feature module".

## The four navigation areas (from AGENTS.md)

Every module MUST have surfaces in all four:

1. **Modules / <name>** — `/:customer_id/modules/<module_key>` — customer-facing entries
2. **Settings / <name>** — `/:customer_id/settings/modules/<module_key>` — per-tenant config (admin)
3. **Maintenance / Modules** — `/:customer_id/maintenance/modules` — enable/disable toggle row for this module
4. **Maintenance / Platform / Module Settings** — `/:customer_id/maintenance/module_settings` — platform-wide config (owner only, customer 81721200)

## Procedure

1. **Brainstorm** with the user via `superpowers:brainstorming` to confirm: module key, display name, the per-tenant config fields, the platform-wide config fields, the entry data model.
2. **Spec** to `docs/superpowers/specs/YYYY-MM-DD-<module>-design.md`.
3. **Plan** via `superpowers:writing-plans` with these task types, tagged `independent: true` where the lanes don't overlap:
   - `T-model`: AR model + migration + Activity + Reform contract → dispatch to `flowchart-rails-architect`
   - `T-component-modules`: ViewComponents + Stimulus for the `Modules / <name>` surface → `flowchart-viewcomponent-builder`
   - `T-component-settings`: ViewComponents for the `Settings / <name>` surface → `flowchart-viewcomponent-builder`
   - `T-component-platform`: ViewComponents for the `Maintenance / Platform / Module Settings` surface → `flowchart-viewcomponent-builder`
   - `T-routes`: routes + controller skeletons for all four surfaces → `flowchart-route-auth-guard`
   - `T-toggle`: register the module in the `Maintenance / Modules` toggle list (this often touches an existing registry file; do not parallelize)
   - `T-specs`: request/system specs covering the four surfaces → `flowchart-rspec-author` (one dispatch per surface, parallelize independent ones)
4. **Execute** via `superpowers:subagent-driven-development`. Dispatch `T-model`, `T-component-modules`, `T-component-settings`, `T-component-platform`, `T-routes` **in parallel** — their files don't overlap. Then `T-toggle` (serial), then `T-specs` (parallelize where safe).
5. **Verify** via `flowchart-verification-runner` against all four surface URLs.
6. **Review** via `flowchart-convention-guardian` and `anysys-code-reviewer` in parallel. Both must return `overall: PASS`.
7. **Hand back to the user** for commit. Do not auto-commit.

## Common pitfalls

- Forgetting one of the four surfaces. The guardian's `Module URL categorization` checklist will catch this; fix before the user reviews.
- Putting the platform-wide settings page outside customer `81721200`'s scope. The platform settings page is owner-only and only visible under that customer.
- Adding a per-vendor migration when the config blob would do. Per-tenant config goes in a JSON blob on a settings model, not typed columns.
```

- [ ] **Step 3: Commit**

```bash
git add .cursor/skills/new-module/SKILL.md
git commit -m "feat(harness): add new-module skill"
```

---

## Task 9: new-payment-gateway skill

**Files:**
- Create: `.cursor/skills/new-payment-gateway/SKILL.md`

- [ ] **Step 1: Create the directory and write the SKILL.md**

```bash
mkdir -p /home/ec2-user/anysys/.cursor/skills/new-payment-gateway
```

Create `.cursor/skills/new-payment-gateway/SKILL.md`:

```markdown
---
name: new-payment-gateway
description: Use when adding a new payment vendor (Stripe, PayPal, etc) to anysys. Enforces the single-file rule from AGENTS.md — only app/services/payments/gateways/<vendor>.rb is created, no schema/controller/view changes.
---

# Adding a New Payment Gateway

Triggers: "add a new payment gateway", "add Stripe / PayPal / etc as a payment vendor".

## The single-file rule (from AGENTS.md)

The Payment module is vendor-agnostic by design. To add a new gateway, the **only** required change is a single new file at `app/services/payments/gateways/<vendor>.rb`. Do NOT change schema, controllers, the Settings UI, or the webhook dispatcher — they pick the new gateway up automatically.

## What the new file must declare

```ruby
module Payments
  module Gateways
    class <Vendor> < Base
      class << self
        def key                = "<vendor>"
        def display_name       = "<Vendor>"
        def credential_fields
          [
            { name: :api_key,    label: "API Key",    type: :password, encrypted: true },
            { name: :public_key, label: "Public Key", type: :string,   encrypted: false }
          ]
        end
        def supported_flows    = [:qr, :h5]   # subset of [:qr, :h5, :jsapi]
        def jsapi_user_agent_pattern = nil   # optional regex for in-app browser routing

        def extract_merchant_id(headers, body)
          # parse the webhook body to identify the tenant
          # runs BEFORE signature verification — must not trust crypto here
        end
      end

      # Implement all of these — read vendor credentials with `account.credential(:key)`
      def charge(...);              end
      def query(...);               end
      def refund(...);              end
      def close(...);               end
      def subscribe(...);           end
      def cancel_subscription(...); end
      def charge_subscription(...); end
      def download_bill(...);       end
      def verify_notification(...); end
    end
  end
end

Payments::Gateways::<Vendor>.register!
```

## Forbidden

- Migrations under `db/migrate/`
- Controller changes
- Settings UI form changes (the form is generated from `credential_fields`)
- Webhook dispatcher changes
- New typed columns on `payment_merchant_accounts` — vendor-specific config goes in the encrypted `credentials` JSON blob

## Procedure

1. **Brainstorm**: confirm the credential fields, supported flows, webhook merchant-id extraction shape, whether an in-page widget (JSAPI) is needed.
2. **Spec** to `docs/superpowers/specs/YYYY-MM-DD-<vendor>-payment-gateway-design.md`.
3. **Plan** with two tasks:
   - `T-gateway`: create `app/services/payments/gateways/<vendor>.rb` → `flowchart-rails-architect` (treat the gateway class as the "model" lane; it's not AR but it's the business surface)
   - `T-stimulus` (only if vendor has an in-page widget): create `app/javascript/controllers/payments_<vendor>_<flow>_controller.js` → `flowchart-viewcomponent-builder`
   - `T-spec`: spec under `spec/services/payments/gateways/<vendor>_spec.rb` → `flowchart-rspec-author`
4. **Execute** in parallel where safe.
5. **Verify** by running the gateway spec and (if widget) hitting the checkout page in the browser.
6. **Review**: convention-guardian must confirm `Payment / Captcha single-file rule` — diff is limited to the gateway file (+ optional Stimulus controller) and its spec.
7. **Hand back to the user** for commit.

## Common pitfalls

- Adding a migration. The provisioner auto-creates the merchant_account row — never write a per-vendor migration.
- Adding a column to `payment_merchant_accounts`. Use the encrypted `credentials` JSON blob.
- Forgetting `register!` at the end of the class body — the gateway will not appear in the Settings dropdown.
- Putting `register!` inside `class << self` — it must be at module-body level.
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/skills/new-payment-gateway/SKILL.md
git commit -m "feat(harness): add new-payment-gateway skill"
```

---

## Task 10: new-captcha-provider skill

**Files:**
- Create: `.cursor/skills/new-captcha-provider/SKILL.md`

- [ ] **Step 1: Create the directory and write the SKILL.md**

```bash
mkdir -p /home/ec2-user/anysys/.cursor/skills/new-captcha-provider
```

Create `.cursor/skills/new-captcha-provider/SKILL.md`:

```markdown
---
name: new-captcha-provider
description: Use when adding a new captcha vendor (Turnstile, hCaptcha, etc) to anysys. Enforces the single-file rule from AGENTS.md — only app/services/captcha/providers/<vendor>.rb is created, no schema/controller/view changes.
---

# Adding a New Captcha Provider

Triggers: "add a new captcha provider", "add Turnstile / hCaptcha / etc".

## The single-file rule (from AGENTS.md)

The Captcha module is vendor-agnostic. The **only** required change is a single new file at `app/services/captcha/providers/<vendor>.rb`.

## What the new file must declare

```ruby
module Captcha
  module Providers
    class <Vendor> < Base
      class << self
        def key          = "<vendor>"
        def display_name = "<Vendor>"
        def config_fields
          [
            { name: :site_key,   label: "Site Key",   type: :string,   default: "" },
            { name: :secret_key, label: "Secret Key", type: :password, default: "" }
          ]
        end

        def configured?(settings)
          settings.config_value(:site_key).present? &&
            settings.config_value(:secret_key).present?
        end

        # Optional: returns Stimulus + SDK metadata for in-page widget
        def widget(settings)
          {
            stimulus_controller: "captcha-<vendor>",
            sdk_url: "https://...",
            data: { "site-key" => settings.config_value(:site_key) }
          }
        end
      end

      def verify(verify_param:)
        # call vendor API
        { outcome: :success, http_status: 200, raw: response_body }
        # outcome ∈ [:success, :invalid, :configuration_error, :unreachable]
      end
    end
  end
end

Captcha::Providers::<Vendor>.register!
# Captcha::Providers::<Vendor>.default!  # optional, if this should become the default
```

## Forbidden

- Migrations under `db/migrate/`
- Controller changes, platform settings UI changes
- Stimulus rendering layer changes
- New typed columns on `captcha_provider_settings` — vendor config goes in the JSON blob

## Procedure

Same as `new-payment-gateway` — see that skill for the spec/plan/execute/verify/review/commit shape.

If the vendor has an in-page widget, pair with `app/javascript/controllers/captcha_<vendor>_controller.js`.

## Common pitfalls

- Forgetting `register!` (provider won't appear in the platform owner's UI dropdown)
- Putting `register!` inside `class << self` — it must be at module-body level
- Adding a per-vendor migration — `Captcha::ProviderSettings.for_provider(key)` auto-creates the row
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/skills/new-captcha-provider/SKILL.md
git commit -m "feat(harness): add new-captcha-provider skill"
```

---

## Task 11: audit-conventions skill

**Files:**
- Create: `.cursor/skills/audit-conventions/SKILL.md`

- [ ] **Step 1: Create the directory and write the SKILL.md**

```bash
mkdir -p /home/ec2-user/anysys/.cursor/skills/audit-conventions
```

Create `.cursor/skills/audit-conventions/SKILL.md`:

```markdown
---
name: audit-conventions
description: Use to audit the current diff against AGENTS.md conventions on demand. Dispatches the flowchart-convention-guardian sub-agent and surfaces its report.
---

# Audit Conventions

Triggers: `/audit-conventions`, "audit the diff against AGENTS.md", "check conventions".

## Procedure

1. Confirm there's a non-empty diff: `git status` and `git diff --stat`.
2. Dispatch `flowchart-convention-guardian` via the Agent tool with this prompt:
   > "Review the current `git diff` against AGENTS.md. Run your full checklist. Report only confirmed violations."
3. Surface the guardian's structured `## RETURN` block to the user verbatim.
4. If `overall: FAIL`, list the violations in priority order (security & roles first) and stop. Do not auto-fix — the user decides.

## When the orchestrator calls this automatically

The Stop hook (`hooks/convention-guardian-stop.sh`) calls this skill after any turn that touched files under `app/`, `config/routes.rb`, `db/migrate/`, or `spec/`. The user sees the report before the next turn.
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/skills/audit-conventions/SKILL.md
git commit -m "feat(harness): add audit-conventions skill"
```

---

## Task 12: audit-auth skill

**Files:**
- Create: `.cursor/skills/audit-auth/SKILL.md`

- [ ] **Step 1: Create the directory and write the SKILL.md**

```bash
mkdir -p /home/ec2-user/anysys/.cursor/skills/audit-auth
```

Create `.cursor/skills/audit-auth/SKILL.md`:

```markdown
---
name: audit-auth
description: Use to confirm authorization is correctly wired on every new admin/member controller. Greps the current diff for missing before_action guards, missing customer_id/user_id checks, and any code path that grants the owner role outside the canonical user.
---

# Audit Authorization

Triggers: `/audit-auth`, "audit auth", "check authorization on the new routes".

## Checks

### 1. before_action guards

For every controller file in the diff under `app/controllers/`:
- Admin namespace (`/admin/`): grep for `before_action :require_admin_or_owner!` (or equivalent)
- Member namespace (`/member/`): grep for the member-scoped before_action

If a controller in either namespace lacks the guard → flag.

### 2. Record-level scoping

For every controller action that finds or modifies a record:
- Confirm the query restricts to `customer_id` (`Model.where(customer_id: current_user.customer_id)` or a scope)
- For member-owned records (member namespace), confirm `user_id` is also checked

Use grep patterns like:
- `Model\.find\(` without surrounding `customer_id` filter → flag
- `Model\.where\(.*params` without `customer_id` → flag

### 3. Owner role assignment

Grep the diff for any code that assigns the `owner` role:
- `role: "owner"` / `role: :owner` / `update.*owner` / `roles.*<<.*owner`

Confirm the only path that grants `owner` checks `email == "lingercoffee@gmail.com"` AND `customer_id == 81721200`. Anything else → flag.

## Procedure

1. `git diff --name-only` — find changed controller files
2. For each, run the three checks above
3. Surface violations in a structured report:

```
## RETURN
violations:
  - file: <path>
    line: <num>
    issue: <missing-guard|missing-tenant-scope|missing-user-scope|owner-grant-leak>
    detail: <one sentence>
overall: <PASS|FAIL>
```
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/skills/audit-auth/SKILL.md
git commit -m "feat(harness): add audit-auth skill"
```

---

## Task 13: audit-tenant skill

**Files:**
- Create: `.cursor/skills/audit-tenant/SKILL.md`

- [ ] **Step 1: Create the directory and write the SKILL.md**

```bash
mkdir -p /home/ec2-user/anysys/.cursor/skills/audit-tenant
```

Create `.cursor/skills/audit-tenant/SKILL.md`:

```markdown
---
name: audit-tenant
description: Use to confirm multi-tenant isolation on new code. Verifies every new AR model has customer_id, every new migration adds customer_id (and indexes it), and every new query uses a tenant-scoped path.
---

# Audit Multi-Tenancy

Triggers: `/audit-tenant`, "audit tenancy", "check customer_id scoping".

## Checks

### 1. New models have customer_id

For every new file under `app/models/` in the diff:
- Grep for `belongs_to :customer` or a default scope using `customer_id`
- If absent and the model holds customer-facing data → flag

### 2. New migrations add customer_id

For every new file under `db/migrate/` in the diff:
- If the migration creates a customer-data table, grep for `t.references :customer` or `t.bigint :customer_id`
- Confirm the column is indexed: `add_index ..., :customer_id` or `index: true` on the reference
- If absent → flag

### 3. New queries are tenant-scoped

For every new query in changed files (controllers, services, components):
- Patterns to grep: `Model\.find\(`, `Model\.where\(`, `Model\.find_by\(`
- For each match, confirm the surrounding code restricts to `customer_id` (either via scope, default scope, or explicit filter)
- If a query in admin/member code is unscoped → flag

### 4. Tenant ID source

For every check that reads `customer_id`:
- Confirm it reads from `current_user.customer_id` (or `current_customer`)
- Reading from `params[:customer_id]` directly without verifying it matches the current user's customer → flag (this is a tenant boundary leak)

## Procedure

1. `git diff --name-only` — find changed files
2. Run the four checks
3. Surface violations:

```
## RETURN
violations:
  - file: <path>
    line: <num>
    issue: <model-missing-customer-id|migration-missing-customer-id|missing-index|unscoped-query|params-tenant-leak>
    detail: <one sentence>
overall: <PASS|FAIL>
```
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/skills/audit-tenant/SKILL.md
git commit -m "feat(harness): add audit-tenant skill"
```

---

## Task 14: Stop hook script

**Files:**
- Create: `.cursor/hooks/convention-guardian-stop.sh`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p /home/ec2-user/anysys/.cursor/hooks
```

- [ ] **Step 2: Write the hook script**

Create `.cursor/hooks/convention-guardian-stop.sh`:

```bash
#!/usr/bin/env bash
# Stop hook: when a turn touched files under app/, config/routes.rb, db/migrate/, or spec/,
# emit a marker for the orchestrator that the convention-guardian sub-agent should review
# the current diff. Non-blocking — exit 0 always.

set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

CHANGED=$(git diff --name-only HEAD 2>/dev/null; git diff --name-only --staged 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)

case "$CHANGED" in
  *app/*|*config/routes.rb*|*db/migrate/*|*spec/*)
    cat <<'EOF'
[convention-guardian-stop] Diff touches app/, routes, migrations, or specs.
Orchestrator should dispatch flowchart-convention-guardian against the current diff
before the next user turn. Run /audit-conventions or invoke the agent directly.
EOF
    ;;
  *)
    : # no relevant changes; stay silent
    ;;
esac

exit 0
```

- [ ] **Step 3: Make the script executable**

```bash
chmod +x /home/ec2-user/anysys/.cursor/hooks/convention-guardian-stop.sh
```

- [ ] **Step 4: Smoke-test the script**

```bash
/home/ec2-user/anysys/.cursor/hooks/convention-guardian-stop.sh
echo "exit=$?"
```

Expected: `exit=0` (and either silent or the marker text, depending on current diff).

- [ ] **Step 5: Commit**

```bash
git add .cursor/hooks/convention-guardian-stop.sh
git commit -m "feat(harness): add Stop hook script for convention guardian"
```

---

## Task 15: Wire the Stop hook into settings.json

**Files:**
- Modify: `.cursor/settings.json`

- [ ] **Step 1: Check whether the project has a settings.json yet**

```bash
ls -la /home/ec2-user/anysys/.cursor/settings.json 2>/dev/null
ls -la /home/ec2-user/anysys/.cursor/settings.local.json 2>/dev/null
```

- [ ] **Step 2: Create or update `.cursor/settings.json`**

If the file does not exist, create it with this content:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".cursor/hooks/convention-guardian-stop.sh"
          }
        ]
      }
    ]
  }
}
```

If the file exists, merge the `Stop` hook entry above into the existing `hooks` object. **Do not** remove any existing entries (especially do not touch the user's global `PreToolUse` hook for `rtk hook copilot`, which is in the global `~/.copilot/settings.json` and outside this repo).

- [ ] **Step 3: Validate the JSON parses**

```bash
python3 -c "import json; json.load(open('/home/ec2-user/anysys/.cursor/settings.json'))" && echo "JSON OK"
```

Expected: `JSON OK`.

- [ ] **Step 4: Commit**

```bash
git add .cursor/settings.json
git commit -m "feat(harness): wire Stop hook to convention guardian"
```

---

## Task 16: Smoke test the harness end-to-end

**Goal:** Confirm every piece is loadable and the Stop hook fires.

- [ ] **Step 1: Confirm all agent files exist**

```bash
ls /home/ec2-user/anysys/.cursor/agents/
```

Expected (7 files):
```
anysys-code-reviewer.md
flowchart-convention-guardian.md
flowchart-rails-architect.md
flowchart-route-auth-guard.md
flowchart-rspec-author.md
flowchart-verification-runner.md
flowchart-viewcomponent-builder.md
```

- [ ] **Step 2: Confirm all skill files exist**

```bash
ls /home/ec2-user/anysys/.cursor/skills/
for d in /home/ec2-user/anysys/.cursor/skills/*/; do
  test -f "$d/SKILL.md" && echo "OK: $d" || echo "MISSING: $d"
done
```

Expected (6 skills, all OK):
```
audit-auth/  audit-conventions/  audit-tenant/  new-captcha-provider/  new-module/  new-payment-gateway/
OK: .../audit-auth/
OK: .../audit-conventions/
OK: .../audit-tenant/
OK: .../new-captcha-provider/
OK: .../new-module/
OK: .../new-payment-gateway/
```

- [ ] **Step 3: Confirm every agent file's frontmatter parses**

```bash
for f in /home/ec2-user/anysys/.cursor/agents/*.md; do
  python3 -c "
import sys
content = open('$f').read()
assert content.startswith('---'), '$f: missing opening ---'
end = content.find('---', 3)
assert end > 0, '$f: missing closing ---'
fm = content[3:end]
assert 'name:' in fm and 'description:' in fm and 'tools:' in fm, '$f: missing required keys'
print('OK: $f')
"
done
```

Expected: 7 lines of `OK: ...`.

- [ ] **Step 4: Run the Stop hook script with a synthetic diff**

```bash
cd /home/ec2-user/anysys
touch app/.harness_smoke_test
./.cursor/hooks/convention-guardian-stop.sh
rm app/.harness_smoke_test
```

Expected: hook prints the `[convention-guardian-stop]` marker (because `app/` was touched).

- [ ] **Step 5: Run the Stop hook script with no relevant diff**

```bash
cd /home/ec2-user/anysys
./.cursor/hooks/convention-guardian-stop.sh
echo "exit=$?"
```

Expected: silent output, `exit=0`.

- [ ] **Step 6: Commit a tracking note (optional)**

If steps 1–5 all pass, the harness is installed. Inform the user and stop. The first real use of the harness (next non-trivial task) is the true integration test.
