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
