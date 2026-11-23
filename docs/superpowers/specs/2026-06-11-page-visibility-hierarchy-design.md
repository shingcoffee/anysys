# Page Visibility Hierarchy — Design

Date: 2026-06-11
Status: Approved (autonomous run; decisions per user request + AGENTS.md)

## Problem

`Page#visibility` is a JSON text column holding three independent booleans
(`{"admin":bool,"member":bool,"public":bool}`), edited via three checkboxes in
`Pages::DistributionCardComponent`. This allows incoherent states ("member-visible
but not admin-visible"), requires an artificial "at least one audience" validation,
and the member "Open" link on the admin page detail is unusable by admins because
`Member::PagesController` only admits the `member` role.

## Requirements (from user)

1. A page is **always visible to admin**; this cannot be changed.
2. **Public-visible ⇒ member- and admin-visible.**
3. **Member-visible ⇒ admin-visible.**
4. An **admin can open the member-oriented page directly** (the `/:cid/member/pages/:id` render).

## Design

Visibility becomes a single hierarchical **level**: `admin` ⊂ `member` ⊂ `public`.

### Data model

- Migration replaces the JSON text column with `pages.visibility` as a `string`,
  `null: false, default: "admin"`. Existing rows are normalised first
  (public flag wins, then member, else admin) — cheap to keep dev data coherent
  even though backward compatibility is officially out of scope.
- `Page`:
  - `VISIBILITY_LEVELS = %w[admin member public].freeze` (rank = index).
  - `validates :visibility, inclusion: { in: VISIBILITY_LEVELS }`.
  - `visible_to?(audience)` → `rank(visibility) >= rank(audience)`; unknown
    audience returns `false` (fail closed). `visible_to?(:admin)` is therefore
    always true for any valid level.
  - `visible_audiences` → all levels up to and including the page's level.
  - Drop `serialize`, `DEFAULT_VISIBILITY` hash, and the JSON plumbing.

### Contract

`Pages::VisibilityContract` shrinks to one property: `visibility` (string),
validated for inclusion in `VISIBILITY_LEVELS`. The `at_least_one_audience`
validation and checkbox coercion are deleted — the invariant is structural.

### Controller / routes

- `Admin::Maintenance::PageVisibilitiesController` permits a single scalar
  `page[visibility]` param. Route unchanged
  (`PATCH /:cid/admin/maintenance/pages/:page_id/visibility`).
- `Member::PagesController#show` admits, in addition to members:
  same-customer `admin`/`owner` users and the platform owner (read-only render,
  no member-only side effects). Anonymous users still redirect to sign-in;
  cross-tenant admins are still rejected. The `published` scope and
  `visible_to?(:member)` gate are unchanged.
- `PublicPagesController` and `Admin::Maintenance::PageRendersController` are
  untouched — their `visible_to?` calls inherit the new semantics.

### UI (`Pages::DistributionCardComponent`)

- The three checkbox rows become a single **radio group** ("Admin only" /
  "Members" / "Public"), one radio per row, same card layout. Copy makes the
  hierarchy explicit (e.g. "Members — members and admins", "Public — everyone").
- "Open" links per row:
  - Admin row: enabled iff `published?` (admin visibility is invariant).
  - Member row: enabled iff `published? && visible_to?(:member)`; otherwise
    disabled with "Not visible to Member". Now genuinely usable by the admin
    viewing the card, thanks to the controller bypass.
  - Public row: enabled iff `published? && visible_to?(:public)` (and token present).

### Testing

Update, per the stale-test policy (rewrite > delete):
- `spec/models/page_spec.rb` — level default, `visible_to?` hierarchy matrix,
  inclusion validation, fail-closed unknown audience.
- `spec/contracts/pages/visibility_contract_spec.rb` — accepts the three levels,
  rejects unknown/blank, persists.
- `spec/components/pages/distribution_card_component_spec.rb` — radio group,
  checked state per level, Open-link enablement matrix.
- `spec/requests/maintenance/page_visibilities_spec.rb` — PATCH with level param,
  rejects bogus level, member role still blocked.
- `spec/requests/member/pages_spec.rb` — member happy path; **admin same-tenant
  200**, owner 200, cross-tenant admin rejected, anonymous redirected,
  admin-only page 404 for member.
- `spec/requests/public_pages_visibility_spec.rb` &
  `spec/requests/admin/maintenance/page_renders_spec.rb` — re-express fixtures
  in level terms; assertions otherwise stand.

## Out of scope

Audit logging, bulk updates, per-section visibility, new roles, changes to other
modules, any new admin-namespaced preview route.
