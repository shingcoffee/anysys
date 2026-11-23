# Page Visibility Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: execute via the anysys-* SDLC team per AGENTS.md (backend / frontend / security in parallel where phases allow, then QA, release, reviews). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three-boolean page-visibility JSON with a single hierarchical level (`admin` ⊂ `member` ⊂ `public`) where admin visibility is invariant, and let same-tenant admins open the member-rendered page directly.

**Architecture:** `pages.visibility` becomes a string column ranked by `Page::VISIBILITY_LEVELS`; `Page#visible_to?` compares ranks and fails closed. The Reform contract shrinks to an inclusion check. The Distribution card swaps three checkboxes for one radio group (`name="page[visibility]"`). `RouteAuthorization` gains a per-controller opt-in (`allow_admin_member_preview!`) admitting same-tenant admin/owner GETs to a member route; `Member::PagesController` opts in. `PublicPagesController` and `Admin::Maintenance::PageRendersController` are untouched — they inherit the new `visible_to?` semantics.

**Tech Stack:** Rails 8.1, sqlite3, Reform, ViewComponent, Tailwind, RSpec.

**Specs (read first):**
- `docs/superpowers/specs/2026-06-11-page-visibility-hierarchy-design.md`
- `docs/superpowers/specs/2026-06-11-distribution-card-ux.md`

**Execution phases:**
- Phase 1: Task 1 (backend) — everything else depends on the column + model.
- Phase 2: Task 2 (frontend) ∥ Task 3 (security) — disjoint files, dispatch in parallel.
- Phase 3: Task 4 (QA request specs).
- Phase 4: Task 5 (release verification).
- Phase 5: tech-lead ∥ code-reviewer.

---

### Task 1: Backend — migration, model, contract (anysys-backend-developer)

**Files:**
- Create: `db/migrate/20260611150000_convert_page_visibility_to_level.rb`
- Modify: `app/models/page.rb:60-84` (Visibility section) and `:96-109` (Validations section)
- Modify: `app/contracts/pages/visibility_contract.rb` (full rewrite)
- Test: `spec/models/page_spec.rb` (the `describe "visibility"` block, currently lines 404-431)
- Test: `spec/contracts/pages/visibility_contract_spec.rb` (full rewrite)

- [ ] **Step 1.1: Rewrite the model visibility spec block (failing first)**

Replace the whole `describe "visibility"` block in `spec/models/page_spec.rb` with:

```ruby
  describe "visibility" do
    it "defaults to admin level" do
      page = build(:page, customer: customer)
      expect(page.visibility).to eq("admin")
      expect(page.visible_to?(:admin)).to be(true)
      expect(page.visible_to?(:member)).to be(false)
      expect(page.visible_to?(:public)).to be(false)
    end

    it "member level is visible to members and admins" do
      page = build(:page, customer: customer, visibility: "member")
      expect(page.visible_to?(:admin)).to be(true)
      expect(page.visible_to?("member")).to be(true)
      expect(page.visible_to?(:public)).to be(false)
      expect(page.visible_audiences).to eq(%w[admin member])
    end

    it "public level is visible to every audience" do
      page = build(:page, customer: customer, visibility: "public")
      expect(page.visible_to?(:admin)).to be(true)
      expect(page.visible_to?(:member)).to be(true)
      expect(page.visible_to?(:public)).to be(true)
      expect(page.visible_audiences).to eq(%w[admin member public])
    end

    it "returns false for unrecognized audience" do
      page = build(:page, customer: customer, visibility: "public")
      expect(page.visible_to?(:unknown)).to be(false)
      expect(page.visible_to?("ghost")).to be(false)
    end

    it "rejects levels outside the hierarchy" do
      page = build(:page, customer: customer, visibility: "everyone")
      expect(page).not_to be_valid
      expect(page.errors[:visibility]).to be_present
    end
  end
```

- [ ] **Step 1.2: Rewrite the contract spec (failing first)**

Replace `spec/contracts/pages/visibility_contract_spec.rb` entirely with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::VisibilityContract do
  let(:customer) { create(:customer) }
  let(:page) { build(:page, customer: customer) }

  %w[admin member public].each do |level|
    it "accepts the #{level} level" do
      contract = described_class.new(page)
      expect(contract.validate("visibility" => level)).to be(true)
      expect(contract.visibility).to eq(level)
    end
  end

  it "accepts a symbol-keyed param" do
    contract = described_class.new(page)
    expect(contract.validate(visibility: "member")).to be(true)
  end

  it "rejects an unknown level" do
    contract = described_class.new(page)
    expect(contract.validate("visibility" => "everyone")).to be(false)
    expect(contract.errors[:visibility]).to be_present
  end

  it "rejects a missing level" do
    contract = described_class.new(page)
    expect(contract.validate({})).to be(false)
  end

  it "persists the level through save" do
    persisted = create(:page, customer: customer)
    contract = described_class.new(persisted)
    contract.validate("visibility" => "member")
    contract.save
    expect(persisted.reload.visibility).to eq("member")
    expect(persisted.visible_audiences).to contain_exactly("admin", "member")
  end
