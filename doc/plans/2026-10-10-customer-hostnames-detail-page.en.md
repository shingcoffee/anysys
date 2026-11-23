# Customer hostnames — dedicated page beneath customer details

Date: **2026-10-10**. Status: **READY_FOR_FRONTEND / READY_FOR_PARALLEL_BUILD**. Research/design and implementation handoff only.

**Final clarification — Customer detail and edit:** Section 10 supersedes the earlier standalone-only presentation/discovery assumption and extends the ownership/interface handoff. Both profile pages require a separate, scoped hostname section with editing controls; the dedicated page remains the hostname edit and mutation-response destination.

## 1. Settled scope and research

Customer detail and edit pages show a separate hostname management section for the displayed customer. Its Manage link and row Edit links open the dedicated, bookmarkable hostname page beneath that customer; hostname submissions also use its nested routes. The dedicated page contains only that customer's hostname management, with a clear route back to customer details. Page shortcuts discovery uses this dedicated destination. Global Customers retains its combined customer table and global hostname management.

This follow-up supersedes the combined-page-only destination, bound form routing/hidden-target instructions and bound return-context instructions in [the customer-context/DNS plan](2026-10-10-customer-hostnames-context-dns.en.md). Its existing customer-bound behavior, inactive-customer rules, Save-time DNS gate and locked ownership checks remain the implementation baseline. This slice adds routes, controller presentation/orchestration and frontend composition; **backend developer work is not required**. No schema, DNS/service/Activity/contract or JavaScript changes are needed.

Research: `.cursor/agents/anysys-ux-designer.md`, `AGENTS.md`, relevant `.cursor/rules/`, current hostname management/link components and specs, Customers views/controller, hostname controller, shared `CustomersIndexContext`, `RouteAuthorization`, `PageShortcuts::PathPolicy`, routes, `AdminPageComponent`, `BreadcrumbsComponent`, the settings-page wrapper, EN/zh-CN UI locales and affected developer references. Current customer-details discovery already supplies `@customer.id`, including inactive customers; Page shortcuts already supplies its URL customer ID. Both benefit from the shared link's destination change.

