# Member Pages Skeleton — Design

**Date:** 2026-05-15
**Status:** Draft for review
**Scope:** Layout, shell, authorization, navigation, and styling skeleton for the member (member) section of the application. Auth surfaces (sign-up / sign-in / password reset) reskinned to share the same personality.

---

## 1. Background and motivation

The application defines three URL trees in `AGENTS.md`:

- **admin** — `/:cid/admin/*` — admin or owner role
- **member** — `/:cid/member/*` — member role
- **public** — anything else

The admin tree is mature: deep `Admin::*` namespace, `ShellComponent` chrome (Topbar + MenuBar + Sidebar + Drawer), full design-token system, ~50 controllers. The member tree is a placeholder — `config/routes.rb` reserves `2c. MEMBER` but no surfaces exist yet.

This spec describes the foundational shell, authorization, navigation registry, and the first set of member pages. It is a **skeleton**: enough structure that subsequent member features can be added with one controller + one view + one nav-registry entry, with no further shell changes.

The skeleton also reskins the existing auth surfaces (sign-up, sign-in, password reset) so a member's first touch with the application matches the member personality from the very first screen.

## 2. Goals and non-goals

**Goals**

1. Members can sign up under a customer, sign in, recover password, edit their profile, manage security, and see their own payments — all under a coherent, beautiful, easy-to-use shell.
2. Member surfaces are visually and architecturally distinct from admin surfaces. They share the design-token foundation but have their own accent palette, their own shell component, their own controller base class, and their own layout.
3. Authorization is enforced at the controller layer (URL gate), the tenant layer (customer scoping), and the record layer (ownership check) — not by UI hiding alone.
4. Adding the next member feature is mechanical: one controller subclassing `Member::BaseController`, one nav-registry entry, one set of views.

**Non-goals**

- Notification center.
- User-editable preferences (theme, locale).
- 2FA recovery codes management UI.
- Account deletion / data export.
- Member-side "create payment" flow — that already lives at `/:cid/payments/checkout` per existing public routes; the member payments pages are read-only listings of the user's own payments.
- Splitting member surfaces into a separate Rails engine or separate hostname. We remain a single monolith. Engine extraction is the next maturity tier and is out of scope.

## 3. Industry-standard reference shape

For context, mature multi-tenant SaaS applications converge on six layers of separation between admin / member / public surfaces:

1. URL prefix per category
2. Controller namespace mirroring the URL, with a per-category base controller
3. Layout / shell component per category
4. Policy / authorization at the resource level (record-aware, not URL-aware)
5. Navigation as data (a registry the shell consumes; not hardcoded markup)
6. Engines / modular monolith for the strongest separation

Examples: Stripe takes the maximum (separate hostnames for Dashboard / Customer Portal / marketing). Shopify uses a packwerk-enforced modular monolith. GitHub, GitLab, and Discourse are single Rails monoliths with layers 1–5. This codebase already has layers 1–3 in place for admin; this spec adds layers 1–5 for member and consciously stops short of layer 6.

## 4. Architecture

### 4.1 Two parallel shells

```
┌─────────────────────────────────────────────────────────┐
│  layouts/application.html.erb  →  ShellComponent        │  admin chrome
│  (Topbar + MenuBar + Sidebar + Drawer + main)           │  (existing)
├─────────────────────────────────────────────────────────┤
│  layouts/member.html.erb  →  Member::         │  member chrome
│  ShellComponent (TopNav + main)                         │  (NEW)
├─────────────────────────────────────────────────────────┤
│  layouts/auth.html.erb         →  Member::         │  auth surfaces
│  AuthShellComponent (split-pane: marketing left,        │  (reskinned —
│  form right)                                            │   replaces current
│                                                         │   minimal layout)
└─────────────────────────────────────────────────────────┘
```

Each shell is responsible for chrome only; pages render content inside via `<%= content %>`. No cross-talk between shells.

The existing `layouts/auth.html.erb` today is a thin minimal shell shared by all Devise endpoints. Devise endpoints serve both admins and members (same registration, sign-in, password-reset surfaces are the entry point for everybody), so reskinning this single layout gives the entire auth experience the member personality — which is the correct first impression for new self-sign-up users. Admins hit the same auth pages and see the same friendly first-touch surface; nothing about that hurts admins.

### 4.2 Controller layout

