# Customer Search & Context Switch — Migration to Maintenance / Platform / Customers

**Date:** 2026-05-10
**Status:** Spec — pending implementation plan
**Owner area:** Admin top bar, Maintenance / Platform / Customers

## 1. Goal

Move the platform-owner customer search and customer-context-switch entry point off the admin top bar and into the existing **Maintenance / Platform / Customers** index page. After this change:

- The top bar no longer shows a "switch customer" icon/dropdown.
- The Customers index page gains a live, fuzzy-feeling search input.
- Each row gets an **Act As** action that performs the same context switch the topbar dropdown used to do.
- The mechanism for being "in" an acted-as context (the amber banner, the Return-to-Platform action, the session key) is unchanged.

## 2. Non-Goals

- No change to the Cmd+K inline navigation search (`InlineSearchComponent` / `Admin::SearchController` / `app/services/search_query.rb`). It stays on the top bar exactly as-is. It does not search customers and is not in scope here.
- No change to the underlying context-switch session machinery in `Admin::Maintenance::Platform::CustomerContextsController` or in the `TenantContext` concern.
- No change to the amber `Platform::ContextBannerComponent` ("Acting as X — Return to Platform").
- No new fuzzy-match infrastructure (no trigram extension, no Levenshtein gem). SQLite stays as-is.
- No tier filter on the Customers page. The controller's existing `?tier=` param continues to work, but no UI is added for it.
- No pagination (the page does not paginate today; out of scope).

## 3. Current State

### 3.1 Top-bar Customer Switcher (to be removed)
- `app/components/topbar_component.html.erb:36` renders `Platform::CustomerSwitcherComponent` (icon + dropdown), only when `current_user.platform_owner?`.
- The dropdown's search input calls `GET /:customer_id/admin/maintenance/platform/customer_context_searches?q=…` (Rails action: `Admin::Maintenance::Platform::CustomerContextSearchesController#index`), which runs `Customer.search_by_name(params[:q]).limit(20)` and returns JSON.
- Selecting a result calls `PATCH /:customer_id/admin/maintenance/platform/customer_context` with `customer_id=<target_id>`, handled by `Admin::Maintenance::Platform::CustomerContextsController#update`. This sets `session[:platform_acting_as_customer_id]` and redirects.
- Stimulus controller: `app/javascript/controllers/platform_customer_switcher_controller.js`.

### 3.2 Maintenance / Platform / Customers index (target home for this functionality)
- Route: `GET /:customer_id/admin/maintenance/platform/customers` → `Admin::Maintenance::Platform::CustomersController#index`.
- View: `app/views/admin/maintenance/platform/customers/index.html.erb` — breadcrumbs, header, Trash + New Customer buttons, then the `CustomerListTableComponent`.
- Controller already accepts `?search=` and `?tier=` URL params and applies `search_by_name` / `by_tier` scopes; no UI surfaces these today.
- Table renders: ID, Name, Alias, Contact, Phone, Industry, Tier, Role, Created, Actions (Edit + Delete icons).
- Access: `require_platform_owner!`.

### 3.3 What the model currently supports
- `Customer.search_by_name(query)` (model scope, `app/models/customer.rb:189`) does `LOWER(name) LIKE '%query%'` — name-only, single-token.
- DB is **SQLite**. No `description` column on `customers`. Searchable-looking columns are: `id`, `name`, `alias`, `contact`, `phone`, `address`.

## 4. Decisions

### 4.1 Search semantics
- Search across **`id`, `name`, `alias`** (these are the human-identifying columns shown most prominently in the table).
- Match style: **tokenized substring**.
  - Whitespace-tokenize the query, lowercase, drop empty tokens.
  - For each token: build an OR clause across `LOWER(name) LIKE %t%`, `LOWER(alias) LIKE %t%`, and `id = t` *only when the token is all digits*.
  - Combine multiple tokens with AND ("all words must hit somewhere").
- This is "fuzzy-feeling" enough for the realistic admin use case (multi-word, partial, across fields) without needing a trigram extension or Postgres migration. Typo tolerance is explicitly out of scope.

### 4.2 Search UX
- A single search input rendered above the customers table.
- Live update via Stimulus debounced submit (250 ms) into a Turbo Frame; no JSON endpoint, no client-side row-render duplication.
- Server is the single source of truth — controller's `Customer.search` scope filters; the existing `index.html.erb` re-renders inside the frame.
- The input value is preserved on re-render (the input lives outside the frame; or alternatively inside but value is set from `params[:search]`). See §6.4.
- Empty state copy branches: `params[:search].present?` → "No customers match your search"; otherwise "No customers yet" (existing).