The shadcn skill/MCP is unavailable in this harness. Reuse the official [shadcn Field reference](https://ui.shadcn.com/docs/components/field) consulted in the preceding task and the prior plan's FieldTitle/read-only content/FieldDescription and FieldLabel/control/FieldError guidance. Compose **Card / Breadcrumb / Field patterns** through the project's existing ViewComponent + Tailwind primitives, with native Rails forms. No React package or new widget is part of this design.

## 2. Surface inventory

| Surface | Navigation area / audience | Design |
|---|---|---|
| Customer details → Manage customer hostnames | admin → Maintenance → Platform → Customers; platform owner | Shared discovery link opens the selected customer's nested hostname page. |
| Dedicated customer hostname GET / edit state | Same | New `CustomerHostnames::CustomerPageComponent` shell, existing management form and scoped saved list; no customer table. |
| Nested POST/PATCH/DELETE and full-page 422 | Same | Same existing hostname controller; return/render the dedicated page based on the nested path parameter. |
| Global Customers GET and global hostname CUD | Same | Existing combined page and table-context behavior. |
| Optional query-bound Customers GET/global CUD | Same | Existing bound target semantics continue; rendered bound management controls now use nested URLs. No compatibility redirect. |
| Page shortcuts → Manage customer hostnames | admin → Maintenance → Page shortcuts; discovery visible only to owner | Shared link opens the dedicated hostname page for the shortcuts URL's customer. |

Customers remains the platform sidebar destination. The dedicated child page adds neither a sidebar leaf nor a new audience. Its URL is admin-category and platform-owner-only.

## 3. Layout specification

```text
Existing responsive dashboard chrome / Maintenance selected

Maintenance / Customers / Acme / Customer hostnames
Manage customer hostnames                         [← Back]
Showing hostnames for Acme (12345678).

Customer hostnames h2
Existing public-shortcut routing description
┌ Add hostname / Edit hostname h3 ─────────────────────────┐
│ Existing DNS/deployment instructions                     │
│ Persistent validation summary, when present              │
│ Hostname                         Customer                │
│ [forms.acme.example          ]    Acme (12345678)          │
│ Existing help / inline errors     Read-only context hint  │
│ Inactive-target explanation, when applicable              │
│ [Add hostname / Save] [Cancel, edit only]                 │
└─────────────────────────────────────────────────────────┘
┌ Saved hostnames h3 ──────────────────────────────────────┐
│ Showing hostnames for Acme (12345678).                    │
│ Existing removal explanation                            │
│ Hostname | Customer name + ID | Availability | Actions   │
│ Only customer_id = 12345678; Edit / Remove                │
│ Existing availability explanation                       │
└─────────────────────────────────────────────────────────┘
```

- **Shell:** render `AdminPageComponent` once, wrapped by `CustomerPageComponent`. Default dashboard content width; normal document scrolling. One h1 from `customer_hostnames.manage`; retain the existing labeled management h2 and card h3 headings. The dashboard layout owns flashes; do not duplicate success alerts in the component.
- **Breadcrumbs:** Maintenance → Customers → target customer name → Customer hostnames. Maintenance links to `admin_maintenance_path(81721200)`; Customers to `admin_maintenance_platform_customers_path(81721200)`; customer name to `admin_maintenance_platform_customer_path(81721200, target_customer.id)`; final crumb has no link. Render the escaped customer name as data, not a translated label. This hierarchy applies to add/edit/422 states, including inactive targets.
- **Header:** description uses `customer_hostnames.target_saved_hint` with `%{customer}` produced by `customer_hostnames.customer_option`, showing the actual target name and ID. Secondary Back action uses `common.actions.back`, icon `:back`, fixed customer-detail helper above, `data: { turbo: false }`, and `min-h-11 w-full sm:w-auto whitespace-normal`. Back is deterministic navigation, not browser-history behavior.
- **Management body:** reuse the existing two cards and all fields/list columns. Target identity maps to `Customer#name/#id`; inactive state to `Customer#active?`; rows to `CustomerHostname#id/#hostname/#customer_id` with their loaded customer association. The management section description still explains public shortcut routing. Do not add a Customers table, search, sorting, pagination, customer selector or reassignment control to the dedicated page.
- **Actions:** Add/Save is primary within the form, Cancel secondary beside it in edit mode, Edit secondary in each saved row, Remove destructive in each row. Back stays in the page header. Reuse current removal semantics and explanatory copy; no new confirmation interaction.
- **Empty:** retain the Add form and `EmptyStateComponent` with `empty_title` and `target_empty_hint`. Active targets can add their first hostname. Inactive targets retain identity/explanation with disabled hostname/Add controls; existing rows remain editable/removable, and editing an existing scoped binding enables hostname/Save while keeping customer read-only.
- **Errors:** native 422 renders the complete dedicated page with persistent `AlertComponent(type: :error, auto_dismiss: false)` inside `role="alert"`, escaped raw attempted hostname (including blank), inline field errors and the saved edit identity. Keep customer errors associated with the read-only group, base errors in the summary and existing `aria-invalid`/`aria-describedby` wiring. A foreign or no-longer-scoped edit identity is a 404, never another customer's display or a silent switch to Add.
- **Loading:** ordinary native navigation/submission; existing bounded DNS work can delay Save. No separate loading panel, live DNS status or JS spinner. DNS failures use the existing translated hostname error. Remove continues to work independently of DNS.

### Responsive and accessibility rules

- Shell wrapper: `min-w-0 [&_h1]:whitespace-normal [&_h1]:break-words`, following `Admin::Settings::PageComponent`. Escape and wrap header identity text with `break-words [overflow-wrap:anywhere]` where needed for long names/IDs. Use render-time helpers to construct safe markup, not `html_safe` on customer input.
- Breadcrumbs reuse the existing labeled nav and local `overflow-x-auto` on small screens. Long crumbs scroll within that region rather than overflowing the viewport; no shared breadcrumb redesign.
- Body retains `space-y-6`, cards `p-4 sm:p-6`, form `space-y-5`, field `space-y-2`, `grid grid-cols-1 gap-4 md:grid-cols-2`, `min-w-0`, project semantic color/text tokens, `break-words` names/errors and `break-all` hostnames. No fixed-width card.
- Header and form actions stack below `sm`; saved rows use existing mobile block layout and labeled values, changing to semantic `md:table`/`md:table-fixed`. Preserve all four columns and both row actions on mobile. Touch targets use `min-h-11`.
- Keep the real hostname label/input. Bound customer identity remains non-focusable read-only text in `role="group"` with a title/hint/error relationship, not a disabled select or a label for a nonexistent input. Preserve native CSRF/method-override controls, keyboard links/buttons and the existing external-hostname `noopener noreferrer` behavior.
- **Stimulus:** no new controller/actions/values. Add/Edit/Cancel/Save/Remove/Back work with JavaScript disabled.

## 4. Route and target-resolution contract

Use two separate URL customer identities:

- Outer `request.path_parameters[:customer_id]` is the platform authorization CID and must equal the string `"81721200"`.
- Inner `request.path_parameters[:hostname_customer_id]` is the authoritative hostname target. Do not use Rails' default nested `:customer_id`, which collides with the outer scope.

Let `G = /81721200/admin/maintenance/platform/customers` and `N(C) = G/:hostname_customer_id/hostnames` with the path target `C`.

| Verb / path | Controller action | Helper |
|---|---|---|
| GET `N(C)` | `admin/maintenance/platform/customer_hostnames#index` | `admin_maintenance_platform_customer_hostnames_path(81721200, target.id)` |
| POST `N(C)` | same controller `#create` | same collection helper |
| PATCH `N(C)/:id` | same controller `#update` | `admin_maintenance_platform_customer_hostname_path(81721200, target.id, row)` |
| DELETE `N(C)/:id` | same controller `#destroy` | same record helper |
| GET `G` | existing `customers#index` | existing `admin_maintenance_platform_customers_path(81721200)` |
| POST `G/hostnames`; PATCH/DELETE `G/hostnames/:id` | existing hostname CUD actions | existing plural-`customers` collection/record helpers |

Security owns an explicit scope inside the existing admin/maintenance/platform routing scopes, alongside existing global hostname CUD and Customers resources. This routing sketch establishes helper names without modifying ordinary Customers route parameters:

```ruby
scope "customers/:hostname_customer_id", as: :customer do
  resources :hostnames, only: %i[index create update destroy],
            controller: "maintenance/platform/customer_hostnames"
end
```

There is no global hostname index, nor separate new/show/edit action/controller. Edit is GET `N(C)?edit_hostname=<row-id>#hostname-form`. Confirm helper argument order and recognition during implementation.

### Authoritative target and presentation mode

1. Inherited authentication/platform-owner/CanCan guards run first, then the existing exact outer-platform path guard, before any target/hostname/table reads.
2. Detect nested mode by **key presence in `request.path_parameters`**, never merged `params`: `request.path_parameters.key?(:hostname_customer_id)`. If present, validate that path value using the existing strict CID policy (`PageShortcuts::PathPolicy.customer_id`, eight digits, nonzero first digit) and resolve `Customer.unscoped.find(cid)`. Missing/invalid customer returns 404; do not fall back to query/body. Inactive existing customers remain addressable.
3. Only when the path key is absent, keep the concern's existing optional `target_customer_id` fallback semantics: absent means global; explicitly supplied invalid/blank/nonscalar/nonexistent means 404; valid means query-bound combined context. This is ongoing behavior on existing routes, not a redirect layer.
4. On nested requests, query/body `target_customer_id` and query/body `hostname_customer_id` cannot override or invalidate the real path target, even if conflicting or malformed. Ignore them as routing context. `customer_hostname[customer_id]` is overridden server-side with the resolved target, including missing/blank/forged values, as in current bound behavior. Keep existing strong-parameter allowlisting; do not add rejection of extraneous fields from the platform owner.
5. All lists, GET edits, path-selected update/remove records and failure edit restoration use `hostname_scope`. CUD selects its record with `request.path_parameters[:id]`; query/body record IDs cannot substitute. Missing/foreign IDs return 404 before invoking an Activity. Pass the existing `expected_customer_id: @hostname_target_customer&.id` to Save/Destroy so locked checks still protect concurrent reassignment.
6. **Response selection is path-driven:** nested CUD success → nested GET; nested failure → dedicated index view. Global CUD success/failure retains combined Customers responses, even if the old request has a valid query/body target. Never infer response template from `@hostname_target_customer` alone.
7. Nested pages ignore `q/sort/dir/page`: no table preparation, filtering, validation, hidden fields or forwarding. Extra keys are tolerated but not consumed as table state. Nested returns retain only path target and `#hostname-form`; clear `edit_hostname`. The existing combined page/global CUD retains its allowlisted scalar table context and optional validated target.

## 5. Interaction and failure flows

| Starting point / action | Outcome and next URL |
|---|---|
| Customer details → Manage customer hostnames | Native GET `N(displayed_customer.id)#hostname-form`; target name/ID, blank Add form and only target-owned rows. Inactive discovery remains target-specific. |
| Page shortcuts → Manage customer hostnames | Native GET `N(shortcuts_url_customer.id)#hostname-form`, still under platform CID 81721200. |
| Discovery with no target | Existing GET `G#hostname-form`, combined global page. |
| Nested Add | Native POST `N(C)`, hostname payload only; server assigns C. Success 303 to `N(C)#hostname-form`, translated saved flash, refreshed rows and blank Add state. |
| Nested Edit → Save | GET `N(C)?edit_hostname=R#hostname-form`, then native PATCH `N(C)/R`. Success 303 to `N(C)#hostname-form`; keep C and clear edit state. |
| Nested Cancel | GET `N(C)#hostname-form`; discard attempt and clear edit state, keep target. |
| Nested Remove | Native DELETE `N(C)/R`; success 303 to `N(C)#hostname-form`, deleted flash, refresh rows, clear edit state even if another row was being edited. |
| Save validation/duplicate/DNS/conflict failure | 422 at the submitted nested action URL with dashboard layout, dedicated shell, scoped list, original saved edit identity and raw attempted values. Retry form still points at the nested collection/record action. |
| Remove failure | 422 dedicated page retaining the separately rendered edit identity and attempted hostname carried by the removal form; Destroy still acts only on its path-selected row. Reload removed/edit identities inside scope; moved/missing records return 404. |
| Back / customer breadcrumb | GET `admin_maintenance_platform_customer_path(81721200, C)`; Customers breadcrumb instead opens global G with no inherited table query. |
| Old query-bound combined GET | Render combined page as today; its bound Add/Edit/Cancel/Remove controls point to N(C). Following any control enters the dedicated flow. Table search/sort/page can continue retaining its validated old target on the combined source page. |
| Direct old global CUD with valid target | Preserve current bound scoping and combined 303/422 response with table/target context. A rendered bound retry/cancel/edit/removal control uses nested URLs thereafter. |
| Invalid target / stale or foreign row | Standard 404 with no foreign hostname/customer content, no fallback/global expansion and no mutation. |
| Anonymous / admin / member | Existing sign-in or authorization-denial response from `RouteAuthorization`; no new denial UI. Owner on wrong outer CID receives 404 before target/hostname queries. |

Removal forms retain the **server-rendered** hostname attempt and optional `edit_hostname` for failure restoration, including a blank attempt. This is not live capture of unsent browser edits. In bound mode omit customer-assignment/target/table hidden context; the action path carries the target. Global unbound removal continues carrying its existing rendered hostname/customer/table values.

## 6. Exact component/controller interfaces

### Frontend: new page shell

```ruby
CustomerHostnames::CustomerPageComponent.new(
  target_customer: @hostname_target_customer,
  hostnames: @hostnames,
  customer_id: 81721200,
  errors: @errors || [],
  form_values: @form_values || {},
  editing_hostname: @editing_hostname
)
```

Initializer contract: `target_customer:` and `hostnames:` required; `customer_id: 81721200`, `errors: []`, `form_values: {}`, `editing_hostname: nil` optional. `target_customer` must be the resolved Customer, never an attempted/request-supplied hash. Shell makes no database queries. It builds breadcrumbs/title/description/Back and renders `ManagementComponent` with `target_customer`, `available_customers: []` and `table_context: {}`. Retain current title identity defaults; only one management section is mounted. No `table_context` or `available_customers` prop on the page shell.

New view: `app/views/admin/maintenance/platform/customer_hostnames/index.html.erb`. A simple component mount passes the above prepared assigns; layout/chrome/fields remain in components. Controller explicitly renders dashboard layout on both GET and 422. Native links/forms use existing `data-turbo="false"`; this page has no table frame/reload requirement.

### Frontend: existing management/link contract

Keep `ManagementComponent`'s initializer and `target_customer: nil` API. Route from that prop in **every** rendering location, including a query-bound combined source page:

| Method / markup | `target_customer` present | No target |
|---|---|---|
| `index_path` | nested collection helper + `#hostname-form` | existing G + scalar table context + anchor |
| `form_path` | nested collection POST or nested `record_path` PATCH | existing global CUD helpers |
| `record_path(row)` | nested singular-`customer` record helper, outer CID, target ID, row | existing plural-`customers` record helper |
| `edit_path(row)` | nested collection helper + `edit_hostname: row.id` + anchor | existing combined GET + table context/edit/anchor |
| Add/Save hidden routing fields | no `target_customer_id`, `hostname_customer_id`, nested customer ID or table fields | existing scalar table fields |
| `removal_params` | rendered `customer_hostname[hostname]` plus optional `edit_hostname` only | existing rendered form state and scalar table context |

Decision: **omit duplicated target routing fields from all bound nested forms/removal forms**, including when rendered on the old query-bound source page. Remove the bound hidden-target loop/its helper usage as needed. Component may retain its sanitized `table_context` reader for existing callers, but bound navigation/submission never emits it. Do not introduce a source-mode prop or copy target context into action queries.

`ManagementLinkComponent` keeps `initialize(current_user:, target_customer_id: nil)` and owner-only `render?`. Target present → `admin_maintenance_platform_customer_hostnames_path(81721200, target_customer_id, anchor: "hostname-form")`; target absent → existing `G#hostname-form`. No target lookup in the link. Customer details and Page shortcuts mount APIs already match; their templates need no routing duplication.

### Security: controller/concern contract

- Extend `CustomersIndexContext#prepare_hostname_target_customer` with path-first resolution above; keep query fallback and current `hostname_scope`/`prepare_hostname_management`. Use a small shared private predicate, e.g. `nested_hostname_request?`, reading the path key directly.
- Add `CustomerHostnamesController#index` for **dedicated nested GET only**. Require path target, load optional scoped `edit_hostname`, initialize fresh GET errors/form values and call `prepare_hostname_management`. Explicitly `render :index, layout: "dashboard"`. Never call `prepare_customers_index`, `customers_table_context` or `ModuleEntriesResolver` for this page; do not prepare `@rows/@columns/@pagination`.
- Prepared dedicated assigns: `@hostname_target_customer`, `@hostnames`, `@available_customers = []`, `@customer_id = 81721200`, `@editing_hostname`, `@errors`, `@form_values`. Preserve batching/unscoped customer association loading already in `prepare_hostname_management`.
- Generalize existing return/render helpers (e.g. `hostname_return_path`, `render_hostname_failure`) so both Save and Destroy branch on `nested_hostname_request?`. Nested return uses the nested collection helper with outer 81721200, resolved target ID and anchor only. Global return keeps existing combined `customers_table_context`. Fixed helpers ignore arbitrary return/redirect fields.
- Failure preparation calls `prepare_hostname_management` without resetting `@errors`, raw `@form_values` or the saved `@editing_hostname`. Nested failure renders `admin/maintenance/platform/customer_hostnames/index`, `layout: "dashboard"`, status 422; global failure additionally prepares Customers table and renders the existing combined index with the same explicit layout/status.
- Keep saved-ID reload in scoped Save failure and clicked-row/optional edit reload in scoped Remove failure. GET-only initialization must not run during CUD failure rendering. Keep authoritative customer payload and existing Activity arguments unchanged.
- `CustomersController`'s combined index and view retain their current query-bound preparation/table behavior. Section 10 adds profile-page section preparation and local HTML path guards; no new hostname controller or shared authorization changes are expected.

## 7. Component reuse and I18n map

| Region | Component / responsibility |
|---|---|
| Dedicated page composition | **New** `CustomerHostnames::CustomerPageComponent` |
| Breadcrumb/title/description/Back | Existing `AdminPageComponent`, internally `BreadcrumbsComponent` and `ButtonComponent` |
| Form/list and all bound/inactive/error states | Existing `CustomerHostnames::ManagementComponent` |
| Form/list containers | Existing `CardComponent(padding: :none)` |
| Persistent validation summary | Existing `AlertComponent(type: :error, auto_dismiss: false)` |
| Empty list / availability / actions | Existing `EmptyStateComponent`, `BadgeComponent`, `ButtonComponent` and native `button_to` |
| Customer detail/Page shortcuts discovery | Existing `CustomerHostnames::ManagementLinkComponent` |

Reuse these existing paired EN/zh-CN translations; no new copy keys are required:

| Purpose / key | English | 简体中文 |
|---|---|---|
| Maintenance crumb: `maint_platform.customers.breadcrumb.maintenance` | Maintenance | 维护 |
| Customers crumb: `maint_platform.customers.breadcrumb.customers` | Customers | 客户 |
| Final crumb/section: `customer_hostnames.title` | Customer hostnames | 客户主机名 |
| h1/discovery: `customer_hostnames.manage` | Manage customer hostnames | 管理客户主机名 |
| Header description: `customer_hostnames.target_saved_hint` | Showing hostnames for %{customer}. | 仅显示 %{customer} 的主机名。 |
| Identity: `customer_hostnames.customer_option` | %{title} (%{id}) | %{title}（%{id}） |
| Header action: `common.actions.back` | Back | 返回 |

Reuse all current form/action/empty/inactive/DNS/flash keys. Translate at render/request time, never in constants. Customer names, IDs and hostnames are escaped record data. Any additional wording discovered during build must use paired locale keys with matching interpolation tokens; keep English byte-identical to the intended displayed text.

## 8. Exclusive ownership and parallel build steps

These are handoff lanes for a subsequent build, not subagents dispatched by this design task.

| Owner | Exclusive files / deliverables |
|---|---|
| Frontend developer | Add `app/components/customer_hostnames/customer_page_component.{rb,html.erb}` and `app/views/admin/maintenance/platform/customer_hostnames/index.html.erb`; update `app/components/customer_hostnames/management_component.{rb,html.erb}` and `management_link_component.rb`. Own shell/responsiveness/native URLs/context omission. Own new `spec/components/customer_hostnames/customer_page_component_spec.rb` and existing management/link component specs. Locale edits, if needed, belong exclusively to frontend in paired `config/locales/customer_hostnames.{en,zh-CN}.yml`; none expected with copy reuse. |
| Security engineer | Update `config/routes.rb`, `app/controllers/admin/maintenance/platform/customer_hostnames_controller.rb`, `app/controllers/concerns/customer_hostnames/customers_index_context.rb`. Own route/helper recognition, guard ordering, authoritative path target, scoped IDs, dedicated GET preparation and path-driven 303/422. Own `spec/requests/admin/maintenance/platform/{customer_hostnames,customers,customers_hostnames_merge}_spec.rb`, plus discovery expectations in `spec/requests/admin/maintenance/page_shortcuts_spec.rb`, `spec/components/page_shortcuts/management_component_spec.rb` and `spec/components/admin_table_component_base_path_spec.rb` if affected. Own new routing specs if a separate routing file is useful. |
| Backend developer | **No changes required.** Consume the current Save/Destroy/CNAME interfaces and ownership guards. |
| Integration/reference owner | Update both locales of affected `doc/reference` pages, merge the two lanes, review tests/docs and perform responsive/bilingual/native smoke checks. Own any integration-only corrections after parallel work is reconciled. |

1. **Freeze shared interfaces:** route/helper names and positional arguments; distinct outer `customer_id`/inner `hostname_customer_id`; path-key predicate; dedicated assigns and page initializer; prop-driven bound control URLs versus path-driven response selection. Confirm the current backend/context-DNS slice is the baseline.
2. **Parallel frontend lane:** build the shell/mount, switch ManagementComponent's bound helpers/hidden/removal context, update link destination, and add/update component specs. Reuse current field/inactive/error rendering and existing locales. Frontend uses the agreed future helper names; render checks can complete once routes are available.
3. **Parallel security lane:** add explicit scoped routes, path-first target resolution, nested-only GET preparation and nested/global return/failure branches. Preserve global/query-bound semantics and existing Activity calls; add/update request/routing/discovery regressions. Security does not edit frontend-owned templates/components/locales.
4. **Integrate:** verify rendered form/link destinations and native submissions against real routes; test nested vs direct-global response selection and query-bound source transition. Reconcile specs that formerly expected query-bound links, hidden targets/table fields or combined h1/table after following customer discovery.
5. **Documentation and verification:** synchronize reference pages below, run the focused checks, rebuild Tailwind and smoke-test EN/zh-CN at 375/768/1440px with JavaScript disabled for the hostname flows. Review ownership/isolation and project conventions before implementation handoff is complete.

## 9. Acceptance, checks and reference updates

- Dedicated GET is bookmarkable under the selected customer, renders exactly one admin shell/h1, target name/ID, breadcrumbs/Back, scoped form/list and no customer table/search/pagination. GET/edit/422 all use full dashboard layout, including a request carrying an unrelated `Turbo-Frame` header.
- Route recognition retains outer `customer_id: "81721200"`, inner `hostname_customer_id: C` and mutation `id: R`, and dispatches all four verbs to the same existing hostname controller. Global route recognition/helpers remain intact.
- Anonymous, platform/tenant admin and member cases use the inherited protection on every nested verb. Owner with wrong outer CID fails before target/hostname/table queries. Strict invalid/leading-zero/nonexistent path targets return 404; valid inactive targets remain addressable.
- On every nested verb, conflicting/malformed query/body target fields do not change the path target or response mode. Add/update with missing/blank/foreign nested customer ID uses C. Extraneous owner fields are ignored through existing allowlisting. Nested mutation IDs are selected exclusively from the path; foreign edit/update/remove/restoration IDs return 404 and never mutate or display another customer's binding.
- Native emitted Add/Edit/Cancel/Save/Remove URLs use nested helpers, including from an old query-bound combined render. Bound forms carry no duplicated target/customer/table routing fields; removal still carries raw rendered attempt/optional edit identity. Global unbound forms/list/table context remain as before.
- Nested CUD successes use 303 to `N(C)#hostname-form`, translated flash and cleared edit state; failures use 422 dedicated view preserving raw/blank attempt, saved PATCH identity, errors and bound target. Injected `q/sort/dir/page`, return URLs and body-only `hostname_customer_id` are not forwarded. Direct old global CUD, including query-bound requests, keeps combined 303/422 and current table context.
- Exercise duplicate/validation and stubbed CNAME failures, same-customer failure restoration, moved/deleted saved identities returning 404 and inactive Add/edit/remove behavior. Use deterministic verifier stubs at `CustomerHostnames::CnameVerifier.call`; no public DNS dependency and no reimplementation of backend tests.
- Verify escaped long customer names/hostnames, accessible field/group/error relationships, breadcrumb local scrolling, mobile-stacked actions/rows, bilingual rendering and no translation/interpolation gaps. Component construction before changing locale must still translate at render time.

Suggested focused implementation checks (run after both lanes are integrated):

```bash
bundle exec rspec spec/components/customer_hostnames/customer_page_component_spec.rb spec/components/customer_hostnames/management_component_spec.rb spec/components/customer_hostnames/management_link_component_spec.rb spec/requests/admin/maintenance/platform/customer_hostnames_spec.rb spec/requests/admin/maintenance/platform/customers_spec.rb spec/requests/admin/maintenance/platform/customers_hostnames_merge_spec.rb spec/components/page_shortcuts/management_component_spec.rb spec/requests/admin/maintenance/page_shortcuts_spec.rb spec/components/admin_table_component_base_path_spec.rb
bin/rails tailwindcss:build
```

Include any added route specs in that scoped run. No runtime tests or build were run for this research/design-only artifact; the above are implementation acceptance checks.

In the implementation change, update **both locales** of `doc/reference/{en,zh-CN}/{customer-hostnames,customers,page-shortcuts,tenancy-and-roles,system-map,access-grants}.md`. Document nested routes/helper/API, distinct path IDs, dedicated shell/navigation, authoritative path scope, bound controls without hidden routing context, path-selected return/422 presentation and retained global/query-bound combined behavior. Correct claims of “no standalone hostname GET” and “discovery always targets the combined index.” Keep the existing hostname reference/catalog entry; this extends that documented feature. Search remaining reference pages for conflicting discovery/routing/context statements and synchronize any affected matches in both locales. Preserve accurate DNS/concurrency descriptions from the earlier slice.

## 10. Final supplement — Customer detail and edit

### Required surfaces and layout

- **Show:** after all customer profile cards, render one distinct hostname section containing `ManagementLinkComponent` and the existing `ManagementComponent`. Move the existing top-of-profile Manage link into this section; do not duplicate it. Preserve the profile h1 and reuse the management h2/card h3 hierarchy, current Card/Field patterns and existing paired I18n copy.
- **Edit and profile-update HTML 422:** render the same section after the complete `CustomerFormComponent`. **Profile and hostname forms must be siblings, never nested.** Keep profile errors/attempted fields in the profile form, and a fresh hostname Add form plus scoped saved rows in the hostname section. Profile Save does not submit or persist hostname fields.
- **Controls:** show the read-only current-customer identity, hostname Add form, saved rows, Edit and Remove controls on both pages. Add POST and Remove DELETE use the existing nested hostname routes; row Edit opens `N(@customer.id)?edit_hostname=R#hostname-form`; Manage opens `N(@customer.id)#hostname-form`. All hostname successes/422s remain on the dedicated page, not the profile page. Profile-page `edit_hostname`/target/table query parameters are ignored by this section. Native navigation/submission does not save unsent profile edits.
- **Responsive:** adjust Show's desktop-only header to `flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between`, with `min-w-0`, wrapping name/badges and stacked/wrapping actions (`min-h-11`). Edit replaces the page-wide `:narrow` override with `:full` (the existing admin default); constrain only the profile form's own wrapper with `w-full max-w-3xl`, leaving the hostname section full available width below it. Retain `space-y-6`, mobile-stacked hostname rows/actions, `md:table`, wrapping long values and local breadcrumb scrolling. No additional page shell/h1, JS or DNS-on-render behavior.

### Frozen preparation and mount interfaces

Security owns private `CustomersController#prepare_customer_hostname_section`: use the already loaded `@customer`, set `@hostname_target_customer = @customer`, and prepare `@hostnames` only through `hostname_scope.order(:hostname, :id)`, with each row's customer association populated for display. Do not invoke the query-target resolver, prepare the Customers table or perform DNS/service calls. Keep `@customer` and its validation errors intact; the profile record's persisted ID defines scope even after failed update.

Call preparation only for HTML Show/Edit GET and immediately before rendering Edit on profile-update HTML 422. Successful profile update retains its existing redirect; JSON Show/Update responses and profile query/JSON interfaces remain unchanged, with **no hostname reads for JSON**. Keep existing customer eligibility: Show uses `Customer.unscoped`, while Edit/Update retain their current `Customer` lookup; do not make inactive profile editing newly accessible. Inactive Show still renders the existing disabled-Add/retain-only hostname behavior.

Extend the local exact-platform guard to **HTML** `show/edit/update`, after inherited authorization and before section queries (preferably before `set_customer` and any profile update). Keep the current index guard. Read `request.path_parameters[:customer_id] == "81721200"`; query/body values cannot substitute. Do not broaden this supplemental guard to JSON or change shared `RouteAuthorization`.

Frontend reuses these mounts with no new required component API:

```ruby
CustomerHostnames::ManagementLinkComponent.new(
  current_user: current_user, target_customer_id: @hostname_target_customer.id
)
CustomerHostnames::ManagementComponent.new(
  hostnames: @hostnames, available_customers: [], customer_id: 81721200,
  target_customer: @hostname_target_customer,
  errors: [], form_values: {}, editing_hostname: nil, table_context: {}
)
```

Optional composition-only wrapper: `CustomerHostnames::CustomerSectionComponent.new(current_user:, target_customer:, hostnames:, customer_id: 81721200)` renders exactly those two components, substituting its props for the assigns. It has no queries, page shell, request-target resolution or alternate return mode; direct reuse above is the minimal implementation. One section/form-anchor per page, no hidden target/customer/table routing fields, and no copying profile errors/params into hostname state.

### Parallel ownership delta and acceptance

- **Frontend additionally owns** `app/views/admin/maintenance/platform/customers/{show,edit}.html.erb`: section placement, sibling forms, Show header wrapping and Edit width adjustment. If using the thin wrapper, frontend also owns `app/components/customer_hostnames/customer_section_component.{rb,html.erb}` and its component spec. Existing profile form/business behavior stays encapsulated in `CustomerFormComponent`.
- **Security additionally owns** `app/controllers/admin/maintenance/platform/customers_controller.rb`: HTML guard/preparation and failed-profile-update integration; request coverage remains in its existing `customers_spec.rb` ownership. Backend still requires no changes. Reference owner additionally documents both embedded profile sections and independent forms in both locale versions of the affected reference pages.
- **Build sequence:** freeze the assigns/mounts above → frontend mounts sections while security prepares/guards HTML profile surfaces in parallel → integrate with existing nested actions → verify focused component/customer/hostname request specs and 375/768/1440px EN/zh-CN smoke checks. Include the optional wrapper spec only if introduced.
- **Acceptance:** Show, Edit GET and profile HTML 422 display one scoped section with working Add/Edit/Remove/Manage controls and correct current identity despite conflicting, malformed or nonscalar query targets. Other customers' rows never appear. Profile HTML 422 retains profile attempts/errors and section independently; valid profile JSON Show/Update performs no hostname queries, and render/profile save performs no CNAME checks. Wrong-prefix HTML Show/Edit/Update fails before hostname reads/profile mutation, including forged query/body CID; inherited role gates still apply. Check sibling form markup and independent emitted payloads, inactive Show and unchanged inactive Edit eligibility, empty state, dedicated hostname 303/422 destination, long-name header wrapping and bilingual/mobile rendering. No runtime tests were run for this supplement.