```
app/controllers/
  member/
    base_controller.rb              # layout + helpers + authorize_owned! (URL/tenant gates inherited)
    dashboards_controller.rb        # GET    /:cid/member          (Home)
    profiles_controller.rb          # GET    /:cid/member/profile
                                    # GET    /:cid/member/profile/edit
                                    # PATCH  /:cid/member/profile
    securities_controller.rb        # GET    /:cid/member/security
    payments_controller.rb          # GET    /:cid/member/payments
                                    # GET    /:cid/member/payments/:id
```

`Member::BaseController < ApplicationController` is intentionally thin. It declares:

- `layout "member"` — opt into the member shell layout for the whole namespace.
- `helper_method :current_member, :member_nav_items` — view helpers.
- protected `authorize_owned!(record)` — single-line guard the controllers call before touching a specific record:

```ruby
def authorize_owned!(record)
  raise ActiveRecord::RecordNotFound unless record &&
    record.customer_id == current_user.customer_id &&
    (!record.respond_to?(:user_id) || record.user_id == current_user.id)
end
```

The URL+role gate (member required) and the tenant gate (cross-tenant rejection) are NOT installed here — they're inherited from the global `RouteAuthorization` and `TenantContext` concerns that `ApplicationController` already includes. See §7 for the full contract. This is the layer-4 discipline encoded at the level the project actually wires authorization. Every show/edit/update/destroy action in a member controller calls `authorize_owned!`. We deliberately do not introduce Pundit at this size; if the member surface grows past ~10 controllers the call-sites are already shaped to mechanically lift into a real policy class.

`Ability` (`app/models/ability.rb`) gains a `member` branch that grants `can :manage, [:route_member_dashboards, :route_member_profiles, :route_member_securities, :route_member_payments]`. This is what makes `RouteAuthorization#authorize_route!` pass for member users on the member surfaces. Adding a new member controller means adding its symbol to `Ability#member_route_subjects` (one line).

### 4.3 View component layout

```
app/components/member/
  shell_component.rb / .html.erb         # member shell (TopNav + main)
  top_nav_component.rb / .html.erb       # logo + nav items + user menu
  user_menu_component.rb / .html.erb     # avatar dropdown (profile, security, sign out)
  hero_card_component.rb / .html.erb     # gradient hero panel used on Home
  status_card_component.rb / .html.erb   # the three status cards on Home
  auth_shell_component.rb / .html.erb    # split-pane shell for sign-in/up/recover
```

All inherit from the existing `ApplicationComponent`. Naming, slot structure, and lifecycle mirror existing admin components.

### 4.4 Navigation as data

```
app/services/member/
  navigation.rb               # module-level registry
  navigation/item.rb          # value object: key, label, path, icon, visible?
```

`Member::Navigation.items_for(user)` returns the nav items the user should see, given their customer's enabled modules. Each item is a small value object with:

- `key` — symbol (`:home`, `:profile`, `:payments`, `:security`)
- `label` — display string
- `path` — lambda taking the customer, returning the URL string
- `icon` — symbol naming a Heroicons SVG
- `visible` — lambda taking the user, returning a boolean

Initial registry:

| Key | Label | Visibility |
|---|---|---|
| `:home` | "Home" | always |
| `:profile` | "Profile" | always |
| `:payments` | "Payments" | `user.customer.module_enabled?(:payments)` |
| `:security` | "Security" | always |

`Member::TopNavComponent` consumes the items array and does not know what items exist. Adding a new member surface is then: add a controller + add one entry to the registry. The shell never needs to be edited again.

## 5. Pages

### 5.1 Page inventory

| # | Page | Path | Layout | Controller |
|---|---|---|---|---|
| 1 | Sign in | `/:cid/auth/sign_in` | `auth` | `Authentication::SessionsController` (existing) |
| 2 | Sign up | `/:cid/auth/sign_up` | `auth` | `Authentication::RegistrationsController` (existing) |
| 3 | Forgot password | `/:cid/auth/password/new` | `auth` | `Authentication::PasswordsController` (existing) |
| 4 | Reset password | `/:cid/auth/password/edit` | `auth` | `Authentication::PasswordsController` (existing) |
| 5 | Home / Overview | `/:cid/member` | `member` | `Member::DashboardsController#show` |
| 6 | Profile show | `/:cid/member/profile` | `member` | `Member::ProfilesController#show` |
| 7 | Profile edit | `/:cid/member/profile/edit` | `member` | `Member::ProfilesController#edit / update` |
| 8 | Security | `/:cid/member/security` | `member` | `Member::SecuritiesController#show` |
| 9 | My Payments — index | `/:cid/member/payments` | `member` | `Member::PaymentsController#index` |
| 10 | My Payments — show | `/:cid/member/payments/:id` | `member` | `Member::PaymentsController#show` |

