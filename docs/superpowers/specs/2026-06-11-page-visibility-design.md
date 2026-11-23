# Page-Level Visibility Control — Design

**Date:** 2026-06-11
**Status:** Approved scope, ready for plan

## Problem

Pages built in the page builder have only a binary `published` flag. Once
published, a page is served at the *public* URL `/:customer_id/forms/:token`
to **anyone** who has the token — there is no role-based gate. There is no way
to say "this page is for admins only" or "this page is for signed-in
members only."

## Goal

Add a **page-level visibility setting** that controls which audiences may view
the published page, enforced at the form URL. Three independent audiences:

- **admin** — admin/owner of the customer
- **member** — signed-in member of the customer
- **public** — anyone, including anonymous visitors

By default a new page is visible to **admin only**.

## Decisions (locked)

1. **Model = independent toggles.** Three independent on/off switches; a page
   can be visible to any combination. Default = admin only.
2. **Enforcement = redirect to sign-in.** A visitor whose role is not permitted
   is redirected to the tenant sign-in page; after signing in the role is
   re-checked and a still-unauthorized viewer gets 404 (Page not found).

## Data model

Add a **single** `visibility` JSON column to `pages` (typed column, **not**
stored in the versioned `configuration` blob — access control must not change
when an old content version is restored). This mirrors the entity-field
visibility shape exactly:

| column       | type   | default                                             | null  |
|--------------|--------|-----------------------------------------------------|-------|
| `visibility` | `text` | `{"admin":true,"member":false,"public":false}` | false |

Backed by `serialize :visibility, coder: JSON, type: Hash`, so `page.visibility`
reads/writes a real Hash (`{ "admin" => bool, "member" => bool,
"public" => bool }`). The DB column default seeds **admin-only** on create.

Per AGENTS.md (brand-new app, no backward-compat): existing rows backfill to
the column default, i.e. **admin-only**. Existing published pages therefore
become admin-only until an admin opens them up — this is the intended
secure-by-default behavior.

### Page model additions

- `VISIBILITY_AUDIENCES = %w[admin member public].freeze`
- `DEFAULT_VISIBILITY = { "admin" => true, "member" => false, "public" => false }`
- `serialize :visibility, coder: JSON, type: Hash`
- `visible_to?(audience)` — reads `visibility[audience]`, **fail-closed**
  (visible only when the key is explicitly `true`)
- `visible_audiences` — array of enabled audience keys
- Validation: **at least one** audience must be enabled — enforced in
  `Pages::VisibilityContract` (validation lives in the Reform contract per
  AGENTS.md, not the model).

## Enforcement — `PublicPagesController`

`/:customer_id/forms/:token` stays in the *public* URL category but now
self-enforces per-page audience. Replace `find_published_page`:

```
@page = Page.for_current_customer.published.find_by(public_token: params[:token])
return render_page_not_found unless @page
return if page_visible_to_current_viewer?(@page)   # render normally

if user_signed_in?
  render_page_not_found              # signed in, role not permitted
else
  store_location_for_return          # remember the form URL
  redirect_to new_user_session_path(customer_id: params[:customer_id])
end
```

`page_visible_to_current_viewer?`:

```
return true  if page.visible_to?(:public)
return false unless user_signed_in?
# tenant match (platform owner may cross tenants)
return false unless current_user.customer_id == current_customer_id || current_user.platform_owner?
return true  if page.visible_to?(:admin)  && current_user.admin_or_owner?
return true  if page.visible_to?(:member) && current_user.member?
false
```

- `render_page_not_found` → `render plain: "Page not found", status: :not_found`
  (same as today; does not leak which roles are allowed).
- After sign-in, the stored location returns the user to the form URL and the
  gate re-runs; if still not allowed → 404.
- **Admins are never locked out of review:** the admin-side preview route
  `/:cid/admin/maintenance/pages/:id/preview` is admin-gated and independent of
  these toggles.

## UI — Visibility card on the page show view

Add a **Visibility** section to `app/views/admin/maintenance/pages/show.html.erb`,
directly under the existing Publishing card, rendered via a ViewComponent
`Pages::VisibilityCardComponent` (Tailwind only). Three checkboxes
(Admin / Member / Public) reflecting current state, in a form that submits
to a dedicated action. The card is shown regardless of published state (you
decide *who* can see it; Publish makes it live). Copy clarifies that admins can
always preview from the admin UI.

## Route + controller

New singular resource mirroring the existing `restoration` pattern under the
page (Module URL area: **Maintenance / Pages**, an admin URL):

```
PATCH /:customer_id/admin/maintenance/pages/:page_id/visibility
  → Admin::Maintenance::PageVisibilitiesController#update
```

Because the path is under `/:cid/admin/...`, `RouteAuthorization` automatically
gates it to admin/owner — no per-controller auth filter needed. The controller
loads the page tenant-scoped (`Page.for_current_customer.find`), validates
through a Reform contract, updates the `visibility` hash, and redirects back to
the page show with a notice.

### Reform contract — `Pages::VisibilityContract`

Coerces the submitted `visibility` hash to booleans and enforces the "at least
one audience enabled" rule. Keeps the model thin and follows the
Trailblazer/Reform convention.

## Testing

- **Model spec:** defaults (admin-only), `visible_to?`, `visible_audiences`,
  at-least-one validation.
- **Contract spec:** at-least-one rule, coercion of checkbox params.
- **Request spec — `PublicPagesController`:** full matrix of
  {anonymous, member-of-customer, member-of-other-customer, admin, owner} ×
  visibility combinations → render / 404 / redirect-to-sign-in. Multi-tenant
  isolation: a member of another customer is never allowed.
- **Request spec — `PageVisibilitiesController`:** admin can update; the admin
  route guard rejects member/anonymous; tenant isolation on the page lookup;
  contract rejection (all toggles off).
- **Component spec — `VisibilityCardComponent`:** renders three toggles with
  correct checked state for a given page.

## Out of scope

- Per-field visibility (already exists via layout templates / the `visibility`
  hash on fields — unchanged).
- Time-based or token-expiry visibility.
- Changing the `published` flag semantics or the public token mechanism.
