# Customer hostnames — customer context and DNS Save gate

Date: **2026-10-10**. Status: **READY_FOR_FRONTEND / READY_FOR_PARALLEL_BUILD**. Research/design and implementation plan only; runtime verification belongs to the build.

## 1. Settled scope and research

`target_customer_id` becomes a persistent **customer-bound management mode**, replacing the earlier preselection hint. Without that parameter, Customers retains the global hostname form/dropdown/list. Every otherwise-valid Save must verify a direct CNAME to `anysys.net` before persistence, including unchanged-hostname and customer-only edits. Use existing routes, schema and native forms; no new JavaScript or gem.

Read `.cursor/agents/anysys-ux-designer.md`, project conventions, `CustomerHostnames::ManagementComponent`/`ManagementLinkComponent`, the Customers index/details views, `AdminTableComponent`, Card/Button/Alert primitives, both controllers, `CustomersIndexContext`, Save/Destroy Activities, Reform contract and existing context/concurrency specs. This plan supersedes the suggestion-only and no-DNS-check portions of the 2026-10-09 plans; the combined-page structure remains the baseline.

The shadcn skill/MCP is unavailable in this harness. The parent consulted the official [Field reference](https://ui.shadcn.com/docs/components/field), also reviewed for this plan: stacked FieldTitle/read-only content/FieldDescription; editable FieldLabel/control/FieldDescription/FieldError; responsive grouping and accessible validation. Deliver these patterns through existing ViewComponent + Tailwind composition. DNS research: [Ruby 3.2 Resolv::DNS](https://docs.ruby-lang.org/en/3.2/Resolv/DNS.html) and [Ruby 3.2.8 source](https://github.com/ruby/ruby/blob/v3_2_8/lib/resolv.rb).

## 2. Surface inventory and layout

| Surface | Navigation area | Design |
|---|---|---|
| Customer details → Manage customer hostnames | admin → Maintenance → Platform → Customers | Existing link opens fixed platform Customers index with the displayed customer's ID and `#hostname-form`, including inactive customers. |
| Customers index without target | Same | Existing customer table, then global hostname form and saved list. |
| Customers index with `target_customer_id=C` | Same | Existing customer table, then customer-bound hostname form/list; customer-table search/sort/page never changes the target. |
| Existing POST/PATCH/DELETE hostname endpoints and full-page 422 | Same | Native mutation/failure flow retains mode, table context, attempted hostname and saved edit identity. |
| Existing owner discovery links, including Page shortcuts | admin → Maintenance → Page shortcuts | Any supplied target now enters bound mode; links without target enter global mode. |

```text
Customers h1 + existing page actions
Existing Customers table/search/sort/pagination

Customer hostnames h2 + existing description
┌ Add hostname / Edit hostname h3 ────────────────────────┐
│ DNS/deployment instructions; persistent error summary  │
│ Hostname                       Customer                │
│ [forms.example.com       ]     Acme (12345678)          │
│ Exact-host + CNAME help/error   Bound-context help      │
│ Inactive-target explanation, when applicable           │
│ [Add hostname / Save] [Cancel, edit only]               │
└────────────────────────────────────────────────────────┘
┌ Saved hostnames h3 + customer-specific list description┐
│ Hostname | Customer name + ID | Availability | Actions  │
│ Only bindings with customer_id = C; Edit / Remove       │
└────────────────────────────────────────────────────────┘
```

- Reuse `AdminPageComponent` once, `AdminTableComponent`, both existing `CardComponent(padding: :none)` cards, `ButtonComponent`, `AlertComponent(type: :error, auto_dismiss: false)`, `BadgeComponent` and `EmptyStateComponent`. New components: **none**.
- In bound mode replace the customer select with a read-only text group: translated Customer title (`form-label` styling), escaped `target_customer.name` + ID using `customer_hostnames.customer_option`, and a context hint. Use `role="group"`, `aria-labelledby` and `aria-describedby` for the title/help/error; do not associate a `<label for>` with a nonexistent input. No disabled dropdown or focusable pseudo-control. Bound customer identity always comes from the server target, never attempted nested fields.
- Keep hostname label/input/help/error and `aria-invalid`/`aria-describedby`; customer validation errors remain visible beneath the read-only identity and in the `role="alert"` summary. Base conflict errors appear in the summary.
- Preserve `p-4 sm:p-6`, `space-y-5`, field `space-y-2`, `grid grid-cols-1 gap-4 md:grid-cols-2`, `min-w-0`, project text/color tokens, `break-words` names/errors, `break-all` hostnames and `min-h-11` actions. Actions stack full-width below `sm`; saved rows retain the semantic mobile-stack/`md:table` composition and all actions.
- Inactive existing target: show its name/ID and translated explanation; disable hostname/add controls and submit in add mode. A scoped existing binding may retain that inactive customer while editing its hostname, with Save and Remove enabled. No reassignment UI in bound mode. Global mode keeps current active choices and retain-only editing behavior.
- Empty bound list: existing EmptyState with contextual description; add form remains visible. Empty customer-search results also retain the bound section. Availability continues to mean customer activity, not live DNS/TLS health.
- Loading is ordinary native navigation. Save may wait for bounded DNS lookup; no new spinner/check action. Failure uses the complete 422 page with persistent summary and inline hostname error. TLS, ingress and HostAuthorization still require deployment configuration.

## 3. State and navigation contract

Let `C` be `/81721200/admin/maintenance/platform/customers`, `T` the sanitized scalar `q/sort/dir/page`, and `B` the validated `target_customer_id` when bound.

| Flow | Required outcome |
|---|---|
| Details discovery | `C?target_customer_id=<displayed-id>#hostname-form`; never drop the ID merely because the customer is inactive. |
| Add / Edit | Native POST `C/hostnames` or PATCH `C/hostnames/:id` carries T and B; Edit GET also carries clicked `edit_hostname` and anchor. |
| Successful Save / Remove | 303 to `C?T&B#hostname-form`; clear `edit_hostname`, show translated flash, refreshed scoped list and blank add form with retained read-only customer. |
| Cancel | GET `C?T&B#hostname-form`; clear edit state and retain target/table state. |
| Validation / DNS / Remove failure | Full dashboard-layout 422 with T/B, errors, raw attempted hostname (including blanks), and saved edit identity. Failure preparation must not reset mode or apply old suggestion logic. |
| Customer table search / sort / page | Keep B. Search resets page as today; sorting/pagination preserve existing semantics. Customer table itself remains global. |
| Invalid target / unavailable record | Standard 404 for malformed, blank, nonscalar or nonexistent supplied target, and for missing/foreign edit/update/remove records. A completely absent target parameter is valid global mode. |

Native removal forms retain T/B and currently rendered edit/form state for failed removal display only; Destroy receives the route-selected record, not those display fields. Delete success clears edit state even when a different row was being edited. Table navigation need not retain `edit_hostname`; it must retain bound mode. Global success/cancel still returns to global add mode.

## 4. Agreed frontend/controller API

```ruby
CustomerHostnames::ManagementComponent.new(
  hostnames: @hostnames, available_customers: @available_customers,
  customer_id: current_customer_id, target_customer: @hostname_target_customer,
  errors: @errors || [], form_values: @form_values || {},
  editing_hostname: @editing_hostname, table_context: @table_context || {}
)
```

### Frontend boundary

- Add `target_customer: nil` to the component. Keep `customer_id` as the platform URL customer, distinct from the target. Continue slicing component `table_context` to **q/sort/dir/page only**.
- Derive a separate target-context hash from `target_customer.id`; merge it into `index_path`, `edit_path`, mutation path helpers and `removal_params`. Add exactly one hidden **top-level** `target_customer_id` to Save and Remove submissions; avoid duplicate hidden controls when mutation paths also contain the query parameter.
- Bound Save may omit nested `customer_hostname[customer_id]`; the controller sets it authoritatively. Display/form helper precedence for customer ID uses the target in bound mode, while raw attempted hostname and global raw customer-field behavior remain as today.
- Customers index passes `target_customer: @hostname_target_customer`. Its `AdminTableComponent` receives security-prepared `@table_context` containing T plus validated B.
- **No extra AdminTable context prop is needed:** its native GET form already emits non-search/filter/page/sort/dir params as hidden fields (`admin_table_component.html.erb:41–43`), and sort/page helpers merge `params`. The fixed `base_path`, `turbo_page_requires_reload` and explicit dashboard layout already prevent stale sibling form context, including frame requests and 422 pages. Verify this existing behavior rather than replacing it.
- Customer details currently passes `@customer.active? ? @customer.id : nil`; change the mount to pass `@customer.id`. Shared link destination/API already fits the design.

### Security/controller boundary

- Keep inherited authentication/platform-owner authorization, then exact `request.path_parameters[:customer_id] == "81721200"` guard, **before target, table or hostname queries**. Apply local preparation to index and hostname CUD; do not alter shared authorization or other customer workflows.
- Add concern `prepare_hostname_target_customer`: distinguish absent key from invalid supplied value; require scalar strict eight-digit ID through `PageShortcuts::PathPolicy.customer_id`, then `Customer.unscoped.find` so inactive existing customers remain addressable. Set `@hostname_target_customer`, or raise `RecordNotFound` for bad/missing targets. Run before shared table preparation and scoped record lookup, including JSON index requests carrying a target.
- Add concern `hostname_scope`: target present → `CustomerHostname.where(customer_id: @hostname_target_customer.id)`; otherwise global relation. Use it for list, GET `edit_hostname`, route-selected update/remove, saved edit reload on Save failure, and optional edit restoration on Remove failure. Mutation identity remains `request.path_parameters[:id]`; query/body record IDs never override it.
- In bound Save override permitted nested `customer_id` with target ID, even when missing, blank or forged. Keep hostname input raw for failure rendering. Prepare scoped rows and batched inactive customer identity; dropdown choices are needed only for global mode.
- Security owns `@table_context`: allowlisted scalar T plus canonical validated B. `ModuleEntriesResolver` receives **only** `@table_context.slice("q", "sort", "dir", "page").symbolize_keys`; target is UI/navigation state, never a customer-table filter. Fixed return helpers retain T/B, clear edit state and keep `#hostname-form`.
- Concurrency handoff: pass optional `expected_customer_id: @hostname_target_customer&.id` to Save/Destroy. Backend must compare it with the stored binding under the mutation lock; a post-scope reassignment fails with localized `binding_changed`, never reassigns back or deletes another customer's row. Initial foreign IDs remain controller 404s. Activity conflicts render 422 while the edit identity still resolves within scope; if it has moved/disappeared, scoped failure preparation returns 404 instead of rendering a foreign row or silently switching to create.

## 5. DNS service and persistence sequencing

Use a thin `CustomerHostnames::CnameVerifier` at `app/services/customer_hostnames/cname_verifier.rb`, wrapping Ruby stdlib `Resolv` with one public `call(hostname:)` returning `:verified` or `:unverified`. No DNS in the model/Reform contract, render path, Destroy or locked transaction. Existing Save Result/error shape remains intact.

1. Save's early Reform validation uses a fresh saved baseline and captures the normalized candidate hostname. Invalid syntax/customer/uniqueness errors return normally before network I/O.
2. Before opening the persistence transaction, query the absolute candidate (`"#{normalized_hostname}."`) for `Resolv::DNS::Resource::IN::CNAME`. Use a per-call resolver and explicit finite retries (`timeouts = [1]`) plus a **3-second overall lookup deadline**, covering multiple nameservers and TCP fallback/connect/read. Close resolver/request resources on every exit; isolate deadline handling inside this I/O-only wrapper.
3. Require answer-section CNAME records whose owner is exactly the queried hostname and whose unique normalized target is exactly `anysys.net` (case and one terminal dot insensitive). Do not accept A/AAAA, address equality, suffix matching, flattened aliases or a later hop to `anysys.net`. Preserve owner identity using `fetch_resource`'s reply and answer entries; high-level resource objects hide that identity, and extraction iterates other sections. Use stdlib decoding/request handling, not a hand-written DNS protocol.
4. Empty answers, NXDOMAIN, wrong/mixed targets, malformed replies, resolver errors or deadline/transport failures return `:unverified`; never persist or fail open. A single localized hostname error explains the direct CNAME requirement and retry. Use a new resolver on each Save; no app-level successful-result cache or unchanged-hostname bypass.
5. Once verified, retain `(normalized_hostname, verified)` as request-local evidence. Preserve existing parent-before-child ordered locks, reload, active/retain-only/unique/FK validation and atomic two-field persistence. Compare the locked contract's **final normalized hostname** with the verified candidate before sync/save. A mismatch returns existing localized `binding_changed`; no DNS retry under locks. This protects omitted-hostname/customer-only updates when another writer changes the stored hostname during lookup.
6. Recheck bound `expected_customer_id` under lock as above. Destroy also locks/reloads and verifies ownership before deletion, with no DNS dependency. Existing global stale-write and inactive-retention semantics remain where final hostname evidence still matches. Concurrent hostname evidence mismatch requires reload/retry.

The gate establishes only the required Save-time DNS configuration; saved availability badges are not a cached DNS status, and the check does not provision deployment infrastructure.

## 6. Localization contract

Frontend owns paired `config/locales/customer_hostnames.en.yml` / `.zh-CN.yml`; backend owns paired `customer_hostname_errors.en.yml` / `.zh-CN.yml`. Reuse existing customer identity, actions, availability, empty title and flashes. Add/update these proposed keys with identical locale/interpolation sets; translate at render/request time:

| Key under `customer_hostnames` | English | 简体中文 |
|---|---|---|
| `target_customer_hint` | Hostnames on this page belong to this customer. | 本页主机名仅属于此客户。 |
| `target_inactive_hint` | This customer is inactive. Existing hostnames can be edited or removed; new hostnames cannot be added. | 此客户已停用。可编辑或移除现有主机名，无法新增。 |
| `target_saved_hint` | Showing hostnames for %{customer}. | 仅显示 %{customer} 的主机名。 |
| `target_empty_hint` | No hostnames are assigned to %{customer} yet. | %{customer} 尚未绑定主机名。 |
| `hostname_hint` | Enter an exact hostname without a scheme, port or path. Its direct CNAME must point to anysys.net; checked on every Save. | 请输入不含协议、端口或路径的完整主机名。其直接 CNAME 必须指向 anysys.net，每次保存均会校验。 |
| `deployment_hint` | Configure a direct CNAME to anysys.net before saving. TLS, ingress and Rails HostAuthorization are configured separately by deployment. | 保存前请将直接 CNAME 配置为 anysys.net。TLS、入口路由及 Rails HostAuthorization 仍由部署单独配置。 |
| `errors.cname_unverified` | The hostname must have a direct CNAME to anysys.net. Check DNS configuration and try saving again. | 主机名必须配置直接指向 anysys.net 的 CNAME。请检查 DNS 配置后重新保存。 |

`%{customer}` uses the localized name/ID label. Keep `availability_hint` accurate: customer status does not guarantee current DNS/TLS readiness.

## 7. File ownership and coordination

| Owner | Exclusive files / responsibility |
|---|---|
| Backend developer | New `app/services/customer_hostnames/cname_verifier.rb`; `app/services/customer_hostnames/activities/{save,destroy}.rb`; paired `customer_hostname_errors` locales; `spec/services/customer_hostnames/cname_verifier_spec.rb` and Activity specs. Own DNS bounds/directness, final-value evidence and optional `expected_customer_id` mutation guards. Reform contract stays pure; edit only if normalization interface requires it. |
| Security engineer | `app/controllers/concerns/customer_hostnames/customers_index_context.rb`; `app/controllers/admin/maintenance/platform/{customers,customer_hostnames}_controller.rb`. Own guards, target resolution, `hostname_scope`, authoritative customer payload, resolver slicing, 303/422/404 and restoration scoping. |
| Frontend developer | `app/components/customer_hostnames/management_component.{rb,html.erb}`; `app/views/admin/maintenance/platform/customers/{index,show}.html.erb`; paired `customer_hostnames` UI locales. Own target prop, read-only field, inactive states, hidden/context/path preservation and table parameter wiring. No shared table implementation changes are expected. |
| QA engineer | Hostname component/link specs; Customers/hostname/combined-flow request specs; targeted AdminTable native hidden-context regression; discovery specs as needed. Own authorization, forged/foreign IDs, inactive mode and native context/DNS-error rendering integration. Stub verifier at its boundary; never depend on public DNS in specs. |
| Parent/integration doc owner | Paired reference updates and final merge review. Backend/frontend provide changed API/copy notes; security provides context/guard notes. |
| Release engineer | Scoped test execution, Tailwind rebuild and responsive/bilingual/native browser smoke checks; follow project asset/server instructions if a restart is needed. |

Before parallel build, agree on `target_customer`, `@hostname_target_customer`, canonical B in `@table_context`, pure T resolver input, verifier outcome/error key, and optional Save/Destroy `expected_customer_id:`. Keep UI/error locale files and test files with their listed owners to avoid overlapping edits. Existing specs asserting discarded targets, foreign edits taking precedence, or inactive detail links becoming global must be updated to the new contract, not preserved as compatibility behavior.

Sequence: freeze these interfaces → parallel backend/security/frontend implementation → QA integrates native/DNS/race regressions and reference owner synchronizes both locales → release runs scoped checks and browser smoke → parent reviews conventions and correctness.

## 8. Acceptance, checks and reference updates

- Bound rows/identity never leak another customer; forged/missing nested customer IDs are overridden. Initial foreign edit/update/remove and malformed/blank/nonscalar/nonexistent supplied targets return 404. Absent target is global; inactive existing target remains visible with disabled add and retain-only edit/removal.
- Exercise native emitted Add/Edit/Cancel/Save/Remove controls with CSRF, T/B retained through 303 and 422; search GET hidden target, sort and pagination remain bound, including zero search results and frame-originated whole-page responses. Test DNS failure after unchanged-hostname Save and preserve attempted hostname/edit state on failed Remove.
- Verifier tests cover exact/mixed-case/terminal-dot success; wrong target, absent CNAME, A-only, CNAME chain, unrelated owner/sections, conflicting targets, malformed/timeout/resolver/transport failure, finite retry/deadline and cleanup. Use deterministic stdlib reply fixtures/fake resolver I/O.
- Activity tests cover every otherwise-valid Save, unchanged/customer-only edits, no DNS under Save-acquired DB locks, locked final-value mismatch, concurrent target reassignment, atomic failure and existing uniqueness/FK/inactive retention races. Destroy remains usable when DNS is unavailable.
- Run touched service/Activity/contract, hostname component/link, AdminTable regression and `spec/requests/admin/maintenance/platform/{customers,customer_hostnames,customers_hostnames_merge}_spec.rb` plus relevant discovery specs. Rebuild Tailwind and browser-smoke at 375/768/1440px in EN/zh-CN; hostname flows work with JavaScript disabled. No tests were run for this design-only artifact.
- In the implementation change, update **both locales** of `doc/reference/{en,zh-CN}/{customer-hostnames,customers,page-shortcuts,tenancy-and-roles,system-map,access-grants}.md`: replace suggestion-only/edit-wins/target-cleared claims; document bound scoping, inactive behavior, table context, API and DNS/concurrency gate. Search remaining references for contradictory DNS wording. This existing surface needs no catalog addition.