### 4.3 Per-row Act As
- A small text button ("Act As") at the **start of the Actions column**, before Edit/Delete.
- Implemented as `button_to … method: :patch` to the existing `customer_context#update` route, with the target's id sent as the form's `customer_id` field.
- Hidden when the row's customer is the platform owner itself (id `81721200`) or is the currently-acted-as customer (`Current.acting_as_customer&.id == customer.id`) — there's nothing to switch to.
- The Name column remains a link to the customer's show page (unchanged) — Act-As is a separate, explicit action.

### 4.4 Top-bar removal
- Drop the `<%= render Platform::CustomerSwitcherComponent.new(...) %>` line from `topbar_component.html.erb`.
- Delete the component, its template, and its Stimulus controller.
- Delete `Admin::Maintenance::Platform::CustomerContextSearchesController` and its route — once the switcher is gone, nothing else uses that JSON endpoint.
- Keep `Admin::Maintenance::Platform::CustomerContextsController` (the actual switch + return endpoints) and `Platform::ContextBannerComponent` (the amber banner) untouched. The new Act-As button hits the same PATCH; Return-to-Platform still works the same way.

### 4.5 Search architecture
- Replace `Customer.search_by_name` with a broader scope `Customer.search` on the model itself.
- One scope, one location. No new query object, no shared service. The codebase's other "search service" (`app/services/search_query.rb`) is for the Cmd+K nav search across pages/entities/modules — different audience, different return shape, deliberately not reused.

## 5. Architecture Diagram

```
BEFORE                                       AFTER
─────────                                    ─────────
Topbar:                                      Topbar:
  [logo] [Cmd+K] [SWITCHER▾] [user]            [logo] [Cmd+K]            [user]
                  │
                  ↓ search & switch                            (gone)
                                              Maintenance / Platform / Customers:
                                                [search input]               (new)
                                                ┌──────────────────────────┐
                                                │ ID │ Name │ … │ [Act As] │ (new in row)
                                                │                  [edit][del]
                                                └──────────────────────────┘
                                                              │
                                                              ↓ PATCH customer_context (unchanged)
                                                              ↓ session flips
                                                              ↓ amber banner appears  (unchanged)
```

## 6. Implementation Detail

### 6.1 Model — `app/models/customer.rb`

Replace the existing `search_by_name` scope with a `search` scope:

```ruby
scope :search, ->(query) {
  return all if query.blank?

  tokens = query.to_s.downcase.split(/\s+/).reject(&:blank?)
  return all if tokens.empty?

  tokens.inject(all) do |relation, token|
    if token.match?(/\A\d+\z/)
      relation.where(
        "LOWER(name) LIKE :pat OR LOWER(\"alias\") LIKE :pat OR id = :id",
        pat: "%#{token}%", id: token.to_i
      )
    else
      relation.where(
        "LOWER(name) LIKE :pat OR LOWER(\"alias\") LIKE :pat",
        pat: "%#{token}%"
      )
    end
  end
}
```

Notes:
- `alias` is a SQL keyword in some dialects, so the column reference is quoted to be safe.
- The id branch only activates for all-digit tokens, avoiding spurious casts and keeping the index on `id` usable.
- `search_by_name` is removed. Any caller is updated (the only caller is the index controller, plus the deleted `customer_context_searches_controller`).

### 6.2 Controller — `app/controllers/admin/maintenance/platform/customers_controller.rb`

In `#index`, replace:

```ruby
@customers = @customers.search_by_name(params[:search]) if params[:search].present?
```

with:

```ruby
@customers = @customers.search(params[:search]) if params[:search].present?
```

No other changes to the controller.

### 6.3 Search form — new ViewComponent

`app/components/customer_search_form_component.rb` and `.html.erb`:

- Renders a `form` with `data-controller="customer-search"` and `data-turbo-frame="customers_list"`.
- Method GET, action `admin_maintenance_platform_customers_path(current_customer_id)`.
- One text input (`name="search"`, `value=<%= search %>`), with `data-action="input->customer-search#submit"` and a magnifier icon.
- Initializer takes `customer_id` and `search` (current value).

`app/javascript/controllers/customer_search_controller.js`:

- One `submit` action; debounces 250 ms; calls `this.element.requestSubmit()`.
- Cancels any pending submit in `disconnect()`.