Auth pages get view + layout reskins only; controllers are not modified. Profile edit submits through a Reform contract (`Member::Profiles::UpdateContract`) per project convention; the controller stays thin.

### 5.2 Sign in (auth shell)

Split-pane layout. Left: brand panel with the member gradient, customer name, a one-sentence value-prop tagline, and a soft decorative shape. Right: the sign-in form (email, password, "Remember me", primary submit, secondary "Forgot password?" link, tertiary "Create an account" link).

Mobile collapses to single column with the brand panel as a slim header.

### 5.3 Sign up (auth shell)

Same split-pane shell. Form fields: first name, last name, email, password, password confirmation, terms checkbox.

Two changes to the existing `Authentication::RegistrationsController` are required and in scope of this skeleton:

1. **Assign the `member` reserved role on successful create.** The current controller persists the user without assigning any reserved role. After `resource.save` succeeds, attach the `member` role via the existing `UsersRole` association (the same path admin tooling uses) before signing the user in.
2. **Redirect to `/:cid/member` instead of admin.** `after_sign_up_path_for` currently returns `admin_dashboard_path(current_customer_id)`, which is wrong for self-sign-up — a fresh `member` cannot enter `/admin`. Change it to the member dashboard path.

`Authentication::RegistrationsController#account_update_params` is already permissive enough for the member profile-update use case, but member profile updates go through the new `Member::ProfilesController` + Reform contract, not Devise's update path; the Devise update endpoint is left untouched.

### 5.4 Forgot / reset password (auth shell)

Same split-pane shell. Forgot: single email field, primary "Send reset link" CTA. Reset: new password + confirmation, primary "Set new password" CTA. Both inherit Devise behavior; only views change.

### 5.5 Home / Overview

The face of the portal. Composed of:

- **Hero card** — full-width gradient panel using `--gradient-member-hero`. Headline: `"Hi {first_name} 👋"`, subhead: time-of-day greeting (morning / afternoon / evening based on server time), secondary line summarizing one notable status (e.g. "Your membership is active.").
- **Status card row** — three rounded cards in a responsive grid (1 col on mobile, 3 cols on desktop):
  1. **Profile** — status text "Complete" if first_name, last_name, and email are all present (which is enforced by validations, so the card label here is effectively always "Complete" today; the card exists as a hook for future optional profile fields). CTA: "Update profile →".
  2. **Payments** — count of payments in the last 30 days + total amount over that window. CTA: "View all →". Hidden when the Payments module is disabled for the customer.
  3. **Security** — MFA on/off badge driven by `current_user.mfa_required?`. CTA: "Manage security →".
- **Recent activity strip** — a thin card listing the user's last 5 sign-ins (from Devise `trackable` columns: `last_sign_in_at`, `last_sign_in_ip`). Empty state for brand-new accounts (no sign-in history yet): a friendly illustration placeholder + "Welcome — your activity will show up here as you use the portal."

### 5.6 Profile show + edit

**Show** — read-only view of the user record: avatar (initials placeholder), full name, email, member-since date, customer name. Single primary CTA: "Edit profile". Single secondary CTA: "Sign out".

**Edit** — form with first name, last name, email. Email is editable per the existing model validation (`uniqueness: { scope: :customer_id }`). Submits via the `Member::Profiles::UpdateContract` (Reform). Inline validation errors per field. Cancel returns to show.

### 5.7 Security

Single-page authenticated security center:

- **Password** — "Change password" CTA links to the existing Devise password edit flow (same controller as forgot-password reset, but reached via a logged-in path).
- **Two-factor authentication** — Status badge (On / Off / Enforced). If off: "Set up 2FA" CTA links to the existing `/:cid/auth/mfa/setup` endpoint. If on: "Disable 2FA" destructive action calls the existing `/:cid/auth/mfa` DELETE endpoint.
- **Recent sign-ins** — last sign-in row from Devise `trackable` columns (`last_sign_in_at`, `last_sign_in_ip`, plus `current_sign_in_at`/`current_sign_in_ip` if different). Read-only.