end
```

- [ ] **Step 1.3: Run both specs, confirm they FAIL**

Run: `bundle exec rspec spec/models/page_spec.rb spec/contracts/pages/visibility_contract_spec.rb`
Expected: visibility examples fail (column is still JSON).

- [ ] **Step 1.4: Create the migration**

Create `db/migrate/20260611150000_convert_page_visibility_to_level.rb`:

```ruby
# frozen_string_literal: true

# Collapses the three-boolean visibility JSON into a single hierarchical
# level string: "admin" (floor) < "member" < "public". Existing rows are
# normalised widest-flag-wins before the JSON column is dropped.
class ConvertPageVisibilityToLevel < ActiveRecord::Migration[8.1]
  def up
    add_column :pages, :visibility_level, :string, null: false, default: "admin"

    execute(<<~SQL.squish)
      UPDATE pages SET visibility_level =
        CASE
          WHEN visibility LIKE '%"public":true%' THEN 'public'
          WHEN visibility LIKE '%"member":true%' THEN 'member'
          ELSE 'admin'
        END
    SQL

    remove_column :pages, :visibility
    rename_column :pages, :visibility_level, :visibility
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

Run: `bin/rails db:migrate` then `bin/rails db:test:prepare`
Expected: migrates cleanly; `db/schema.rb` shows `t.string "visibility", default: "admin", null: false`.

- [ ] **Step 1.5: Replace the model's Visibility section**

In `app/models/page.rb`, replace the whole `# Visibility` section (the `VISIBILITY_AUDIENCES` constant, `DEFAULT_VISIBILITY`, `serialize`, `visible_to?`, `visible_audiences`) with:

```ruby
  # ==========================================================================
  # Visibility
  # ==========================================================================

  # Visibility is a single hierarchical level, ranked by index: a page at a
  # given level is visible to that audience and every narrower one
  # ("member" ⇒ members + admins, "public" ⇒ everyone). Admin visibility is
  # therefore invariant — every valid level includes it.
  VISIBILITY_LEVELS = %w[admin member public].freeze

  # Fails closed: unknown audiences and unknown stored levels are not visible.
  def visible_to?(audience)
    audience_rank = VISIBILITY_LEVELS.index(audience.to_s)
    level_rank = VISIBILITY_LEVELS.index(visibility)
    return false if audience_rank.nil? || level_rank.nil?

    level_rank >= audience_rank
  end

  def visible_audiences
    rank = VISIBILITY_LEVELS.index(visibility)
    rank.nil? ? [] : VISIBILITY_LEVELS.first(rank + 1)
  end
```

And add to the `# Validations` section (after `validates :customer_id, presence: true`):

```ruby
  validates :visibility, inclusion: { in: VISIBILITY_LEVELS }
```

- [ ] **Step 1.6: Rewrite the contract**

Replace `app/contracts/pages/visibility_contract.rb` entirely with:

```ruby
# frozen_string_literal: true

module Pages
  # Validates and persists the page's hierarchical visibility level
  # ("admin" < "member" < "public"). The hierarchy is structural — admin
  # visibility can never be turned off — so the old "at least one
  # audience" count check is gone.
  class VisibilityContract < Reform::Form
    property :visibility

    validates :visibility, inclusion: { in: Page::VISIBILITY_LEVELS }

    def deserialize!(params)
      raw = params["visibility"] || params[:visibility]
      super("visibility" => raw.to_s)
    end
  end
end
```

- [ ] **Step 1.7: Sweep for stragglers**

Run: `grep -rn "VISIBILITY_AUDIENCES\|DEFAULT_VISIBILITY" app lib db/seeds.rb 2>/dev/null`
Expected: no hits outside `db/migrate/20260611120927_add_visibility_to_pages.rb` (historic migration, leave it). If `db/seeds.rb` or any service writes hash-shaped page visibility, convert it to a level string.

- [ ] **Step 1.8: Run the specs, confirm they PASS**

