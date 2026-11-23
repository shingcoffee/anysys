# Page shortcuts — implementation and UX contract

Status: proposed design; ready for implementation planning. Source inspection and documentation research only.

## 1. Decisions and URL behavior

- Use Rails 8.1.2 Action Dispatch/Journey root, glob and request constraints. Use the existing `addressable` dependency (locked at 2.8.8) for URI parsing and query/fragment preservation. Add no rewrite middleware or `rack-rewrite` dependency.
- Render aliases directly through `Websites::PagesController#home`, `#show` or `PublicPagesController#show`; keep the alias in the address bar. Retain all existing site, media, public-page and submission endpoints.
- `config.x.page_shortcuts.hosts` is an exact, normalized hostname-to-customer-ID hash; `config.x.page_shortcuts.default_customer_id` defaults to `81721200`. Host configuration is deployment configuration, not a tenant-editable field. Configure accepted dedicated hosts in Rails HostAuthorization too.
- For an unprefixed request, the host mapping selects the customer, otherwise the default customer is selected. An explicit eight-digit customer prefix always selects that customer. Do not infer a customer from a signed-in user's session.

| Public URL | Resolution |
|---|---|
| `/` on the shared host | Customer 81721200's home, when module, site and home page are published; otherwise existing `HomeController#index` behavior |
| `/pricing` on the shared host | Published platform website inner slug `pricing`, automatically |
| `/join` on the shared host | Customer 81721200's explicit shortcut `/join` |
| `/12345678/pricing` or `/12345678/join` | Customer 12345678's automatic website slug or explicit shortcut |
| `/` or `/pricing` on a host mapped to 12345678 | That customer's published home or inner page |
| `/12345678/` | That customer's published home; unavailable home returns 404 |

Only GET/HEAD aliases are supported. Public form pages continue to POST to `/:cid/page/:uuid`; forms must use an explicit existing submission helper, not the current alias path. Unmatched non-root aliases return the normal 404. Root fallback retains HomeController's signed-in landing redirect as well as anonymous sign-in rendering.

## 2. Persistence, eligibility and collisions

- `PageShortcut`: required `customer_id`, `path`, `target_type`, `target_id`, plus timestamps. Unique database index on `(customer_id, path)`; customer foreign key and target lookup index. No `enabled` column: deleting a row removes that explicit mapping.
- Allowlist target types `WebsitePage` and `Page`. Parse submitted `target` as `WebsitePage:<id>` or `Page:<id>` through that allowlist; never constantize arbitrary input. Derive `customer_id` from the authorized URL context, not the submitted form.
- Website targets must belong to the shortcut customer and its website. Availability requires the Website module, site and page to be published. Home-page targets dispatch to `#home`; inner targets dispatch to `#show` with the record's current slug.
- Page targets must be active, launched, public-visible and accessible to the shortcut customer: customer-owned or shared (`customer_id NULL`). Shared definitions resolve under the selected customer's `Current.customer` and `resolved_current_version`. An owner managing another customer still cannot point its shortcut at a third customer's private row.
- Offer only currently eligible targets for creation. Keep existing rows when targets go offline; show derived `Unavailable` status and return 404 until eligibility returns. Missing targets are removable records, never exceptions that break the index. Recheck eligibility on every request.
- Canonical stored paths have one leading slash and lowercase kebab-case segments, e.g. `/join` or `/campaign/spring`; accept a missing leading slash and normalize one trailing slash. Reject empty paths, `/`, repeated slashes, dots/dot segments, percent escapes, backslashes, controls, embedded whitespace, schemes, hosts, queries and fragments. The UI takes the tenant-relative path; it does not take `/12345678/join`.
- Reserve `/`, eight-digit leading segments and application namespaces, including `admin`, `member`, `auth`, `oauth`, `locale`, `up`, `captcha`, `payments`, `sms`, `email`, `unsubscribe`, `page`, `site`, `site-images`, `assets`, `rails` and `.well-known`. Check segment boundaries, not loose prefix matching. Maintain one path policy used by validation and runtime resolution; compare it against `config/routes.rb` in routing specs.
- Reject an explicit shortcut colliding with an automatic website slug, including an unpublished inner page's slug. Reject even same-target duplicates for the initial design. Automatic website routes have no PageShortcut rows and cannot be removed here.
- Validate the reverse collision when creating/changing/publishing website slugs. Existing reserved website slugs remain reachable through `/:cid/site/:slug`, but receive no clean automatic URL. If pre-existing data produces an explicit/automatic collision, the website route wins and the explicit mapping is unavailable; never silently redirect an old alias to an unrelated target.

## 3. Routing and tenant callback contract