No new endpoints — Security is a composition page over existing auth surfaces.

### 5.8 My Payments — index + show

**Index** — read-only list of `Payments::Payment` records where `user_id == current_user.id` AND `customer_id == current_user.customer_id`. Each row: date, amount, status pill, vendor (Alipay / WeChat Pay), "View →" link. Pagination (20 per page) using whatever the project already uses on the admin payments index. Empty state: friendly illustration + "No payments yet."

**Show** — single payment detail page: amount, status, vendor, created/paid timestamps, receipt download (if available), refund history (if any). Read-only — no actions in skeleton.

Both controller actions call `authorize_owned!(@payment)` before rendering.

## 6. Routes

Drop into the existing `2c. MEMBER` block in `config/routes.rb`:

```ruby
namespace :member do
  resource  :dashboard, only: :show, controller: "dashboards", path: ""
  resource  :profile,   only: %i[show edit update]
  resource  :security,  only: :show, controller: "securities"
  resources :payments,  only: %i[index show]
end
```

Resulting URLs:

```
GET    /:cid/member                    member/dashboards#show
GET    /:cid/member/profile            member/profiles#show
GET    /:cid/member/profile/edit       member/profiles#edit
PATCH  /:cid/member/profile            member/profiles#update
GET    /:cid/member/security           member/securities#show
GET    /:cid/member/payments           member/payments#index
GET    /:cid/member/payments/:id       member/payments#show
```

No changes to existing auth or admin routes.

## 7. Authorization contract

Three layers, all enforced; no UI hiding alone. Layers 7.1 and 7.2 are inherited from existing global concerns — they already enforce admin/member URL prefixes for any controller. `Member::BaseController` therefore does NOT re-implement them; it owns only the record-level layer 7.3.

### 7.1 URL gate (inherited)

`app/controllers/concerns/route_authorization.rb` (included in `ApplicationController`) is the project's single declarative URL+role gate. It runs as a `before_action` keyed off path:

- `/:cid/member/*` requires `current_user.member?`
- `/:cid/admin/*` requires `current_user.admin_or_owner?`
- `/:cid/admin/maintenance/platform/*` requires `current_user.platform_owner?`

Behavior on rejection:

