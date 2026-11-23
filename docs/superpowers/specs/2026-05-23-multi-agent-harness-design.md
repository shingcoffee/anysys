# Multi-Agent Harness Design

**Date:** 2026-05-23
**Status:** Draft, awaiting user review
**Owner:** Platform / DevEx

## 1. Goal

Convert the project's current single-agent vibe-coding workflow into a disciplined multi-agent collaboration model with a project-scoped harness, modeled as a small SDLC team. The harness must directly address the problems the user has surfaced:

- **Conventions drift** — AGENTS.md rules (Trailblazer activities, ViewComponent, Tailwind/Stimulus purity, multi-tenant `customer_id`, the four module URL areas, role/auth guards, payment/captcha single-file rule) silently slip when the agent is improvising.
- **Slow serial work** — large tasks (new module, new gateway, new vendor, new dashboard surface) get done one file at a time even when the work is independent.
- **Weak verification gates** — "done" is claimed before RSpec on touched files, asset rebuild, server smoke, and route/auth checks.
- **No durable spec/plan flow** — work happens in-conversation and is lost; there is no consistent artifact trail.
- **Quality of generated code** — code reviewed only by the user, after the fact.
- **Context drift / focus loss** — as the conversation grows, the agent forgets earlier decisions, loses track of constraints, and starts editing files outside its lane.

## 2. Non-goals

- No hard-blocking PreToolUse gates. Per the user's preference, enforcement is **auto-review agent gate**: a tech-lead sub-agent surfaces violations after edits but does not block tool calls.
- No new external services, no remote orchestrators. Everything is local to this repo and the user's `~/.copilot/` config.
- No backwards-compatibility shims for the existing workflow. The harness replaces it for any non-trivial task.
- No auto-commit. The user commits manually (per `feedback_no_auto_commit`).
- No PR / push automation. Work stays on `master` (per `feedback_no_pr_master_branch`).

## 3. Workflow Spine — the SDLC pipeline

Every non-trivial task — meaning anything beyond a single-file fix or a question — runs the same pipeline end-to-end. Each phase has a named team role:

```
PO → UX → brainstorm → spec → plan → parallel-where-safe build → release-eng → tech-lead + code-reviewer → user commits
```

| Phase | Role / driver | Output | Lives in |
|---|---|---|---|
| Requirements | `anysys-product-owner` | Structured brief: stories, acceptance criteria, edge cases, open questions | conversation |
| Brainstorm | `superpowers:brainstorming` | Validated design in conversation | — |
| Spec | Orchestrator | `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` | git |
| UX design (when UI changes) | `anysys-ux-designer` | `docs/superpowers/specs/YYYY-MM-DD-<topic>-ux.md` | git |
| Plan | `superpowers:writing-plans` | `docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.md` with tasks tagged `independent` or `serial` | git |
| Build (parallel lanes) | `anysys-backend-developer` ‖ `anysys-frontend-developer` ‖ `anysys-security-engineer` | Edits across `app/`, `config/`, `db/migrate/` | working tree |
| Test authoring | `anysys-qa-engineer` | Edits across `spec/` | working tree |
| Verify | `anysys-release-engineer` | RSpec + asset rebuild + server smoke report | conversation |
| Review (parallel) | `anysys-tech-lead` ‖ `anysys-code-reviewer` | Two structured reports — both must PASS | conversation |
| Commit | User | Git commit | git |

The orchestrator is the main agent and sequences the phases. Each role sub-agent does the bulk of the editing within its lane and cannot see the conversation history — it receives a self-contained brief that re-states success criteria from the plan document inline.

## 4. The Team — Sub-Agent Roster

Nine project-scoped agents, defined as `.cursor/agents/<name>.md` with frontmatter (`name`, `description`, `tools`, `model`). Each has a tight system prompt with **role**, **scope**, **forbidden actions**, **success criteria**, and a reduced toolset. Reduced toolsets are a load-bearing part of the harness — the frontend developer cannot edit `config/routes.rb` because the tool is not available to it.

### Upstream phase

| Role | Agent | Owns |
|---|---|---|
| Product Owner | `anysys-product-owner` | Requirements brief: user stories per role, acceptance criteria, edge cases, out-of-scope, open questions |
| UX Designer | `anysys-ux-designer` | UI design doc: surface inventory, layout per surface, interaction flow, component reuse map |

### Build phase

| Role | Agent | Owns | Forbidden |
|---|---|---|---|
| Backend Developer | `anysys-backend-developer` | Thin AR model, migration, Trailblazer Activity, Reform contract for one slice | Views, components, routes, controllers |
| Frontend Developer | `anysys-frontend-developer` | ViewComponent + ERB (Tailwind only) + Stimulus controller + component spec | Models, migrations, routes, controllers; custom CSS or non-Stimulus JS |
| Security Engineer | `anysys-security-engineer` | Routes in the four URL areas + controller skeleton with `before_action` auth guards + `customer_id`/`user_id` scoping | Models, components, activities |

### Test phase

