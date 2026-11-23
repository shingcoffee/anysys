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
