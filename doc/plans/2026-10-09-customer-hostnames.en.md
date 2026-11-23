# Customer hostnames — brief, UX contract and implementation plan

Status: **READY_FOR_IMPLEMENTATION**. Research/planning only; application implementation and verification are future work. Date: 2026-10-09.

> The standalone management-page/sidebar proposal below is superseded by [Customers + hostnames merge](2026-10-09-customers-hostnames-merge.en.md). Keep this historical brief for the binding, validation, concurrency and public-routing contract; current management URLs and composition are documented in the merge plan and developer reference.

This plan follows `AGENTS.md`, then the product-owner and UX-designer role files. The requested bilingual `doc/plans/` files hold the downstream brief/design/plan instead of the role's default UX-document location. Preserve all existing uncommitted shortcut, website, captcha, route, schema, locale, reference and spec work. This decision supersedes only the deployment hostname-map proposal in `2026-10-08-page-shortcuts.*.md`; inspected current source is the baseline for other behavior.

## 1. Product-owner brief

### 1. Problem statement

The platform owner needs to store and manage each customer's shortcut hostnames in the database, so customer selection can change immediately without editing process configuration. A customer may have several hostnames, but a hostname must identify exactly one customer. The existing shortcut feature already provides host-aware routing; this change gives that mapping a persistent, owner-only management surface while retaining established public routing and tenant isolation.

### 2. User stories

- **S1:** As an **owner**, I want to add, edit and remove hostname-to-customer mappings, so that I can manage dedicated shortcut addresses centrally.
- **S2:** As an **owner**, I want to see mappings for inactive customers and reach management from related screens, so that I can diagnose and maintain saved bindings.
- **S3:** As a **member**, I want published shortcut addresses to select the intended customer consistently, so that I reach the correct public content under the established access rules.

### 3. Acceptance criteria

| Story | Observable criteria |
|---|---|
| S1 | Only the platform owner at `/81721200/admin/maintenance/platform/customer_hostnames` can read or mutate mappings. A customer can have multiple globally unique canonical hostnames. Create/reassignment offers existing active customers with name + ID labels. Invalid submissions return 422 with retained input; successful mutations return 303 with translated feedback. |
| S2 | Inactive-customer bindings remain listed with saved hostname, customer name/ID and Unavailable status. Such bindings can be removed or reassigned to an active customer. Owner-only links appear in the platform sidebar, shortcut management and customer details. Soft-delete/restore changes displayed availability and routing without deleting/recreating the binding. |
| S3 | Unprefixed paths select the exact host's saved customer or default `81721200` when unmapped. Explicit eight-digit prefixes take priority over host selection. A binding to an inactive customer produces 404 rather than serving another customer's content. Committed mapping changes affect the next request without restart, preserving public GET/HEAD and eligible public-form POST behavior. |

### 4. Edge cases and error scenarios

- Anonymous access follows sign-in handling; admin/member access is denied; even an owner on another customer's platform prefix cannot manage mappings. Query/body customer IDs cannot replace the URL authorization context.
- Empty mapping list, no active customer options, long hostnames/customer names, failed create/update, stale edit/delete IDs, and inactive retained selections must render coherently.
- Canonical duplicates, including concurrent submissions, produce a hostname error without partial reassignment. A customer becoming inactive or being permanently deleted during save is rechecked/handled; unavailable database errors must not select another tenant.
- Subdomains do not inherit a parent's binding. Schemes, ports, paths, userinfo, wildcards, malformed labels and noncanonical customer IDs are rejected by existing policies.

### 5. Out of scope

DNS records, domain ownership verification, certificates/TLS, ingress configuration, automated Rails HostAuthorization updates, wildcard hostnames, bulk import, tenant-editable host configuration and new roles are outside this feature. There is no environment/hash compatibility path or automatic import.

### 6. Open questions

None blocking. Defaults: one global list; hostname-sorted rows; native edit-in-place form; retain-only inactive customer selection on existing records; permanent customer deletion cascades bindings.