### 6.4 Index view — `app/views/admin/maintenance/platform/customers/index.html.erb`

- Render the `CustomerSearchFormComponent` (full-width, max ~`md:max-w-md`) above the table, alongside or below the existing header row depending on visual fit (TailwindCSS only).
- Wrap the customers list section in `<%= turbo_frame_tag "customers_list" do %>` … `<% end %>`. The frame contains either the `CustomerListTableComponent` or the `EmptyStateComponent`.
- The search **form lives outside the frame** so its input keeps focus and value across frame swaps. The form renders the current `params[:search]` in its initial value.
- Empty-state copy branches by `params[:search].present?`:
  - search active + zero results: "No customers match your search" with a clear-search action that sets `?search=`.
  - blank search: existing "No customers yet" / "Add First Customer" CTA.

### 6.5 Table component — `app/components/customer_list_table_component.{rb,html.erb}`

- Add helper `act_as_button_visible?(customer)` to the Ruby class. Reuse the existing `Authentication::User::PLATFORM_CUSTOMER_ID` constant — do not redeclare:

  ```ruby
  def act_as_button_visible?(customer)
    return false if customer.id == Authentication::User::PLATFORM_CUSTOMER_ID
    return false if Current.acting_as_customer&.id == customer.id
    true
  end
  ```

- In the Actions column template, add as the first action (only when `act_as_button_visible?(customer)`):

  ```erb
  <%= button_to admin_maintenance_platform_customer_context_path(current_customer_id),
                method: :patch,
                params: { customer_id: customer.id },
                class: "...ghost-button-style...",
                form: { class: "inline" } do %>
    Act As
  <% end %>
  ```

  The existing Edit/Delete buttons are unchanged and follow it.

### 6.6 Top-bar — `app/components/topbar_component.html.erb`

- Remove line 36 (`<%= render Platform::CustomerSwitcherComponent.new(...) %>`).
- No re-arrangement of remaining items needed: the topbar's right-side flex group naturally tightens.

### 6.7 Routes — `config/routes.rb`

- Delete the line:

  ```
  resources :customer_context_searches, only: :index, controller: "maintenance/platform/customer_context_searches"
  ```

- Keep `resource :customer_context, only: %i[update destroy], …` intact.

### 6.8 Files to delete

- `app/components/platform/customer_switcher_component.rb`
- `app/components/platform/customer_switcher_component.html.erb`
- `app/javascript/controllers/platform_customer_switcher_controller.js`
- `app/controllers/admin/maintenance/platform/customer_context_searches_controller.rb`
- Any spec files exercising the above (e.g. request specs for `CustomerContextSearchesController`, component spec for the switcher, JS spec for the Stimulus controller). Confirm via grep that no remaining test references them.

### 6.9 Files to keep, untouched

- `app/controllers/admin/maintenance/platform/customer_contexts_controller.rb`
- `app/components/platform/context_banner_component.{rb,html.erb}`
- `app/components/inline_search_component.*`, `app/javascript/controllers/inline_search_controller.js`, `app/services/search_query.rb`, `app/controllers/admin/search_controller.rb` (Cmd+K).
- The `TenantContext` concern and everything driving `Current.acting_as_customer`.

## 7. Data Flow

### 7.1 Search keystroke
1. User types in the input. Stimulus debounces 250 ms; calls `form.requestSubmit()`.
2. Browser issues `GET /:customer_id/admin/maintenance/platform/customers?search=acme+tech` with `Accept: text/vnd.turbo-stream.html` (Turbo Frame request).
3. Controller runs `Customer.by_name.search("acme tech")` → SQL like:
   `WHERE (LOWER(name) LIKE '%acme%' OR LOWER("alias") LIKE '%acme%') AND (LOWER(name) LIKE '%tech%' OR LOWER("alias") LIKE '%tech%')`.
4. Server renders `index.html.erb`. Turbo swaps only `#customers_list`. Search input outside the frame is untouched (focus and value preserved).

### 7.2 Act As click
1. User clicks **Act As** on a row.
2. Browser POSTs `_method=patch` to `/:customer_id/admin/maintenance/platform/customer_context` with `customer_id=<target_id>`.
3. `CustomerContextsController#update` (unchanged) sets `session[:platform_acting_as_customer_id] = target_id`, redirects to the target customer's admin dashboard.
4. On the next page load, `TenantContext` populates `Current.acting_as_customer`; `Platform::ContextBannerComponent` renders the amber banner. Return-to-Platform still posts a DELETE to clear the session key.

