---
name: audit-conventions
description: Use to audit the current diff against AGENTS.md conventions on demand. Dispatches the anysys-tech-lead subagent and surfaces its report.
---

# Audit Conventions

Triggers: `/audit-conventions`, "audit the diff against AGENTS.md", "check conventions".

## Procedure

1. Confirm there's a non-empty diff: `git status` and `git diff --stat`.
2. Dispatch the `anysys-tech-lead` subagent (`.cursor/agents/anysys-tech-lead.md`) with no `model` argument (or `model: inherit`) and this prompt:
   > "Review the current `git diff` against AGENTS.md. Run your full checklist. Report only confirmed violations."
3. Surface the tech-lead's structured `## RETURN` block to the user verbatim.
4. If `overall: FAIL`, list the violations in priority order (security & roles first) and stop. Do not auto-fix — the user decides.

## When the orchestrator calls this automatically

The Cursor stop hook (`.cursor/hooks/tech-lead-stop.sh`) nudges this skill after any turn that touched files under `app/`, `config/routes.rb`, `db/migrate/`, or `spec/`.