Run: `bundle exec rspec spec/models/page_spec.rb spec/contracts/pages/visibility_contract_spec.rb`
Expected: all green (other blocks in page_spec must stay green too).

- [ ] **Step 1.9: Commit**

```bash
git add db/migrate db/schema.rb app/models/page.rb app/contracts/pages/visibility_contract.rb spec/models/page_spec.rb spec/contracts/pages/visibility_contract_spec.rb
git commit -m "refactor(page-builder): collapse page visibility to hierarchical level"
```

---

### Task 2: Frontend — Distribution card radio group (anysys-frontend-developer)

**Files:**
- Modify: `app/components/pages/distribution_card_component.rb`
- Modify: `app/components/pages/distribution_card_component.html.erb`
- Test: `spec/components/pages/distribution_card_component_spec.rb` (rewrite visibility-related expectations)

Read `docs/superpowers/specs/2026-06-11-distribution-card-ux.md` first — it is the authoritative layout/copy spec.

- [ ] **Step 2.1: Update the component class**

Replace the class comment, `HINTS`, and `audiences_with_rows` in `app/components/pages/distribution_card_component.rb`:

```ruby
  # Unified "Audience & Distribution" card: one radio row per audience level
  # plus the rendered-view Open links. The visibility form PATCHes
  # admin_maintenance_page_visibility_path with a single scalar param:
  # page[visibility] = "admin" | "member" | "public".
  class DistributionCardComponent < ViewComponent::Base
    DOT_CLASSES = {
      "admin"  => "bg-accent",
      "member" => "bg-member-accent",
      "public" => "bg-success"
    }.freeze

    HINTS = {
      "admin"  => "Admin only — visible to admins and owners",
      "member" => "Members — visible to signed-in members and admins",
      "public" => "Public — visible to everyone, including anonymous visitors"
    }.freeze

    def initialize(page:, customer_id:)
      @page        = page
      @customer_id = customer_id
    end

    def audiences_with_rows
      Page::VISIBILITY_LEVELS.map do |key|
        not_published = !page.published?
        not_visible   = !page.visible_to?(key)

        disabled_reason = if not_published
                            "Not published"
                          elsif not_visible
                            "Not visible to #{key.capitalize}"
                          end

        {
          key:             key,
          label:           key.capitalize,
          hint:            HINTS[key],
          dot_class:       DOT_CLASSES[key],
          checked:         page.visibility == key,
          enabled:         page.published? && page.visible_to?(key),
          disabled_reason: disabled_reason,
          open_url:        open_url_for(key)
        }
      end
    end
```

(`open_url_for` and the rest are unchanged.)

- [ ] **Step 2.2: Update the template**

In `app/components/pages/distribution_card_component.html.erb`:

1. Column header (line 13): `Visible` → `Level`.
2. Delete the member-row info note (the `<% if item[:key] == "member" %>…<% end %>` block with "Requires an active member session to open." — obsolete now that admins can open the member render).
3. Replace Col 2 (hidden input + checkbox) with a single radio per row:

```erb
          <%# Col 2: level radio — one mutually-exclusive choice across rows %>
          <div class="sm:text-center sm:w-20">
            <label class="flex sm:justify-center items-center gap-2 cursor-pointer">
              <input type="radio"
                     name="page[visibility]"
                     value="<%= item[:key] %>"
                     <%= "checked" if item[:checked] %>
                     class="h-4 w-4 border-border text-accent focus:ring-accent shrink-0">
              <span class="form-label mb-0 sm:hidden">Level</span>
            </label>
          </div>
```

Everything else (form_with PATCH, Open-link column, Save button, responsive grid) stays.

- [ ] **Step 2.3: Rewrite the component spec**

In `spec/components/pages/distribution_card_component_spec.rb`, update fixtures to string levels (`visibility: "public"`, `"member"`, `"admin"`) and assert:
- three radios `input[type=radio][name='page[visibility]']` with values admin/member/public; exactly the page's level is `checked`
- column header text "Level" (and no "Visible" header)
- no "Requires an active member session" text
- Open-link matrix: published+`"public"` page → all three Open links; published+`"member"` → admin & member links, public row disabled "Not visible to Public"; published+`"admin"` → admin link only, member row "Not visible to Member"; unpublished → all rows "Not published"
- form still PATCHes `admin_maintenance_page_visibility_path`

Keep the existing file structure (`render_component` helper, `build_stubbed(:page, …)` style). Example fixture rewrite:

