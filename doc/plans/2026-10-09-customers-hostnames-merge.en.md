# Customers + hostnames — UX design and implementation plan

Date: **2026-10-09**. Status: **READY_FOR_FRONTEND**. This is a design/planning artifact; implementation and runtime verification are downstream work.

## 1. Confirmed brief and design basis

The product owner confirmed the smallest merge: keep the existing Customers table first, then embed the complete global hostname add/edit form and saved-binding list below it, in **one `AdminPageComponent` shell**. Customers remains the sole platform-sidebar destination for this combined surface.

This document follows `AGENTS.md` and `.cursor/agents/anysys-ux-designer.md`. The requested paired `doc/plans/` paths replace the role's default output location. Inspected current working-tree components, views and controllers are the implementation baseline, including existing uncommitted hostname work. This plan supersedes the standalone hostname-page/navigation proposal in `2026-10-09-customer-hostnames.*.md`; the existing binding, validation, concurrency and public-routing behavior remains the feature contract.

The official shadcn skill/MCP tools are unavailable in this toolset. The orchestrator consulted the official [Card](https://ui.shadcn.com/docs/components/card) and [Table](https://ui.shadcn.com/docs/components/table) documentation before design. Apply their header/description/content/actions and semantic caption/header/body composition through existing Rails ViewComponents and Tailwind utilities. No React, custom CSS or new JavaScript is needed.

## 2. Surface inventory

| Surface | Navigation area | Adaptation |
|---|---|---|
| `/81721200/admin/maintenance/platform/customers` | admin → Maintenance → Platform → Customers | One page: current Customers table, hostname section heading, form card, saved-bindings card. |
| Same index with `?edit_hostname=<id>#hostname-form` | admin → Maintenance → Platform → Customers | Prefill the embedded form for the globally managed binding. |
| `/81721200/admin/maintenance/platform/customers/hostnames[/:id]` | admin → Maintenance → Platform → Customers | Native create/update/remove endpoints; validation failures render the full combined index. |
| Platform sidebar | admin → Maintenance → Platform | Keep Customers; remove the separate Customer hostnames leaf. |
| `/:cid/admin/maintenance/page_shortcuts` | admin → Maintenance → Page shortcuts | Existing owner discovery link targets fixed platform Customers index and the form anchor; optional URL-customer suggestion. |
| `/81721200/admin/maintenance/platform/customers/:id` | admin → Maintenance → Platform → Customers | Existing owner discovery link continues suggesting the displayed active customer. |

All hostname management remains platform-owner-only and locked to URL customer `81721200`. The list is global. Search, sorting and pagination apply to the Customers table only, never to hostname rows or assignment choices.

## 3. Layout specification

```text
Existing Customers breadcrumbs
Customers                                  [Trash] [New customer]
Existing Customers page description

+ Existing Customers AdminTable -------------------------+
| Existing search, columns, row actions and pagination    |
+--------------------------------------------------------+

Customer hostnames                         h2, section label
Map hostnames to customers for public shortcut routing.

+ Add hostname / Edit hostname --------------------------+
| Deployment hint                                        |
| Error summary, only after a failed action               |
| Hostname input                 Customer native select  |
| Field hint / error             Field hint / error       |
| No-active-customers message, when applicable            |
| [Add hostname / Save]          [Cancel, edit only]       |
+--------------------------------------------------------+

+ Saved hostnames ---------------------------------------+
| Removing a hostname keeps the customer and its pages.   |
| Hostname | Customer name + ID | Availability | Actions  |
| a.example | Acme (12345678) | Available | Edit Remove    |
| old.example | Old (23456789) | Unavailable | Edit Remove |
| Availability reflects customer status, not DNS/TLS.     |
+--------------------------------------------------------+
```

### 3.1 Parent page

- `app/views/admin/maintenance/platform/customers/index.html.erb` owns the single `AdminPageComponent`: existing breadcrumbs, Customers h1/description, Trash and New customer actions.
- Put the current `AdminTableComponent` and the hostname component in a `min-w-0 space-y-6` body wrapper. The Customers table stays first, with its existing columns, row links, Act as/Edit/Delete behavior, search and pagination.
- Supply the table's existing `base_path:` option with the fixed Customers index path. Its current default is an empty relative base; on a 422 response rendered from a hostname CUD URL, relative search/sort/page navigation would otherwise return to the mutation path.
- Flash feedback continues to be rendered once by the dashboard layout. The embedded component handles hostname validation errors only.

### 3.2 Embedded hostname component: precise minimal changes

- Keep `CustomerHostnames::ManagementComponent`; remove its `AdminPageComponent` wrapper and its own breadcrumbs/page title strip.
- Render a root `<section class="min-w-0 space-y-6" aria-labelledby="...">`. Add `title_id: "customer-hostnames-title"` to its initializer; use this ID for a visible h2 translated with `customer_hostnames.title`.
- Beneath the section h2, render the existing `customer_hostnames.description`. The form and saved-list card headings become h3 elements, keeping the existing `section-header` appearance and existing translations. Derived heading IDs can use the `title_id` prefix.
- Retain both `CardComponent.new(padding: :none)` cards. Keep `id="hostname-form"` on the form-card content region; there is exactly one such anchor per page. Keep `p-4 sm:p-6`, form `space-y-5` and field `min-w-0` containers.
- Retain the current native hostname/customer form, field hints/errors, active/retain-only options, escaped values, badges, public hostname links, edit actions, native removal forms and saved-list empty state.
- Add only `table_context: {}` for the four Customers-table return parameters described below. Path helpers and hidden fields use that sanitized prop.
- In the no-active-customers state, keep the explanatory text and disabled new-assignment controls. Remove the now-redundant link back to Customers from inside its own page; the existing parent customer workflows remain the way to manage customers.

### 3.3 Responsive composition and model fields

| Region | Data | Rendering |
|---|---|---|
| Customers table | Existing `@rows`, `@columns`, `@pagination` | Existing AdminTable mobile cards and desktop table. |
| Hostname field | Attempted `form_values[:hostname]`, else saved edit `hostname`, else blank | Native required text input; mono text, no autocapitalization/spellcheck. |
| Customer field | Attempted `form_values[:customer_id]`, else saved edit `customer_id`, else eligible suggestion/blank | Native required select with localized name + ID labels. |
| Saved hostname | Persisted `CustomerHostname#hostname` | Active customer: `https://<hostname>/` new-tab link with `noopener noreferrer`; inactive/missing customer: plain text. |
| Saved customer | Persisted `customer_id` plus batched customer name | Name + ID, including inactive identity and translated missing-customer fallback. |
| Availability | Associated customer `active?` | Existing success/neutral badge and translated Available/Unavailable label. |
| Saved row actions | Persisted binding ID | Secondary Edit link and danger Remove button. |

- Below `md`, the two form fields stack; from `md`, use `grid-cols-2`. Form actions are full-width stacked buttons below `sm`, intrinsic-width rows from `sm`.
- Preserve the hostname table's existing `block w-full md:table md:table-fixed` composition, real `<caption>`, `<thead>`, `<tbody>`, scoped column headers and labeled mobile cells. Rows stack below `md`; all four data/action cells remain available on mobile.
- Use `break-all` for long hostnames, `break-words` for names/errors, `min-w-0` throughout flexible containers, `flex-wrap gap-2` for row actions and `min-h-11` targets. Preserve project color tokens and input/button/card classes.
- The hostname table remains its existing semantic responsive markup in a Card. Replacing it with AdminTable would add search/pagination semantics absent from the agreed global list.

## 4. Native interactions and states

For the following flows, let `C` mean the fixed Customers index and `T` mean the current sanitized `q/sort/dir/page` query. Rails helpers encode query values; fragments are browser-side navigation targets.

| Flow | Action and result |
|---|---|
| Add | GET `C?T` → fill hostname/select active customer → native POST `C/hostnames` → successful save → **303** `C?T#hostname-form`, translated saved flash, blank add form and refreshed global list. |
| Edit | Saved row Edit → GET `C?T&edit_hostname=<id>#hostname-form` → same form with saved fields → native PATCH `C/hostnames/<id>` → **303** `C?T#hostname-form`, translated saved flash and add mode. |
| Cancel | Edit form Cancel → GET `C?T#hostname-form`; leave edit mode and show the blank add form. |
| Remove | Native `button_to` DELETE `C/hostnames/<id>` → **303** `C?T#hostname-form`, translated removed flash and refreshed list; customer/pages remain intact. |
| Save failure | **422**, render the full Customers index: original table query/sort/page, hostname section, error summary, attempted fields including blanks/rejected IDs, and original saved edit identity. |
| Remove failure | **422**, render the same full page and translated base error; preserve table context and any submitted rendered form/edit state. |
| Discovery | Owner link → `C?target_customer_id=<id>#hostname-form`, or `C#hostname-form` without a suggestion → active suggestion selects the add form only. |

Additional states:

- **Editing wins:** `edit_hostname` takes precedence over `target_customer_id`. A suggestion never filters the table/list or changes platform authorization context.
- **Inactive retained edit:** only the edited binding's saved inactive customer is retainable. Keep its name + ID and unavailable option; allow hostname changes or reassignment to an active customer. It never becomes a new-assignment choice for another binding.
- **Rejected input:** preserve raw attempted hostname/customer values; a rejected nonblank customer ID stays a selected disabled translated option. Blank selection remains blank. Retention eligibility is anchored to the saved edit row, not a mutated Activity model.
- **Empty hostname list:** show the existing EmptyState in the saved-list card and keep the add form visible. A Customers-table empty/search-no-match state does not hide the hostname section.
- **No active customers:** disable new assignment; an edit retaining its original inactive customer remains enabled. Inactive rows remain editable/removable.
- **Missing/stale edit/update/remove ID:** standard 404; do not silently switch to create. Anonymous/admin/member access uses established authentication/role handling; owner requests using another URL CID receive 404 before global hostname access.
- **Loading:** ordinary browser/page navigation, no new skeleton or async region. Domain/DNS/TLS/vendor health is not queried here; operational failures use existing Rails handling.
- **Accessibility:** one Customers h1, one hostname-section h2, card h3 headings, section `aria-labelledby`, explicit field labels, hint/error `aria-describedby`, field `aria-invalid`, persistent `role="alert"` error summary, table caption/scoped headers and hostname-specific translated action labels. Keep native tab order and visible focus.

## 5. Component and controller API recommendations

### 5.1 Embedded component props

```ruby
CustomerHostnames::ManagementComponent.new(
  hostnames: @hostnames,
  available_customers: @available_customers,
  customer_id: 81721200,
  errors: @errors || [],
  form_values: @form_values || {},
  editing_hostname: @editing_hostname,
  table_context: @table_context || {},
  title_id: "customer-hostnames-title"
)
```

`hostnames`, `available_customers`, errors and raw-field precedence retain the inspected interface. `title_id` is an HTML identity, not a translated label. `table_context` accepts only scalar `q`, `sort`, `dir`, `page`; slice again at the component boundary. Do not accept arbitrary `params`, `return_to`, `redirect`, nested structures or authorization/customer IDs as return context. Existing resolver validation continues to control valid sort/direction/page values.

- Add/edit form: emit top-level hidden fields named `q`, `sort`, `dir`, `page` for supplied context entries, outside the nested business payload. Keep only `hostname` and `customer_id` in `customer_hostname` business parameters.
- Removal forms: include the same context hidden fields. If a form is currently in edit mode, include `edit_hostname` and the currently server-rendered hostname/customer values to allow a failed removal to restore that form state. Carry rendered add values too when present. These are failure-display inputs, never additional Destroy inputs. Native forms submit their own fields; raw Save attempts are taken directly from that Save request.
- Edit URL: sanitized table context + the clicked binding's `edit_hostname` + `#hostname-form`.
- Cancel and successful CUD return URL: sanitized table context + `#hostname-form`; omit `edit_hostname` and `target_customer_id`. The suggestion is not sticky after success or cancel.
- Keep native forms and edit/cancel/discovery links `data-turbo="false"`; no feature Stimulus controller.

### 5.2 Shared controller preparation

The **security engineer owns both controllers and the shared controller concern**, including moving existing preparation logic; frontend owns component/view/locales integration. A suggested concern path is `app/controllers/concerns/customer_hostnames/customers_index_context.rb` (final name can follow local conventions).

Expose a small preparation interface such as `prepare_customers_index` with responsibilities:

1. Derive `@table_context` using the `q/sort/dir/page` scalar allowlist.
2. Prepare existing Customers `@columns`, `@customers`, `@rows`, `@pagination` with the same scope/resolver behavior as today's index.
3. Prepare all hostname rows ordered by hostname/ID, batched customer identity including inactive rows, and active `@available_customers` ordered by name/ID.
4. For initial HTML GET, resolve `params[:edit_hostname]` after the exact platform-path guard; otherwise apply only an eligible active `target_customer_id` suggestion.
5. For CUD failure rendering, accept already-established errors/raw form values/saved edit identity without resetting them or reapplying a GET suggestion. Mutation route `:id` defines update identity; body/query IDs cannot change the record being updated/deleted.

Use the existing `CustomerHostnamesController` for CUD, mounted at a **Customers collection scope**, not beneath `/customers/:customer_id`. Suggested helpers: `admin_maintenance_platform_customers_hostnames_path(81721200)` and `admin_maintenance_platform_customers_hostname_path(81721200, hostname)`. Helpers must generate `/customers/hostnames[/:id]`; use a scoped route name to distinguish the collection from the existing customer resource.

HTML failure rendering targets `admin/maintenance/platform/customers/index` with status 422 and all combined-page variables prepared. Preserve existing Customers JSON responses and customer create/show/edit/delete/trash/restore/act-as workflows. The exact platform-CID check for the combined index must run before hostname preparation; CUD retains the existing inherited owner gate and explicit path guard.

### 5.3 Fresh table context without changing the shared table

The inspected AdminTable wraps itself in `turbo-frame#admin-table` and advances browser history while replacing only the table. That would leave the sibling hostname component's hidden return context stale after search/sort/page navigation.

For this combined HTML index, recommend the standard Rails **`turbo_page_requires_reload`** helper in the Customers index template. This makes table visits refresh the complete page and both regions' state without changing `AdminTableComponent` or its existing JavaScript. Also supply `base_path:` as above. The tradeoff is full-page Customers-list navigation instead of table-only updates.

**Important integration detail:** `ApplicationController#dashboard_layout` currently returns `false` for `Turbo-Frame` requests. The security-owned Customers HTML index render must explicitly use the dashboard layout, including frame-originated requests, so `yield :head` emits the helper's `turbo-visit-control=reload` directive. Full-page 422 rendering uses that layout too. A helper declaration in a layoutless response alone cannot solve this. Keep this explicit rendering choice local to the combined page.

Official behavior reference: [Turbo Frames: breaking out from a frame](https://turbo.hotwired.dev/handbook/frames#%E2%80%9Cbreaking-out%E2%80%9D-from-a-frame). QA must exercise search/sort/page followed by hostname actions in a real browser to verify current context is returned.

## 6. Component reuse and localization

| Region | Existing component / composition |
|---|---|
| Page chrome | `AdminPageComponent`, once in Customers index. |
| Customers list | `AdminTableComponent`, existing controls and responsive composition; existing `base_path:` prop. |
| Hostname section | Adapt existing `CustomerHostnames::ManagementComponent`; own h2/description and two Cards. |
| Form and saved-list cards | `CardComponent(padding: :none)`; header/description, content and action regions composed in its content. |
| Error summary | `AlertComponent(type: :error, auto_dismiss: false)` inside `role="alert"`. |
| Submit/edit/cancel/discovery | `ButtonComponent`; existing primary/secondary styling. |
| Removal | Existing native `button_to` with project danger classes, CSRF and DELETE method field. |
| Availability / empty list | `BadgeComponent` / `EmptyStateComponent`. |
| Owner discovery | `CustomerHostnames::ManagementLinkComponent`, fixed Customers index + anchor even without a suggestion. |

New components: **none**. Shared primitive API changes: **none**.

Reuse the paired `config/locales/customer_hostnames.en.yml` / `.zh-CN.yml` keys for all hostname labels, descriptions, hints, options, accessibility labels and flashes. Examples: `title` → “Customer hostnames” / “客户主机名”; `add_heading` → “Add hostname” / “添加主机名”; `edit_heading` → “Edit hostname” / “编辑主机名”; `saved_heading` → “Saved hostnames” / “已保存的主机名”. Common action labels and existing availability labels retain their current keys. Translations are evaluated at render/request time.

Removing the sidebar leaf makes `chrome.sidebar.maintenance.customer_hostnames` obsolete; remove the matching key from both chrome locale files after checking consumers. Keep `customer_hostnames.title` and its grant-route label mapping because the CUD controller resource remains `customer_hostnames`. Any implementation-added text requires EN/zh-CN key and interpolation parity.

## 7. Implementation sequence and file ownership

| Owner | Files / responsibility |
|---|---|
| Security engineer | `config/routes.rb`; `app/controllers/admin/maintenance/platform/customers_controller.rb`; `customer_hostnames_controller.rb`; new shared concern under `app/controllers/concerns/customer_hostnames/`. Own route remount/removal, guards, shared preparation, full HTML rendering, context and 303/422 behavior. |
| Frontend developer | `app/views/admin/maintenance/platform/customers/index.html.erb`; `app/components/customer_hostnames/management_component.{rb,html.erb}`; `management_link_component.rb`; remove obsolete standalone hostname index template; `app/services/maintenance_contributor.rb` sidebar presentation; paired customer_hostnames/chrome locales if touched. Preserve customer-details/page-shortcuts mounts through the shared link component. |
| Backend developer | Review existing `CustomerHostname`, Save/Destroy Activities and Reform contract against active/retain-only and raw-error rendering needs. Schema/business-rule changes are not required by the merge. Coordinate saved edit identity semantics with security; controller/concern edits stay with security. |
| QA engineer | Update existing hostname component/link, Customers/hostname request, routing and sidebar specs; preserve authorization, CSRF, retained inactive customer and customer-workflow coverage. Add meaningful combined-page/context regressions. |
| Release engineer | Run scoped checks, rebuild Tailwind for changed templates, and smoke-test the combined page at mobile/tablet/desktop sizes and EN/zh-CN. Follow project asset/server instructions when restarting. |
| Reference-doc owner, assigned by parent | Update affected paired `doc/reference` pages in the implementation change; synchronize URL/component/API examples and discovery descriptions. |

Recommended build order:

1. Security publishes the agreed route-helper names, concern variables and table-context schema; frontend can implement against that contract in parallel.
2. Frontend embeds the hostname section and retargets discovery/sidebar; security switches GET preparation/CUD full-page rendering and removes old routes/index action.
3. QA verifies success/failure/context/authorization and retained customer workflows; reference-doc owner synchronizes both locales.
4. Release runs the targeted suites and responsive/native browser smoke tests; tech lead/code reviewer check the agreed minimal merge.

## 8. Acceptance and downstream verification

- Exactly one AdminPage/Customers h1; existing customer table precedes the complete labeled hostname form and global saved list.
- Customers search/sort/page and every existing customer workflow remain functional. Zero search results do not remove global bindings or active customer choices.
- Edit uses `edit_hostname`; editing overrides suggestions. Discovery always uses fixed CID `81721200` and `#hostname-form`, with optional active-customer suggestion; customer details keep their suggestion behavior.
- Native POST/PATCH/DELETE go to `/customers/hostnames[/:id]`. Success is 303 to Customers + the current four-field table context + form anchor, clearing edit/suggestion state.
- Invalid create/update and removal failures return 422 with the entire combined page, original table context, translated errors, all submitted attempted fields, and saved edit identity where applicable. Duplicate/rejected/blank/inactive-retained cases preserve their established semantics.
- No standalone hostname sidebar destination/index view/index action or old `/platform/customer_hostnames` GET/CUD routes remain; there is no compatibility redirect. There are no separate hostname new/show/edit pages.
- Anonymous/admin/member, forged query/body IDs and owner-on-wrong-prefix cases do not expose/mutate global bindings. Existing CSRF/method behavior is retained.
- Form controls, section labeling, caption/header/body, action labels and error associations work in both locales; long hostnames/names/errors wrap without page overflow at 375px, 768px and 1440px.
- Real-browser regression: change Customers q/sort/dir/page, then Edit/Cancel/Save/Remove; URLs, table results and hidden context agree after success and after 422. The index's reload directive is present even for a `Turbo-Frame: admin-table` request.
- With JavaScript disabled, hostname add/edit/cancel/remove/discovery work as native navigation/forms. Existing Customers search retains native GET submission behavior.

Suggested targeted suites: `spec/components/customer_hostnames/management_component_spec.rb`, `management_link_component_spec.rb`, `spec/requests/admin/maintenance/platform/customers_spec.rb`, `customer_hostnames_spec.rb`, `customer_restorations_spec.rb`, `spec/requests/platform/customer_contexts_spec.rb`, `spec/routing/customer_hostnames_routing_spec.rb`, `spec/services/maintenance_contributor_spec.rb`, and relevant shortcut discovery/request specs. Run `grant_route_label_spec.rb` if its mapping is touched. A parent decision to change shared authorization instead of using local guards requires broader auth coverage under AGENTS.md.

## 9. Developer reference pages affected

Update **both** `doc/reference/en/<slug>.md` and `doc/reference/zh-CN/<slug>.md` during implementation:

- **`customer-hostnames`**: combined Customers composition, h2/props, `edit_hostname`, context hidden fields, full-page navigation/rendering, new CUD helpers, 303/422 flows, discovery and removed standalone surface. Keep the feature reference page and catalog entry: hostname behavior still has its own documentation.
- **`customers`**: embedded global section below the table, discovery from details, query context and existing customer lifecycle behavior.
- **`page-shortcuts`**: owner discovery destination now Customers + anchor; suggestion affects the form, not the global list.
- **`tenancy-and-roles`**: precise combined index/CUD path lock, inherited owner gate and suggestion/context distinction.
- **`system-map`**: Customers as the single sidebar/index surface, global hostname section and CUD path.
- **`access-grants`**: distinguish the Customers GET surface from hostname CUD controller/grant identity; remove any implication of a separate sidebar/index destination while keeping the bilingual hostname resource label.

Search `doc/reference/` for old URLs/helper names, `?edit=`, and standalone-navigation wording before final review; update any additional affected EN/zh-CN references. Public hostname resolution and customer lifecycle descriptions remain consistent with their existing behavior.