```text
## RETURN
problem_statement: Persist exact customer hostname bindings with immediate lookup and owner-only management.
user_stories:
  - S1: Owner manages hostname bindings centrally.
  - S2: Owner maintains unavailable bindings and discovers the management surface.
  - S3: Member reaches the intended customer's public content under existing access rules.
acceptance_criteria:
  story_1: [owner and exact platform prefix required, unique canonical CRUD, active customer options, 303/422 feedback]
  story_2: [inactive bindings retained, removal/reassignment available, three discovery locations, restore refreshes availability]
  story_3: [exact host/default selection, explicit prefix priority, inactive binding returns 404, next-request visibility]
edge_cases: [authorization attempts, empty states, normalization and uniqueness races, customer lifecycle]
out_of_scope: [DNS/TLS/ingress, automated host authorization, wildcards/import, tenant hostname administration]
open_questions: []
ready_for_brainstorm: true
notes: Parent technical decisions are settled; proceed to the UX and build contract below.
```

## 2. Research and settled technical contract

- `PageShortcuts::Hosts` currently uses Addressable normalization and `parse` to build a frozen `config.x.page_shortcuts.hosts` from `PUBLIC_PAGE_HOSTS`. Replace the map only: preserve `normalize`, `customer_id(host)`, `dedicated?(host)`, `prefix` and `path` interfaces.
- Add `CustomerHostname`: `hostname` non-null, maximum 253 bytes, canonical value from `PageShortcuts::Hosts.normalize`; `customer_id` non-null bigint, indexed foreign key to `customers`; timestamps; **global unique index on `hostname`**, not `(customer_id, hostname)`. Many bindings per customer; no mapping status/enable flag.
- Keep a thin model with normalization/persistence invariants; use a Reform contract and Trailblazer Save/Destroy activities for management. Reuse Addressable; do not introduce another parser. Validate canonical uniqueness on create/update excluding the edited row; the unique index decides concurrent conflicts.
- `Hosts.customer_id(host)` normalizes input and reads the mapping's scalar `customer_id` directly from `CustomerHostname`, otherwise returns `config.x.page_shortcuts.default_customer_id` (still `81721200`). `dedicated?` checks exact mapping existence. Invalid/nil host is unmapped. Neither lookup joins/filter-scopes active customers, nor rescues DB failures into the default tenant.
- Lookups are live database queries, with no process/global cache, memoized hash or Rails cache. Use uncached lookup where necessary so repeated calls after an in-process mutation also see current rows. The resolver's existing per-request host/path result cache remains a route-resolution snapshot; presentation snapshots must not become a hostname registry.
- Delete `Hosts.parse`, its JSON-only dependency, the environment read, `to_prepare` mapping assignment, and all runtime `config.x.page_shortcuts.hosts` use. Keep the default-customer initializer setting. Boot/route drawing must not query mappings. No legacy fallback/import logic.
- `Resolver.resolve` already extracts explicit customer prefixes before host lookup and checks `Customer.exists?`; `unavailable_root?` already treats a dedicated inactive customer as terminal. Keep that division: binding existence selects CID even when its customer is inactive, then availability returns 404, never default/another customer. Preserve existing root bootstrap behavior for an unmapped shared host and absent default customer.
- `Customer` hides inactive rows through `default_scope { visible }`. Use its normal active scope for selectable customers; load saved binding labels/status with a deliberate unscoped customer association or batched `Customer.unscoped` lookup. Rendering must not lose the inactive customer's identity or issue per-row queries.
- New assignment/reassignment requires an existing active customer and strict eight-digit ID parsing via `PageShortcuts::PathPolicy.customer_id`. An unchanged inactive customer on an existing binding is retain-only and may keep its identity during a hostname edit. Soft-delete retains bindings; restore makes them eligible again. Add `Customer#customer_hostnames` with `dependent: :destroy` and foreign-key `on_delete: :cascade` for permanent deletion; nonexistent IDs cannot be saved.
- Mapping commits change routing lookup immediately; **DNS, TLS, ingress and Rails HostAuthorization remain independently deployment-managed**. A saved binding does not admit a host to Rails' allowlist or prove network reachability. Do not implement a custom HostAuthorization layer.

## 3. UX contract

### 3.1 Surface inventory and discovery

| Surface | Navigation area | Behavior |
|---|---|---|
| `/81721200/admin/maintenance/platform/customer_hostnames` | Admin → Maintenance → Platform → Customer hostnames | Global list plus add/edit form; platform owner only. |
| Platform sidebar | Admin → Maintenance → Platform | Add Customer hostnames beside Customers within the existing owner + `81721200` condition. |
| `/:cid/admin/maintenance/page_shortcuts` | Admin → Maintenance → Page shortcuts | Owner-only secondary Manage customer hostnames link, targeting the fixed platform URL with this customer preselected if active. |
| `/81721200/admin/maintenance/platform/customers/:id` | Admin → Maintenance → Platform → Customers | Same small discovery component beside the details content, targeting the fixed platform URL with the displayed customer preselected if active. |

