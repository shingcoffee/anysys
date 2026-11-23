# Shared Constants — Full CRUD for the Platform Owner

**Date:** 2026-06-13
**Status:** Approved, ready for implementation

## Problem

On `/:cid/admin/maintenance/constants`, **customer-specific** constants already
support full CRUD (create / read / update / delete) for the owning tenant's admin.
**Shared** constants (platform-wide, `customer_id IS NULL`) do not:

- **Create** — allowed, platform-owner only (`constant_params` forces non-owners to
  `customer_specific`).
- **Read** — allowed (index, show, JSON picker).
- **Update / Delete** — **blocked for everyone**, including the platform owner.
  `ConstantsController#ensure_editable` redirects with "Shared constants cannot be
  edited" whenever `@constant.type_shared?`, and the index/show views hide Edit/Delete
  for shared constants.

So the platform owner can create a shared constant and then never change or remove it.
Adjacent dead-end: the "Copy to Customer" button shown on shared constants calls
`ConstantCopiesController#show`, which looks up `Constant.where(customer_id:
current_customer_id).find(...)` — shared constants have a NULL `customer_id`, so the
copy 404s.

## Decision

Give the **platform owner** (`current_user&.platform_owner?` — owner role under customer
`81721200`) full **Update** and **Delete** on shared constants, completing their CRUD.
Regular tenant admins stay blocked from mutating shared constants (shared = platform
resource, consistent with the reserved-role model: only the owner has platform-wide
management). Fix the copy lookup so shared constants can be copied.

No schema, route, or model changes — routes and the `Constant` model already support the
full set; this is an authorization + UI completion.

## Changes

### 1. `ConstantsController#ensure_editable` (authorization)

Replace the blanket shared-constant block with an owner-aware gate:

```ruby
def ensure_editable
  return unless @constant.type_shared?
  return if current_user&.platform_owner?

  respond_to do |format|
    format.html { redirect_to admin_maintenance_constants_path(current_customer_id),
                              alert: "Shared constants can only be edited by the platform owner." }
    format.json { render json: { error: "Shared constants can only be edited by the platform owner" },
                         status: :forbidden }
  end
end
```

- Customer-specific constants are unaffected: `find_constant` uses `Constant.accessible`
  (current customer's own + shared), so a customer-specific record reached here always
  belongs to the current tenant.
- `constant_params` already permits `constant_type` only for the platform owner, so no
  change is needed there; an owner updating a shared constant keeps it shared.

### 2. Form — `_form.html.erb` (type options for the owner)

The type `select` currently hardcodes only `["Customer Specific", "customer_specific"]`.
For the platform owner, include `["Shared", "shared"]` so they can create/edit shared
constants; for everyone else keep the single customer-specific option (matches the
existing server-side `constant_params` gate). Default the selection to the constant's
current type.

### 3. Views — expose Edit/Delete for shared constants to the owner

- `index.html.erb` `row_actions`: add the **Edit** action when
  `c.type_customer_specific? || current_user&.platform_owner?` (today: only
  `customer_specific`).
- `show.html.erb`: for a shared constant, when `current_user&.platform_owner?`, render
  the **Edit** and **Delete** buttons (the same ones customer-specific constants get)
  instead of only "Copy to Customer". Show the read-only "shared constant cannot be
  edited" info alert only to non-owners. Non-owners keep the Copy button.

### 4. `ConstantCopiesController#show` (copy fix)

Change the source lookup from `Constant.where(customer_id: current_customer_id)` to
`Constant.accessible` so a shared constant (NULL `customer_id`) can be copied into a new
customer-specific constant. The new copy is still `customer_specific` + assigned to
`current_customer`, exactly as today.

## Multi-tenant / authorization safety

- Only `platform_owner?` (owner role AND customer `81721200`) may update/delete shared
  constants. Regular admins are redirected/forbidden — no privilege escalation.
- `find_constant` (`Constant.accessible`) keeps a tenant admin from reaching another
  tenant's customer-specific constant by id.
- The owner editing shared constants is platform-wide management, which is exactly the
  owner role's remit per AGENTS.md.

## Testing (request specs)

Extend `spec/requests/admin/maintenance/constants_spec.rb` (and/or
`spec/requests/constants_spec.rb`):

- **Platform owner** (owner role, customer `81721200`) can **update** a shared constant
  (name + options) → 302/redirect, change persisted.
- Platform owner can **delete** a shared constant → record removed.
- Platform owner sees **Edit/Delete** on the shared constant's show page and an **Edit**
  row action on index; the form's type select offers **Shared**.
- **Regular tenant admin** attempting to update or delete a shared constant is
  redirected with the alert (HTML) / `403` (JSON), and the record is unchanged
  (tenant-isolation / privilege guard).
- Regular admin still cannot create a shared constant (existing behavior — confirm).
- **Copy:** a request to copy a shared constant renders the new form prefilled (no 404).

## Out of scope

- Changing how individual options are managed (already full add/edit/remove/reorder in
  the form via the `constant-form` Stimulus controller).
- Adding a Delete action to the index table (delete remains on the show page for all
  constant types, as today).