1. Add an unnamed constrained GET `/` to the existing website home action before the named `root "home#index"`; the constraint requires a publicly available home. Preserve the single named `root_path` helper and fallback.
2. Append GET/HEAD-compatible `/:customer_id/*shortcut_path` and `/*shortcut_path` routes after existing endpoints, with `format: false`. Use fixed controller/action destinations with small request constraints for website home, website inner page and public Page targets.
3. `PageShortcuts::Resolver` returns a typed resolution containing `customer_id`, target identity, destination kind and canonical `page_slug` or `uuid`. Resolve against explicit customer scopes; routing constraints execute before `Current.customer` is set. Read `request.host` and `request.path_info`, not query/body parameters or mutable `req.params`.
4. Memoize lookup results only in the request environment, keyed by host/path. Constraints select the destination; they do not mutate PATH_INFO, SCRIPT_NAME, Current or route parameters. Resolve at request time; do not load DB rows while drawing routes.
5. Include `PageShortcuts::RouteContext` in the two existing public controllers, with a prepended callback restricted to shortcut routes. Copy trusted resolution into `params[:customer_id]` (the actual project key, not `:cid`), `params[:page_slug]` or `params[:uuid]`, and call the existing `set_current_tenant(customer_id, true)` before normal callbacks. Stop after a tenant failure. Merely injecting params does not work: `TenantContext#auto_set_tenant_from_path` reads the actual path.
6. Preserve existing tenant policy: anonymous visitors can read any tenant's published public resources; signed-in non-owner cross-tenant requests retain TenantContext's existing rejection. Do not assign Current directly to bypass that guard. The existing owner-context setup and all publication/visibility checks still execute. Unknown/disabled/deleted targets fail closed without falling back to another target at the same path.

## 4. Public link generation

- Introduce a thin `PageShortcuts::PublicPath` interface shared by website links, displayed admin addresses and public Page links. On a matching dedicated host or the shared default-customer host, generate `/` and `/pricing`; otherwise generate `/:cid/` and `/:cid/pricing`. Prefix explicit shortcuts using the same rule.
- Prefer automatic website paths; use the legacy site path when a slug is reserved. For public Pages with several live shortcuts, select the lexically first canonical shortcut deterministically; otherwise use `public_page_path`.
- Integrate with `Websites::Href`, `PublicComponent#href_for`, `NavComponent#home_href`, scoped HomeSite chrome, footer/section links and displayed site/page addresses. Translate valid legacy local website/Page destinations at render time; preserve query pairs, fragments and locale through Addressable. External HTTPS URLs, media URLs and unrelated application paths keep their established handling.
- Keep the current `Websites::Href.resolve` call usable without a request host (existing service/spec callers): the path interface uses explicit host input when available and a documented shared-host default otherwise. Batch/prefetch shortcut candidates for lists and navigation.

## 5. Surface inventory and layout

| Surface | Navigation area | Contract |
|---|---|---|
| `/:cid/admin/maintenance/page_shortcuts` | Admin → Maintenance → Page shortcuts | One management screen for current-customer mappings |
| Existing Maintenance landing/sidebar | Admin → Maintenance | Card and sidebar leaf linking to management |
| Website settings publication card | Admin → Settings → Website | Clean site address and secondary `Manage page shortcuts` link |
| Tenant Maintenance → Pages index | Admin → Maintenance → Pages | Secondary management link; keep it off platform shared-resource management |
| Published website/public-page aliases | Public | Existing rendering/layout; clean navigation and URL |

Management layout: `AdminPageComponent` supplies Maintenance → Page shortcuts breadcrumbs, localized title/description and normal dashboard width. The body is `space-y-6`, with two full-width cards in source order:

1. **Add shortcut card:** heading and description; server error summary; Path input; Destination native select; helper text; primary Add shortcut button. Fields use `grid grid-cols-1 gap-4 md:grid-cols-2`, `min-w-0`, visible `form-label`, `input-field min-h-11 w-full`; path is `font-mono`. Actions are full width on mobile and intrinsic from `sm`. Explain that website home/inner URLs are automatic and the entered path is customer-relative.
2. **Saved shortcuts card:** Path/public link, Destination (type + saved title/name), Availability, Actions. From `md`, use a semantic table; below `md`, use stacked rows with visible translated labels and wrapping paths (`break-all` where needed). Remove is a per-row form button in danger styling. Link only available targets. Sort by path. Automatic routes are explained separately, not mixed with deletable rows.

Use shadcn Card's header/description/content/footer composition, Input/Field's label/helper/error relationships, semantic Table structure and Native Select's mobile-native interaction, delivered as ViewComponent + Tailwind.

Reuse `AdminPageComponent`, `CardComponent` (`padding: :none` with `p-4 sm:p-6` regions), `ButtonComponent`, `BadgeComponent`, `EmptyStateComponent`, `AlertComponent` (without auto-dismiss) and `QuickActionCardComponent`. Build `PageShortcuts::ManagementComponent` to own the native form and responsive table/rows. The existing `AdminTableComponent` is a visual reference; its destructive links depend on Turbo and do not satisfy this surface's no-JS action contract. `FormErrorsComponent` requires a resource, so use AlertComponent plus field errors with the proposed `errors` input.

## 6. Component, actions and states

Required component inputs: `shortcuts:`, `available_targets:`, `customer_id:`; optional `errors: {}`. `available_targets` is an array of `[display_label, "WebsitePage:<id>" | "Page:<id>"]`; labels combine translated type names and escaped record titles. Preload targets and compute availability under the current URL customer. Extend with `form_values: { path: "", target: "" }` to retain failed input, and `editing_shortcut: nil` for the recommended update flow.