The management index stays global. Optional `?for_customer=<cid>#hostname-form` preselects only an active form option and never narrows authorization or replaces the platform URL CID. An unavailable suggested customer shows an informational message and a blank selection, not an arbitrary default.

### 3.2 Layout and data

```text
Maintenance / Platform / Customer hostnames
Customer hostnames                         [normal admin shell]
Map hostnames to customers for public shortcut routing.

[ Add hostname / Edit hostname                           ]
[ error summary, when needed                            ]
[ Hostname input          Customer native select        ]
[ field hints/errors      Name (12345678)                ]
[ Add hostname / Save     Cancel (edit only)             ]

[ Saved hostnames                                       ]
[ Hostname | Customer name + ID | Availability | Actions ]
[ example.com | Acme (12345678) | Available | Edit Remove ]
[ old.example | Legacy (23456789) | Unavailable | ...     ]
[ Removal keeps the customer and its pages.              ]
```

- Reuse `AdminPageComponent` for localized breadcrumbs/title/description and dashboard width. Inside `min-w-0 space-y-6`, use two full-width `CardComponent(padding: :none)` cards with `p-4 sm:p-6` regions. Flash is rendered once by the existing dashboard shell.
- Form: `grid grid-cols-1 gap-4 md:grid-cols-2`; explicit labels; hostname text input (`font-mono`, `autocapitalize="none"`, spellcheck off); customer native select with `[label, cid]` options. Fields use existing `form-label` / `input-field min-h-11 w-full` conventions. Actions stack full-width on mobile and become intrinsic from `sm`.
- Saved list is sorted by canonical hostname then ID. Use the sibling shortcut component's semantic table from `md`, stacked card-like rows below `md`, visible translated mobile labels, wrapping names and `break-all` hostname text. Columns show saved hostname, customer name + numeric ID, derived availability, Edit and Remove. Display hostnames as text; status means customer activity, not DNS/TLS or page publication.
- Reuse `ButtonComponent`, `BadgeComponent`, `EmptyStateComponent`, and `AlertComponent(auto_dismiss: false)`. Available uses the success badge; inactive customer uses neutral Unavailable. Edit is secondary, Remove danger, Save/Add primary, Cancel secondary. Keep all row actions available for inactive bindings.

### 3.3 Component contract and reuse

```ruby
CustomerHostnames::ManagementComponent.new(
  hostnames: hostnames,
  available_customers: available_customers, # [[translated_name_and_id_label, cid], ...]
  customer_id: 81721200,                   # platform URL context, not the selected customer
  errors: [], form_values: {}, editing_hostname: nil
)
CustomerHostnames::ManagementLinkComponent.new(
  current_user: current_user, target_customer_id: target_customer_id
)
```

The initializer requires `hostnames:` and `available_customers:`; defaults are `customer_id: 81721200`, `errors: []`, `form_values: {}` and `editing_hostname: nil`. `form_values` contains `hostname` and `customer_id`; submitted values take precedence over the editing record, and missing create values stay blank. `errors` supports an attribute-to-messages hash as well as a base-message array, matching `PageShortcuts::ManagementComponent`. `hostnames` supplies saved records with batched/preloaded customer identity including inactive records. `available_customers` supplies active options only, sorted by name then ID, with localized name + ID formatting.

The small `ManagementLinkComponent` wraps the existing secondary button/link styling, renders only for `current_user.platform_owner?`, always links to platform CID `81721200`, and adds `for_customer` when given a target. Mount it on shortcut management and customer details; keep the sidebar on its existing contributor pattern. It owns no mapping queries. `Admin::Maintenance::Platform::SettingsLinkCardComponent` is a visual discovery reference; a compact secondary link better fits these two existing surfaces.

### 3.4 Native interaction flows and states