| Role | Agent | Owns | Forbidden |
|---|---|---|---|
| QA Engineer | `anysys-qa-engineer` | Specs (model / activity / contract / component / request / system / routing); cross-tenant + auth-matrix coverage; happy-path system specs | Editing any production code |

### Verify & review phase

| Role | Agent | Owns | Forbidden |
|---|---|---|---|
| Release Engineer | `anysys-release-engineer` | Run RSpec on touched files, rebuild assets after deleting `public/assets/.manifest.json`, restart dev server with `SKIP_AUTH=1`, smoke target URLs | Editing any file |
| Tech Lead | `anysys-tech-lead` | Diff-only review against AGENTS.md: roles, four URL areas, multi-tenancy, ViewComponent / Tailwind / Stimulus purity, Trailblazer convention, payment/captcha single-file rule | Editing any file |
| Code Reviewer | `anysys-code-reviewer` | Diff-only correctness/security review: SQL injection, XSS, mass-assignment, missing `customer_id` scoping, missing auth guards, N+1, error handling at boundaries, missing tests for new public surface area | Editing any file. Stylistic nits (tech-lead owns those). |

### Parallelism map

For a typical "new module slice" task:

| Phase | Roles | Mode |
|---|---|---|
| Requirements | PO | serial |
| UX | UX Designer | serial |
| Build | Backend Dev ‖ Frontend Dev ‖ Security Eng | **parallel** — file lanes don't overlap |
| Test | QA Eng (per surface) | parallel where independent |
| Verify | Release Eng | serial |
| Review | Tech Lead ‖ Code Reviewer | **parallel** — both must PASS |

## 5. Project Skills

Six skills under `.cursor/skills/<name>/SKILL.md`. Skills 5.1–5.3 drive the full SDLC pipeline for the most common tasks; skills 5.4–5.6 are on-demand audits.

### 5.1 new-module
Drives the full PO → UX → brainstorm → spec → plan → parallel build → QA → release-eng → tech-lead + code-reviewer pipeline. Scaffolds all four navigation areas: `Modules / <name>`, `Settings / <name>`, `Maintenance / Modules` toggle, `Maintenance / Platform / Module Settings`.

### 5.2 new-payment-gateway
Compact pipeline (UX phase usually skipped — Settings UI is auto-generated). Enforces the single-file rule: only `app/services/payments/gateways/<vendor>.rb` is created. Generates the class skeleton with `key/display_name/credential_fields/supported_flows/extract_merchant_id/register!`.

### 5.3 new-captcha-provider
Same compact pipeline for `app/services/captcha/providers/<vendor>.rb`. Generates `key/display_name/config_fields/configured?/verify/widget?/register!`.

### 5.4 audit-conventions
Dispatches `anysys-tech-lead` against the current diff on demand.

### 5.5 audit-auth
Greps the current diff for missing `before_action` guards, missing `customer_id`/`user_id` checks on record-level actions, and any code path that grants the `owner` role outside the canonical user.

### 5.6 audit-tenant
Confirms every new AR model has `customer_id`, every new migration adds (and indexes) `customer_id`, every new query uses a tenant-scoped path, and no code reads `params[:customer_id]` directly.

## 6. Hooks