- Unauthenticated → Devise redirect to `/:cid/auth/sign_in`.
- Authenticated but wrong role (e.g. admin visiting `/:cid/member`) → `CanCan::AccessDenied` raised; `RouteAuthorization#handle_access_denied` redirects to `/:cid` (the user's own customer root) with the flash `"Member privileges required."`. The redirect target is intentionally tenant-aware to avoid dropping the user on the marketing root.
- Authenticated with the right role → proceed.

Member controllers inherit this for free by subclassing the application stack. They MUST NOT add their own `before_action :authenticate_user!` or `before_action :require_member!` — that would either duplicate work or, worse, reorder the chain in confusing ways. The single-layer rule is what makes "URL pattern → role" auditable.

### 7.2 Tenant gate (inherited)

`app/controllers/concerns/tenant_context.rb` (also included in `ApplicationController`) auto-extracts `Current.customer` from any `/:cid/...` URL. When a signed-in user reaches a tenant other than their own, `TenantContext#signed_in_other_tenant?` returns true, and (for non–platform-owners) `render_tenant_forbidden_error` redirects to `/<user.customer_id>/admin/dashboard` with the alert `"Access denied."`. Platform owners are passed through.

This is a 302 redirect, not a 404. The earlier draft of this spec proposed 404 to avoid tenant-existence leaks; the existing convention prioritizes user-friendly recovery and is already locked in across the admin surface, so member surfaces inherit it for consistency.

Member controllers MUST NOT accept a `customer_id` parameter from a body or query — they read it from the URL path only.

### 7.3 Ownership gate (member-specific)

`Member::BaseController` defines `authorize_owned!(record)` as a protected method:

```ruby
def authorize_owned!(record)
  raise ActiveRecord::RecordNotFound unless record &&
    record.customer_id == current_user.customer_id &&
    (!record.respond_to?(:user_id) || record.user_id == current_user.id)
end
```

Every show / edit / update / destroy action that touches a specific record (e.g. `Member::PaymentsController#show`) calls this before rendering or mutating. Records that fail return 404 — this is the gate that prevents user A from viewing user B's payment by URL guessing within the same tenant.

The 404 here IS appropriate (unlike layer 7.2): the user IS in the right tenant, so we are not leaking any tenant-existence; we are merely refusing to confirm whether a given record id exists for someone else.

### 7.4 Test contract

`spec/requests/member/base_authorization_spec.rb` locks this in with explicit cases:

- (a) anonymous → redirected to `/:cid/auth/sign_in`
- (b) admin role visiting a member URL → redirected to `/:cid` with flash `"Member privileges required."`
- (c) owner role visiting a member URL → redirected to `/:cid` with flash `"Member privileges required."`
- (d) member of customer A visiting customer B's URL → redirected to `/<A>/admin/dashboard` with alert `"Access denied."`
- (e) member viewing a payment whose `user_id` is someone else's → 404 (covered by `payments_spec.rb`, not this base spec)
- (f) member visiting their own member URL → 200

The test contract is the source of truth for the actual response shapes, not the prose above.

## 8. Styling — distinct member token namespace

A parallel set of member-specific tokens lives alongside the existing `--color-accent-*` in `app/assets/tailwind/application.css`. The member shell, top nav, hero card, status cards, and primary CTAs reference these. Admin chrome continues to reference `--color-accent-*`. No risk of cross-contamination.

### 8.1 Token additions

```css
@theme {
  /* Member surface accent — distinct from admin indigo.
     Selected hue: teal-500 (#0d9488 base) for warmth and trustworthiness while
     staying visibly distinct from admin's indigo. Final shade tuned in
     implementation against contrast requirements. */
  --color-member-accent:        #0d9488;
  --color-member-accent-hover:  #0f766e;
  --color-member-accent-active: #115e59;
  --color-member-accent-subtle: #f0fdfa;
  --color-member-accent-muted:  #99f6e4;
  --color-member-accent-text:   #115e59;

  --gradient-member-hero: linear-gradient(135deg,
    var(--color-member-accent) 0%,
    var(--color-member-accent-hover) 100%);
}
```

### 8.2 Component utility additions

Three member-flavored utilities sit alongside `.btn-primary` etc. in the `@layer components` block — they do not replace the admin utilities:

```css
.btn-member              /* primary CTA on member surfaces */
.btn-member:hover, :active
.nav-item-member         /* top nav item, default state */
.nav-item-member-active  /* top nav item, current page */
.card-member-elevated    /* status cards on Home */
.hero-member             /* full-width gradient panel */
```

The member shell uses these; admin shell does not.

### 8.3 Typography & spacing

Inherit the existing type scale and font stack — no changes. Member pages just compose the existing scale at slightly larger sizes (e.g. Home hero uses `.text-display`; admin pages use `.text-title`). This keeps brand voice consistent at the typographic level even though the accent palette diverges.

## 9. Component contracts

### 9.1 `Member::ShellComponent`

```ruby
Member::ShellComponent.new(
  customer:,             # Customer
  user:,                 # Authentication::User
  current_nav: :home,    # symbol matching a registry key
  container_width: :default  # :default | :narrow | :edge
)
```

Renders top nav + flash + main with the wrapped content. `:edge` means the page is responsible for its own horizontal padding (used by Home's full-bleed hero); `:default` and `:narrow` apply standard or narrowed max-widths.

### 9.2 `Member::TopNavComponent`

```ruby
Member::TopNavComponent.new(
  customer:,
  user:,
  items:,           # Array<Member::Navigation::Item>
  current_nav:      # symbol
)
```

Stateless. Renders logo (links to `/:cid/member`), nav items, user menu. Mobile: collapses items behind a hamburger that opens a sheet (Stimulus controller `member--mobile-nav`).

### 9.3 `Member::HeroCardComponent`

```ruby
Member::HeroCardComponent.new(
  greeting:,    # String — e.g. "Good morning"
  name:,        # String — e.g. "Lin"
  subhead:,     # String — one-line context
  status: nil   # optional badge — { label:, tone: :success | :warning | :info }
)
```

Renders the gradient hero panel.

### 9.4 `Member::StatusCardComponent`

```ruby
Member::StatusCardComponent.new(
  label:,       # "Profile"
  value:,       # "90%" or "$0" or "On"
  tone: :default,  # :default | :success | :warning
  icon:,        # symbol
  cta_label:,   # "Update"
  cta_path:
)
```

### 9.5 `Member::AuthShellComponent`

```ruby
Member::AuthShellComponent.new(
  customer:,    # Customer (for branding panel)
  title:,       # "Welcome back"
  subtitle:     # "Sign in to your account"
)
```

Slot: `with_form` — receives the form ERB block.

## 10. Reform contract

```
app/contracts/member/profiles/update_contract.rb
```

Validates: `first_name` (presence, length ≤ 50), `last_name` (presence, length ≤ 50), `email` (presence, format, uniqueness scoped to `customer_id`). Mirrors the existing `Authentication::User` validations so behavior is consistent whether the user updates via Devise or this contract.

## 11. Testing convention

```
spec/system/member/
  sign_up_spec.rb        # full registration flow under the auth shell
  sign_in_spec.rb        # sign-in success/failure under the auth shell
  password_reset_spec.rb # forgot + reset flow
  home_spec.rb           # logged-in member sees hero + status row + activity
  profile_spec.rb        # show, edit, update happy path + validation errors
  security_spec.rb       # security center renders, links go to existing endpoints
  payments_spec.rb       # index lists own payments only; show renders own payment

spec/requests/member/
  base_authorization_spec.rb   # the §7.4 contract
  dashboards_spec.rb
  profiles_spec.rb
  securities_spec.rb
  payments_spec.rb

spec/components/member/
  shell_component_spec.rb
  top_nav_component_spec.rb
  hero_card_component_spec.rb
  status_card_component_spec.rb
  auth_shell_component_spec.rb
```

Coverage target: 100% of the new controllers, components, and Reform contract — matching the project's stated convention that fresh-generated code receives full RSpec coverage.

## 12. Implementation phases

The implementation plan (produced separately by `writing-plans`) will likely break this into roughly four phases:

1. **Foundation** — tokens, base controller, layout, shell component, top-nav component, navigation registry, route block. No pages yet — just the chassis. Verified by `base_authorization_spec.rb` against a stub controller.
2. **Auth reskin** — reskin sign-in / sign-up / password reset views; introduce `auth_shell_component`. Verified by system specs.
3. **Authenticated pages — minimum** — Home, Profile show/edit, Security. Verified by system + request specs.
4. **Payments** — Payments index/show. Verified by system + request specs. Hidden when Payments module is disabled.

Each phase is independently mergeable.

## 13. Risks and open questions

- **Customer onboarding state.** This skeleton assumes a customer already exists when a user signs up. The "create a customer + first user" flow is a separate concern (existing `customer_resolutions_controller` handles tenant resolution at sign-in). No change to that flow here.
- **Module-disabled UX.** When the Payments module is disabled for the customer, the `Payments` nav item is hidden and the Home status card is hidden. Direct URL access to `/:cid/member/payments` while the module is disabled should return 404 — the member payments controller checks `current_user.customer.module_enabled?(:payments)` in a `before_action` and raises `ActiveRecord::RecordNotFound` if not. The implementation plan should explicitly verify this.
- **Mobile gestures.** The mobile sheet menu uses `data-action="click->member--mobile-nav#toggle"` only — no swipe gestures. Acceptable for the skeleton.
- **i18n.** Strings in this skeleton are English-only; no `t()` wrappers. If the project has an active i18n direction, the skeleton can be wrapped during a later pass — out of scope here.
- **Self-registration setting.** The existing `RegistrationsController#check_registration_allowed` defaults to false — tenants must opt in. This skeleton does not change that default; the auth-shell sign-up reskin only takes effect on tenants that have opted in. On tenants that have not opted in, the existing redirect to sign-in (with the alert "Self-registration is not available") continues to fire and the new view is never rendered.

## 14. Acceptance criteria

The skeleton is considered done when:

1. A new user can land on `/:cid/auth/sign_up`, register, be redirected to `/:cid/member`, see the Home page populated with their data.
2. The user can navigate to Profile, edit their name, save, and see the change reflected.
3. The user can navigate to Security, click "Set up 2FA", and reach the existing MFA setup flow without visual rupture.
4. The user can navigate to Payments (when the module is enabled) and see only their own payment records.
5. An admin user accidentally clicking a member URL is redirected away with a clear flash.
6. A user from customer A typing customer B's member URL receives 404.
7. All new RSpec specs pass; no existing specs regress.
8. The member surfaces and the admin surfaces are visually distinguishable to a stranger glancing at the screen — different accent palette, different shell density, different hero treatment.