- Create: `form_with scope: :page_shortcut`, action `admin_maintenance_page_shortcuts_path(customer_id)`, POST, fields `page_shortcut[path]` and `page_shortcut[target]` only.
- Remove: `button_to` the singular `admin_maintenance_page_shortcut_path(customer_id, shortcut)`, DELETE via Rails' hidden method input and CSRF token. State clearly that removing a shortcut keeps its page. Native submission; no confirmation modal.
- Recommend REST `index/create/update/destroy`. Edit is a normal GET to the index with `edit=<scoped id>#shortcut-form`; reuse the card, prefilled, with PATCH to the singular helper, Save and Cancel. Updating is atomic; remove/recreate causes an avoidable availability gap. No separate edit screen is required.
- Mutations use tenant-scoped Activities plus a Reform contract. Management inherits `RouteAuthorization`'s admin/owner gate; find every row by `(customer_id, id)` even for owner sessions. Successful mutations return 303 to the index with a localized flash; invalid input returns the whole index at 422 with values and per-field errors.
- Empty list: localized EmptyState explaining that website URLs are automatic; leave the form visible. No eligible targets: disable select/submit and link to relevant page publishing screens. An edited unavailable target remains identifiable and removable; do not silently select another destination.
- Accessibility: explicit input IDs/labels, required fields, `aria-invalid` on failed fields, `aria-describedby` linking hint and error IDs, error summary with `role="alert"`, table caption/header scopes, 44 px action targets, visible focus and unique per-row control IDs. Native keyboard select/forms; no feature-specific JavaScript or loading skeleton. All management forms opt out of Turbo and work with JS disabled.

## 7. Localized wording

Put feature keys under `maint_core.page_shortcuts` in both `config/locales/maint_core.en.yml` and `.zh-CN.yml`; add the sidebar label to both `chrome` files and reuse existing common action keys where English is identical. Translate validation errors, flashes, descriptions, headings, placeholders, type labels and accessibility labels. Resolve translations at call time.

| English | 简体中文 |
|---|---|
| Page shortcuts | 页面快捷路径 |
| Add shortcut | 添加快捷路径 |
| Path | 路径 |
| Destination | 目标页面 |
| Enter a path such as /join. Website page URLs are created automatically. | 输入路径，例如 /join。网站页面的访问路径会自动生成。 |
| Website page / Public page | 网站页面／公开页面 |
| Available / Unavailable | 可访问／不可访问 |
| No shortcuts yet | 暂无快捷路径 |
| Removing a shortcut keeps the page. | 移除快捷路径不会删除页面。 |
| This path is reserved by the application. | 此路径为系统保留路径。 |
| This path is already used by a website page. | 此路径已被网站页面使用。 |
| This destination is not publicly available. | 此目标页面当前不可公开访问。 |

## 8. Implementation sequence and acceptance

1. Backend: migration/thin model; shared path/target policy; save/destroy Activities and Reform contract; resolver and host configuration. Include reverse website-slug collision validation.
2. Routing: fixed-destination constraints and callback concern; root availability/fallback; public path interface and existing link/address integration.
3. Frontend: management ViewComponent, native forms, update flow, discovery links and paired translations.
4. Documentation: during implementation, add `page-shortcuts.md` in both `doc/reference/en/` and `doc/reference/zh-CN/`, register it in `DeveloperDocs::Catalog`, and update/cross-link `websites`, `website-builder`, `page-rendering`, `member-and-public`, `tenancy-and-roles` and `system-map` where affected. This proposal does not describe the feature as already deployed.
5. Verification: focused model/contract/activity/resolver/path/component/admin-request/public-request specs; include existing home, website-public, Href, public-page visibility/submission, route authorization and cross-tenant isolation specs. Since routing and tenant setup are cross-cutting, run the full suite afterward using `bin/rails parallel:prepare && bin/rails parallel:spec` when available.

Acceptance covers published `/` and `/pricing`; HomeController fallback; two tenants with the same shortcut; dedicated/shared hosts and explicit prefixes; forged cid/slug/uuid query parameters; root/namespaces/reserved slugs; unique-index race; automatic/explicit collisions in both directions; home-target aliases; unpublish/relaunch/delete; shared Page customer overrides; retained canonical GET/POST/media endpoints; HEAD support and rejection of other alias methods; locale/query/fragment preservation; scoped management permissions; 422 field retention; no-JS create/update/remove; EN/zh-CN at 320/390/768/1024/1440 px and 200% zoom.

Research: `AGENTS.md`, `.cursor/agents/anysys-ux-designer.md`, existing controllers/models/components/specs; official [Card](https://ui.shadcn.com/docs/components/card), [Table](https://ui.shadcn.com/docs/components/table), [Native Select](https://ui.shadcn.com/docs/components/native-select), user-supplied Input research, and [Rails 8.1.2 routing mapper](https://github.com/rails/rails/blob/v8.1.2/actionpack/lib/action_dispatch/routing/mapper.rb). shadcn skill/MCP are unavailable in this harness; official documentation supplies the component design reference.