## 8. Edge Cases

- **Blank query** → scope returns `all`; full sorted list shown.
- **Whitespace-only query** → tokens empty after `reject(&:blank?)`; scope returns `all`.
- **Numeric token (e.g. `81721200`)** → matches `id = 81721200` OR substring of name/alias.
- **Mixed-alphanumeric token (e.g. `acme1`)** → only name/alias substring (id branch skipped).
- **Multiple tokens** → AND across tokens; each token can hit a different field.
- **SQL injection** → all user input passes through bind parameters. No string interpolation of query into SQL.
- **Soft-deleted customers** → `default_scope { visible }` excludes them; Trash page is unaffected.
- **Non-platform-owner user** → `require_platform_owner!` blocks the page and the Act-As endpoint already.
- **Acting as someone, then searching** → search works the same; Act-As button is hidden for the currently-acted-as row to avoid a no-op switch.
- **Acting as someone, then clicking "Act As" on a different row** → the existing controller updates the session to the new id; there is no double-banner state.
- **Return to Platform** → unchanged; amber banner's Return link still points at `customer_context_path` DELETE.

## 9. Testing

### 9.1 Model spec — `spec/models/customer_spec.rb`
Add a `describe ".search"` block:
- blank query → returns all
- single name token (case-insensitive) matches by name
- single token matches by alias
- all-digits token matches by id
- all-digits token also matches a name/alias containing those digits (OR semantics)
- mixed-alpha token does not produce id matches even if numerically substring
- multi-token AND: token A matches name, token B matches alias → row appears
- multi-token AND: token A matches one row, token B matches a different row → empty result
- whitespace-only / nil → all

### 9.2 Component specs
- `spec/components/customer_search_form_component_spec.rb` — renders form with `data-turbo-frame="customers_list"`, GET method, action path, current `search` value pre-filled, Stimulus `data-controller="customer-search"`.
- `spec/components/customer_list_table_component_spec.rb` — extend existing spec:
  - Act-As button rendered for a normal customer
  - Hidden when `customer.id == Authentication::User::PLATFORM_CUSTOMER_ID`
  - Hidden when `Current.acting_as_customer&.id == customer.id`
  - Edit / Delete actions still render

### 9.3 Request spec — `spec/requests/admin/maintenance/platform/customers_spec.rb`
- `GET …/customers?search=acme` returns 200 and the rendered table contains only matching customers.
- `GET …/customers?search=` (blank) returns full list.
- A non-platform-owner user is redirected with the existing access-denied alert.

### 9.4 Removal verification
- After deleting the switcher and search-endpoint files, run `grep -r CustomerContextSearchesController` and `grep -r CustomerSwitcherComponent` and `grep -r platform_customer_switcher` to confirm nothing references them. Same for `search_by_name`.
- The route `customer_context_searches` no longer appears in `bin/rails routes`.

### 9.5 Manual verification (UI / golden path)
- Sign in as a user with role `owner` under customer `81721200`.
- Navigate to Maintenance / Platform / Customers.
- Type `"acme"` → table filters live (no full-page reload), input keeps focus.
- Type `"81721200"` → the platform-owner row is found; its Act-As button is **not** shown.
- Type a partial id of another customer → that row found; Act-As shown; click → amber "Acting as X" banner appears, sidebar/dashboard now reflects target customer.
- Click Return to Platform → banner disappears, back to platform view.
- Top bar no longer shows the people-icon switcher.

## 10. Risks & Mitigations

- **Token search performance.** Each token adds an OR'd `LIKE '%…%'` per field; on tens of thousands of customer rows that's slow. Today's customer count is far smaller; if we ever exceed ~10k, we revisit (FTS5 in SQLite, or Postgres + `pg_trgm`).
- **Loss of the global "switch from anywhere" affordance.** Acting-as now requires navigating to the Customers page first. This is a deliberate trade for a single source of truth and is acceptable given the audience (platform owner, infrequent action).
- **Frame-swap focus loss** if anyone moves the search input inside the frame. Mitigated by keeping the input outside the `turbo_frame_tag` block.

## 11. Out of Scope (explicit)

- Tier filter UI on the Customers page.
- Pagination of the Customers list.
- Trigram / Levenshtein typo tolerance.
- Searching across `contact`, `phone`, `address`, `industry`.
- Any change to Cmd+K navigation search.
- Any change to the amber acting-as banner.
- Any change to how `session[:platform_acting_as_customer_id]` is set or read.