Only one new hook, layered on top of the existing `rtk hook copilot` PreToolUse hook (defined in the user's global `~/.copilot/settings.json`):

- **Stop hook** — when the agent finishes a turn that touched files under `app/`, `config/routes.rb`, `db/migrate/`, or `spec/`, the hook (`.cursor/hooks/tech-lead-stop.sh`) emits a marker reminding the orchestrator to dispatch `anysys-tech-lead` against the current diff. Non-blocking — the user sees the marker (or the report, if the orchestrator runs the agent) and can ignore it. This matches the user's chosen enforcement level (auto-review agent gate).

No new PreToolUse hooks. No hard gates.

## 7. Context-Discipline Rules

These are encoded in every sub-agent's system prompt to attack focus drift directly:

1. **One task per dispatch.** Each `Agent` invocation references exactly one task ID from the plan document. The agent's prompt re-states the success criteria from the plan inline, so it does not depend on conversation history.
2. **Structured return contract.** Every sub-agent returns a `## RETURN` block. The orchestrator parses that, not free-form prose.
3. **Forbidden-actions list in every system prompt.** Explicit, e.g. "You do not edit `config/routes.rb`." "You do not edit migrations." "You do not write CSS outside Tailwind utilities."
4. **Hard cap on brief length.** If a sub-agent's brief exceeds ~400 lines, the orchestrator splits the task. Long briefs are the primary cause of focus loss.
5. **No nested sub-agents.** Sub-agents do not dispatch their own sub-agents. Only the orchestrator dispatches. The tech-lead is the single exception — it may invoke `audit-conventions`/`audit-auth`/`audit-tenant` skills, which run in-process, not as nested agents. The UX designer is also allowed to invoke the `frontend-design` plugin for mockups.

## 8. File Layout

```
.cursor/
  agents/
    anysys-product-owner.md
    anysys-ux-designer.md
    anysys-backend-developer.md
    anysys-frontend-developer.md
    anysys-security-engineer.md
    anysys-qa-engineer.md
    anysys-release-engineer.md
    anysys-tech-lead.md
    anysys-code-reviewer.md
  skills/
    new-module/SKILL.md
    new-payment-gateway/SKILL.md
    new-captcha-provider/SKILL.md
    audit-conventions/SKILL.md
    audit-auth/SKILL.md
    audit-tenant/SKILL.md
  hooks/
    tech-lead-stop.sh
  settings.json    # Stop hook entry only; merges with global PreToolUse rtk hook
docs/superpowers/specs/2026-05-23-multi-agent-harness-design.md
docs/superpowers/plans/2026-05-23-multi-agent-harness.md
```

Project-scoped, checked into git, so the harness moves with the repo and any future Copilot session inherits it.

## 9. Worked Example: "Add a new SMS vendor"

To make the moving parts concrete, here is what the harness does for a representative task.

1. **Product Owner.** User: "Add Tencent Cloud SMS as a new vendor." Orchestrator dispatches `anysys-product-owner`. PO returns: stories ("As an admin, I want to send transactional SMS via Tencent so that..."), acceptance criteria (delivery status visible to admin, failure surfaced with vendor error code), edge cases (vendor down, invalid phone format, cross-tenant secret leak), out-of-scope (marketing campaigns, scheduled SMS), one open question (which Tencent SDK auth flow). User answers; brief locked.
2. **Brainstorm.** Orchestrator runs `superpowers:brainstorming` using the PO brief. Confirms the change follows the same single-file vendor pattern as captcha/payment.
3. **Spec.** Orchestrator writes `docs/superpowers/specs/2026-05-23-tencent-sms-design.md` with the `key/display_name/credential_fields/send/verify` contract.
4. **UX design.** Skipped — the Settings form is auto-generated from `credential_fields`; no in-page widget needed.
5. **Plan.** Orchestrator runs `superpowers:writing-plans`. Tasks:
   - `T1` (independent): scaffold `app/services/sms/providers/tencent.rb` → backend developer
   - `T2` (depends on T1): write `spec/services/sms/providers/tencent_spec.rb` → QA engineer
6. **Build.** Orchestrator dispatches T1 to backend developer. Then T2 to QA engineer.
7. **Verify.** `anysys-release-engineer` runs `bundle exec rspec spec/services/sms/...`, smokes the SMS settings page.
8. **Review.** `anysys-tech-lead` and `anysys-code-reviewer` dispatched **in parallel**. Tech-lead confirms: single-file rule held, no schema change, no controller change, registered with `register!`. Code reviewer confirms: no SQL injection on credential lookup, no leak of secrets in logs.
9. **User commits.**

For a "new module slice" task the build phase parallelizes backend developer + frontend developer (×3 surfaces) + security engineer in a single message — the file lanes don't overlap. That is the primary speedup the harness delivers.

## 10. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Sub-agent reduced toolset blocks a legitimate edit | Orchestrator escalates: re-dispatches to a different agent whose lane covers the file, or makes the edit itself with explicit user notice. |
| Tech-lead becomes noisy | Prompt requires "report only confirmed violations, not stylistic preferences." Code-reviewer focuses on correctness. |
| Plan fan-out misjudges what is independent | Plan format requires explicit `independent: true/false` per task. When in doubt, default to serial. |
| Stop hook fires too aggressively (e.g., on doc-only edits) | Hook checks the diff before emitting; if no files under `app/`, `config/routes.rb`, `db/migrate/`, `spec/` changed, it stays silent. |
| Existing `rtk hook copilot` PreToolUse hook conflicts with new Stop hook | Stop hook lives in a different lifecycle slot; no conflict. The project settings file holds only the Stop hook; the global file holds the PreToolUse hook. |
| Sub-agent receives stale plan context | Orchestrator re-reads the plan file before each dispatch and inlines the relevant section into the brief. |
| Role names are looser than lane names — risk of overlap | Each role's `## Forbidden actions` section explicitly references the **other** roles' lanes by name. Toolsets remain reduced (load-bearing). The role label sits on top of the lane, not in place of it. |
| PO phase adds latency for trivial tasks | Skill files (`new-payment-gateway`, `new-captcha-provider`) explicitly note when phases can be skipped (e.g., UX skip when no in-page widget). The orchestrator is allowed to skip PO for one-line bug fixes. |

## 11. Success Criteria

- All nine sub-agent definition files exist and are loadable.
- All six skills exist and are invocable.
- Stop hook fires the marker after edits to `app/`, `config/routes.rb`, `db/migrate/`, `spec/`.
- A worked-example task ("add a trivial new captcha provider stub") runs end-to-end through the pipeline: PO → brainstorm → spec → plan → backend dev → QA → release-eng → tech-lead + code-reviewer → manual commit.
- The user can describe the same workflow from memory after one runthrough — i.e., the harness is simple enough to internalize.

## 12. Open Questions

None at this point. Design approved verbally before writing.