```ruby
  let(:published_all_visible) do
    build_stubbed(:page, published: true, public_token: "test_token_abc", visibility: "public")
  end

  let(:admin_only_page) do
    build_stubbed(:page, published: true, public_token: "test_token_ghi", visibility: "admin")
  end
```

- [ ] **Step 2.4: Run the component spec, confirm PASS**

Run: `bundle exec rspec spec/components/pages/distribution_card_component_spec.rb`
Expected: PASS (requires Task 1's migration already applied — Phase 2 runs after Phase 1).

- [ ] **Step 2.5: Commit**

```bash
git add app/components/pages spec/components/pages/distribution_card_component_spec.rb
git commit -m "feat(page-builder): visibility level radio group in distribution card"
```

---

### Task 3: Security — admin preview of member render + scalar param (anysys-security-engineer)

**Files:**
- Modify: `app/controllers/concerns/route_authorization.rb`
- Modify: `app/controllers/member/pages_controller.rb`
- Modify: `app/controllers/admin/maintenance/page_visibilities_controller.rb:27-29`

- [ ] **Step 3.1: Add the opt-in to RouteAuthorization**

In `app/controllers/concerns/route_authorization.rb`:

Inside the `included do` block (after the `before_action` lines):

```ruby
    # Per-controller opt-in (see .allow_admin_member_preview!) letting
    # same-tenant admins/owners GET a member-namespace controller.
    class_attribute :admin_member_preview_allowed, default: false, instance_writer: false
```

Add a `class_methods` block after `included do … end`:

```ruby
  class_methods do
    # Opt-in for member-namespace controllers that admins may open directly
    # (read-only preview — GET/HEAD only; writes remain member-only).
    # Cross-tenant access is still rejected by TenantContext, and CanCan's
    # authorize_route! continues to run.
    def allow_admin_member_preview!
      self.admin_member_preview_allowed = true
    end
  end
```

In `enforce_route_role!`, extend the member branch:

```ruby
    if member_path?
      return if current_user.member?
      return if admin_member_preview_allowed && (request.get? || request.head?) &&
                current_user.admin_or_owner?

      raise CanCan::AccessDenied, "Member privileges required."
    end
```

Also extend the concern's header comment: under the pipeline description for `/member/*` add a line noting the explicit, per-controller GET-only admin preview exception.

- [ ] **Step 3.2: Opt Member::PagesController in**

Replace `app/controllers/member/pages_controller.rb` with:

```ruby
# frozen_string_literal: true

module Member
  # Renders a built page exactly as the member audience sees it
  # (member layout). Pages are tenant records, not member-owned, so the
  # gate is tenant scope + published + member visibility (no user_id check).
  #
  # Same-tenant admins/owners may also GET this render directly — the
  # "Open" link on the admin page detail — via the RouteAuthorization
  # opt-in below. The visibility gate still applies: a page must be at
  # member level or wider to render here.
  class PagesController < BaseController
    include PageRendering

    allow_admin_member_preview!

    def show
      @page = Page.for_current_customer.published.find(params[:id])
      raise ActiveRecord::RecordNotFound unless @page.visible_to?(:member)

      prepare_page_render(@page)
    end
  end
end
```

- [ ] **Step 3.3: Scalar visibility param**

In `app/controllers/admin/maintenance/page_visibilities_controller.rb` replace `visibility_params`:

```ruby
      def visibility_params
        params.require(:page).permit(:visibility).to_h
      end
```

- [ ] **Step 3.4: Sanity check — no other member controller is affected**

Run: `grep -rn "allow_admin_member_preview" app/controllers`
Expected: exactly two hits — the concern definition and Member::PagesController.

- [ ] **Step 3.5: Commit**

```bash
git add app/controllers/concerns/route_authorization.rb app/controllers/member/pages_controller.rb app/controllers/admin/maintenance/page_visibilities_controller.rb
git commit -m "feat(page-builder): same-tenant admin preview of member page render"
```

---

### Task 4: QA — request specs (anysys-qa-engineer)

**Files:**
- Modify: `spec/requests/maintenance/page_visibilities_spec.rb`
- Modify: `spec/requests/member/pages_spec.rb`
- Modify: `spec/requests/admin/maintenance/page_renders_spec.rb`
- Modify: `spec/requests/public_pages_visibility_spec.rb`
- Modify: `spec/requests/public_pages_submission_spec.rb`, `spec/requests/public_pages_theme_chrome_spec.rb`, `spec/requests/public_pages_captcha_spec.rb` (fixture shape only)

Per the stale-test policy: specs asserting the old three-boolean shape are stale — rewrite them in level terms; don't weaken production code to satisfy them.

- [ ] **Step 4.1: Fixture sweep** — replace every page-level `visibility: { "admin" => …, … }` hash with the equivalent level string (public flag true → `"public"`; else member true → `"member"`; else `"admin"`). Leave entity-field/surface/navigation visibility hashes alone.

- [ ] **Step 4.2: page_visibilities_spec** — PATCH params become `{ page: { visibility: "member" } }`. Rewrite:
  - happy path: PATCH `"member"` → redirect with notice, `page.reload.visibility == "member"`, `visible_to?(:admin)` still true
  - invalid level (`"everyone"`) → redirect with alert, value unchanged
  - the old "rejects all-off submission" example is obsolete → replace with the invalid-level example
  - member role still blocked from the admin route (keep)

- [ ] **Step 4.3: member/pages_spec** — fixtures to `visibility: "member"`. Keep: member happy path 200, unpublished 404, cross-tenant isolation, anonymous → sign-in redirect. Rewrite: "not visible" gate uses `visibility: "admin"` → 404. Add (the new behavior):

```ruby
  describe "admin preview" do
    it "allows a same-tenant admin to open the member render" do
      sign_in admin_user # same customer
      get member_page_path(customer.id, page_record)
      expect(response).to have_http_status(:ok)
    end

    it "still 404s the admin preview when the page is admin-only" do
      page_record.update!(visibility: "admin")
      sign_in admin_user
      get member_page_path(customer.id, page_record)
      expect(response).to have_http_status(:not_found)
    end

    it "rejects an admin from another tenant" do
      sign_in other_customer_admin
      get member_page_path(customer.id, page_record)
      expect(response).to redirect_to("/#{other_customer_admin.customer_id}/admin/dashboard")
    end
  end
```

(Adapt helper names — `sign_in`, user factories — to what the file already uses.)

- [ ] **Step 4.4: page_renders_spec** — fixtures to `visibility: "admin"`. The old "404 when not visible to admin" example (all-flags-false) is unrepresentable now — admin visibility is invariant. Replace it with an example asserting an admin-level page renders (200) and keep the unpublished-404 example.

- [ ] **Step 4.5: public_pages_visibility_spec** — re-express in level terms. Note semantics that CHANGE with the hierarchy:
  - member-level page: signed-in admin is now ALLOWED (visible_to?(:admin) true) — rewrite any assertion that previously expected admin rejection on `{"admin":false,"member":true}` pages
  - public-level page: everyone allowed
  - admin-level page: anonymous → sign-in redirect, member → 404, admin → 200

- [ ] **Step 4.6: Run all touched request specs**

Run: `bundle exec rspec spec/requests/maintenance/page_visibilities_spec.rb spec/requests/member/pages_spec.rb spec/requests/admin/maintenance/page_renders_spec.rb spec/requests/public_pages_visibility_spec.rb spec/requests/public_pages_submission_spec.rb spec/requests/public_pages_theme_chrome_spec.rb spec/requests/public_pages_captcha_spec.rb`
Expected: PASS.

- [ ] **Step 4.7: Commit**

```bash
git add spec/requests
git commit -m "test(page-builder): request specs for hierarchical visibility + admin member preview"
```

---

### Task 5: Release verification (anysys-release-engineer)

- [ ] **Step 5.1:** Run the touched-layer suite:
`bundle exec rspec spec/models/page_spec.rb spec/contracts/pages/visibility_contract_spec.rb spec/components/pages/distribution_card_component_spec.rb spec/requests/maintenance/page_visibilities_spec.rb spec/requests/member/pages_spec.rb spec/requests/admin/maintenance/page_renders_spec.rb spec/requests/public_pages_visibility_spec.rb spec/requests/public_pages_submission_spec.rb spec/requests/public_pages_theme_chrome_spec.rb spec/requests/public_pages_captcha_spec.rb`
Expected: 0 failures. This change touches auth gating (RouteAuthorization), so ALSO run the auth/route specs: `bundle exec rspec spec/requests --tag ~slow 2>/dev/null || bundle exec rspec spec/requests` (full request layer — auth scoping changes have wide blast radius).
- [ ] **Step 5.2:** `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` (background) and smoke-hit `/81721200/admin/maintenance/pages/43` plus the member render URL for page 43. Report PASS/FAIL with trimmed output.

---

### Task 6: Reviews (parallel)

- [ ] anysys-tech-lead: diff-only AGENTS.md convention review.
- [ ] anysys-code-reviewer: diff-only correctness + security review (especially the RouteAuthorization change).