- Create: index → enter hostname/select customer → native POST → successful atomic save → 303 index + translated flash. Edit: row Edit → GET index `?edit=<id>#hostname-form` → same prefilled card → native PATCH → 303 index. Cancel is a normal GET back to index. Remove is `button_to`, native DELETE via hidden method → 303 index; customer/pages stay intact. No confirmation modal.
- Mutation parameters are only `customer_hostname[hostname]` and `customer_hostname[customer_id]`. Index `edit` looks up a globally managed record only after authorization. Routes expose `index/create/update/destroy`, not separate new/edit screens.
- Validation failure: render full index at 422, preserve attempted values/edit identity, alert summary and field-linked errors; leave saved rows unchanged. Duplicate race is a hostname error. Missing edit/update/delete record returns 404.
- Inactive edited customer: append only the record's original unavailable customer as a retained selection outside the active-option list. It can remain for hostname-only save or be replaced by an active customer; it cannot be used for a new binding or another binding's reassignment. Never silently select a different customer after failure.
- Empty list: keep form visible and show No hostnames yet. No active customers: explain the state and link to platform Customers; disable new assignment submission. Existing inactive bindings can still be deleted, and an existing retain-only hostname edit remains possible.
- Loading is a normal browser navigation; no dynamic skeleton or feature-specific JavaScript. Operational failures use normal Rails error handling; DNS/TLS/vendor state is not probed on this page. Permission denial uses existing auth handling; an owner with a wrong platform CID receives 404 before any mapping query/mutation.
- Accessibility: unique field IDs/labels, required fields, `aria-invalid`, `aria-describedby` hint/error IDs, `role="alert"` error summary, table caption and scoped headers, visible focus, hostname-specific translated action labels and at least 44 px targets. All management forms and edit/cancel links use `data-turbo="false"`; verify with JavaScript disabled.

### 3.5 Localized copy and design reference

Use paired `config/locales/customer_hostnames.en.yml` / `.zh-CN.yml` plus sidebar keys in paired `chrome` files. Reuse identical existing common action/status strings. All other headings, hints, validation, flashes, option formats and accessibility labels use I18n at call time with interpolation parity.

| English copy | 简体中文 |
|---|---|
| Customer hostnames | 客户主机名 |
| Manage customer hostnames | 管理客户主机名 |
| Add hostname / Edit hostname / Saved hostnames | 添加主机名／编辑主机名／已保存的主机名 |
| Hostname / Customer / Availability | 主机名／客户／可用状态 |
| Choose a customer | 请选择客户 |
| `%{name} (%{id})` | `%{name}（%{id}）` |
| Available / Unavailable | 可用／不可用 |
| Enter an exact hostname without a scheme, port or path. | 请输入完整主机名，不含协议、端口或路径。 |
| Availability reflects customer status, not DNS or TLS readiness. | 可用状态仅反映客户是否启用，不代表 DNS 或 TLS 已就绪。 |
| DNS, TLS, ingress and Rails HostAuthorization are configured separately by deployment. | DNS、TLS、入口路由及 Rails HostAuthorization 允许列表由部署单独配置。 |
| Removing a hostname keeps the customer and its pages. | 移除主机名不会删除客户及其页面。 |
| No hostnames yet / No active customers available. | 暂无主机名／暂无可选的启用客户。 |
| This hostname is already assigned to a customer. | 此主机名已绑定客户。 |
| Choose an existing active customer. | 请选择已存在且已启用的客户。 |

Official shadcn [Input](https://ui.shadcn.com/docs/components/input), [Card](https://ui.shadcn.com/docs/components/card), [Native Select](https://ui.shadcn.com/docs/components/native-select), and [Table](https://ui.shadcn.com/docs/components/table) were fetched before inspecting project components. Apply their label/hint/error, card-region, native mobile-select and semantic-table patterns through project ViewComponent/Tailwind conventions. The shadcn skill/MCP is unavailable in this harness; these official references provide the requested design consultation.

```text
## RETURN
ux_doc: doc/plans/2026-10-09-customer-hostnames.en.md
surfaces:
  - name: Customer hostname management
    nav_area: admin
    new_components: [CustomerHostnames::ManagementComponent]
    reused_components: [AdminPageComponent, CardComponent, ButtonComponent, BadgeComponent, EmptyStateComponent, AlertComponent]
  - name: Owner discovery in shortcut management and customer details
    nav_area: admin
    new_components: [CustomerHostnames::ManagementLinkComponent]
    reused_components: [ButtonComponent]
  - name: Platform sidebar discovery
    nav_area: admin
    new_components: []
    reused_components: [MaintenanceContributor, SidebarNode]
overall: READY_FOR_FRONTEND
notes: Use the requested plan location; native forms, responsive rows and existing admin shell settle the implementation choices.
```

## 4. Ordered implementation tasks and filenames

1. **Backend — persistence and validation.** Add `db/migrate/<next_timestamp>_create_customer_hostnames.rb`, `app/models/customer_hostname.rb`, `spec/factories/customer_hostnames.rb`; extend `app/models/customer.rb`; regenerate `db/schema.rb` without discarding the pending PageShortcut migration/schema. Add `app/services/customer_hostnames/contracts/hostname.rb`, `activities/save.rb`, `activities/destroy.rb`. Normalize before validation/persistence, validate strict CID/active assignment or unchanged inactive retention, transact updates, recheck customer availability on save, and translate uniqueness/FK race failures into stable errors. Specify DB uniqueness/FK and soft-delete/restore/hard-delete behavior in model/activity specs.
2. **Backend — live host lookup.** Change `app/services/page_shortcuts/hosts.rb` and `config/initializers/page_shortcuts.rb` as in section 2. Keep resolver/public-path/captcha APIs and route order. Replace every config-map stub/assignment in specs with actual `CustomerHostname` rows, retaining only default-CID overrides where existing tests need them. Remove obsolete parse/`invalid_hosts` locale keys from both `page_shortcut_errors` files. Run a repository content search for `PUBLIC_PAGE_HOSTS`, `config.x.page_shortcuts.hosts`, `config.hosts` assignments/stubs and `Hosts.parse`; distinguish deployment Rails `config.hosts` from the removed shortcut map.
3. **Security — routes/controller.** Add `resources :customer_hostnames, only: %i[index create update destroy], controller: "maintenance/platform/customer_hostnames"` inside the existing platform scope in `config/routes.rb`. Add `app/controllers/admin/maintenance/platform/customer_hostnames_controller.rb`, inheriting `ApplicationController` and `dashboard_menu_item :maintenance`. Reuse `RouteAuthorization`'s authentication/platform-owner/CanCan pipeline; add a local exact **URL** `request.path_parameters[:customer_id].to_s == "81721200"` guard (404 on mismatch) for every action before binding access. Do not substitute merged query/body params, the selected body CID/current acting tenant or globally change other platform controllers' policy. Authorized record lookup is global by binding ID, since these are owner-managed mappings. Permit only the two nested fields; query suggested/selected customers separately. Use `admin_maintenance_platform_customer_hostnames_path` and `admin_maintenance_platform_customer_hostname_path` with fixed platform CID, 303 success and 422 validation renders.
4. **Frontend — management/discovery.** Add `app/components/customer_hostnames/{management_component,management_link_component}.{rb,html.erb}` and `app/views/admin/maintenance/platform/customer_hostnames/index.html.erb`. Mount the small discovery component in `app/components/page_shortcuts/management_component.html.erb` and `app/views/admin/maintenance/platform/customers/show.html.erb`; update `app/services/maintenance_contributor.rb` inside its existing exact owner/platform-customer branch. Add both feature locale files and matching sidebar translations. Follow section 3's component API, active options, unscoped saved identities, no-JS CRUD and responsive/accessibility states.
5. **Documentation — same implementation change.** Add `doc/reference/{en,zh-CN}/customer-hostnames.md` with parity in front matter and required Summary/Flow/Implementation/Where to pay attention/Key code sections, and register `customer-hostnames` beside `customers` in `app/services/developer_docs/catalog.rb`. Update both locales of `page-shortcuts.md` to replace environment/hash setup with database management and independent HostAuthorization, `customers.md` for discovery/lifecycle, `tenancy-and-roles.md` for exact-prefix authorization, and `system-map.md` for the new surface. Cross-link related website/public rendering references where host selection is discussed. Sweep references for old config claims; keep prior plans clearly historical/superseded, not a runtime compatibility instruction.
6. **QA/release/review.** Use the acceptance matrix below, then asset build and authenticated owner smoke-testing at the requested viewports. Route/auth changes warrant the full regression suite after focused checks. Follow `AGENTS.md` asset-shadowing/restart instructions if restarting; authenticated authorization tests must exercise real roles. Finish convention/security review and report actual results. Human reviewer commits.

When implementation is authorized, hand these lanes to the anysys backend/frontend/security roles, then QA/release and tech-lead/code-reviewer. This planning change creates only the two requested documents.

## 5. Acceptance tests and verification

| Test location | Required assertions |
|---|---|
| `spec/models/customer_hostname_spec.rb`, `spec/models/customer_spec.rb` | Case/trailing-dot/Addressable IDN canonicalization; valid label/253-byte limits; rejected malformed input; global canonical uniqueness across customers; multiple hosts for one customer; indexed FK rejection of nonexistent customer; inactive retention, restore and permanent-delete cascade. |
| `spec/services/customer_hostnames/contracts/hostname_spec.rb`, `activities/{save,destroy}_spec.rb` | Active-only create/reassignment, retain-only unchanged inactive CID, normalized update excluding self, genuine unique-index enforcement plus activity race error handling, missing/inactive customer at persistence, atomic failure leaves old binding intact. |
| `spec/services/page_shortcuts/hosts_spec.rb` | Exact matching, no wildcard inheritance, invalid/nil default, default 81721200, two hosts per customer, dedicated inactive binding still returns saved CID/true; create/change/reassign/delete followed by repeated lookup sees committed DB state without cache reset. |
| `spec/requests/admin/maintenance/platform/customer_hostnames_spec.rb` | Anonymous/admin/member denied for every action; owner on exact platform CID succeeds globally; owner on other active CID's platform prefix denied before reads/writes; forged body/query IDs do not bypass guard; native create/edit/PATCH/DELETE, 303 flashes, 422 field retention, missing ID 404, inactive rows visible/removable. |
| `spec/components/customer_hostnames/{management_component,management_link_component}_spec.rb`, existing shortcut component/customer request/sidebar specs | Component API/defaults, available `[name + id, cid]` options, unavailable retained edit option, empty/no-active states, escaped labels, error summary/field ARIA, CSRF/method/native forms, responsive classes, owner-only fixed-platform discovery and optional preselection; both locales/key parity. |
| Existing `spec/services/page_shortcuts/{resolver,public_path,public_path_integration,public_path_lookup}_spec.rb` and `spec/requests/page_shortcuts*_spec.rb` | Real binding rows replace hash setup; prefix precedence, default/shared host, immediate next-request mapping changes and public link prefixes, inactive root/non-root 404 even with an eligible default home, restore, GET/HEAD/public-Page POST, mounted paths, canonical routes, shared overrides and tenant isolation. |
| Existing captcha shortcut specs and `spec/requests/route_authorization_spec.rb` | Alias throttling/replay re-resolves live binding; mappings never relax admin/member guards, trusted target identity or existing cross-tenant rules. No new host-authorization middleware. |
| `spec/services/developer_docs/repository_spec.rb` | Both new reference pages appear in the catalog, render required headings and valid cross-links; related references no longer prescribe environment/hash setup. |

The old `page_shortcuts_review_spec.rb` inserts a nonexistent CID through a hash. Replace that unreachable-with-FK fixture with a real customer mapped while active then soft-deleted; separately assert nonexistent-CID save/FK rejection. Keep the distinct shared-host bootstrap test where platform customer 81721200 is absent and no binding exists.

Run focused specs for every changed layer and updated host fixture first, including all shortcut/captcha integration files identified by the config-map search. Then run `bin/rails parallel:prepare && bin/rails parallel:spec` when supported, otherwise `bundle exec rspec`. Rebuild Tailwind using `bin/rails tailwindcss:build`. No feature JavaScript is planned; if implementation changes JS, add/update mirrored tests and run `npx vitest run --coverage`, requiring touched files at 100% lines/branches/functions.

Browser acceptance: owner create/edit/remove with JavaScript disabled; EN and zh-CN at 320/390/768/1024/1440 px and 200% zoom; long canonical hostname/name wrapping; keyboard labels/focus; inactive saved binding and failed edit. Confirm mapping changes on an already deployment-admitted host without application restart; separately demonstrate/document that saving an unadmitted hostname does not modify Rails HostAuthorization, DNS, TLS or ingress.

## 6. Handoff checklist

- [ ] Database schema and canonical uniqueness/FK behavior implemented.
- [ ] Runtime hostname environment/hash removed; live APIs, default and explicit-prefix priority verified.
- [ ] Owner-only exact-prefix CRUD, retained inactive mappings and three discovery locations verified.
- [ ] Responsive native management components and paired I18n implemented.
- [ ] Bilingual developer references/catalog updated with deployment boundary.
- [ ] Focused/full checks and browser acceptance recorded with real results; prior uncommitted work preserved.
