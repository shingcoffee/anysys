# Member Page Kit & Surface Registry — Design

**Date:** 2026-05-23
**Status:** Draft for review (revised 2026-05-24 to add admin-configurable overlay)
**Scope:** A unified layout, styling, and registration model for read-only member surfaces. Refactors today's bespoke Profile / Security / Payments pages onto a shared page kit, introduces a per-module `MemberSurface` descriptor so a future surface drops in by adding a single file next to the module, **and** adds a per-tenant settings overlay so the customer admin controls which surfaces appear and how they're labelled / paginated / filtered down.

Builds on the foundation laid down in [`2026-05-15-member-skeleton-design.md`](2026-05-15-member-skeleton-design.md).

---

## 1. Background and motivation

The member skeleton (2026-05-15) gave us a shell, layout, four hand-written pages, a navigation registry, and a small token namespace. What it did **not** give us:

1. A consistent **page anatomy** — Profile, Security, and Payments each repeat the same `<header>` + `<section class="card-member-elevated">` structure with subtle inconsistencies (Profile uses an avatar block, Security uses three sections, Payments uses a table-in-card; all could be expressed as `PageHeader` + one or more `PageSection`s).
2. A reusable **index/detail vocabulary** — Payments index hand-rolls a table; the same shape will be repeated by every read-only member listing (course scores, donations, etc.).
3. A **registration mechanism** for tenant-visible read-only data — adding a new surface today means writing a controller, two views, a route, a navigation entry, and possibly a column-formatting helper. This spec lowers that to **one descriptor file** for the read-only index/detail case.
4. A **per-tenant override** of the member surface — a customer admin should be able to turn each module's member surface on/off, rename it, reorder it, choose which columns the member sees, and so on, without anyone touching code.

The motivating example: "a customer defines a 'Course' entity for students; the member member can access all his/her scores for each course." After this spec lands, that requires one file (the descriptor) and zero code changes when a tenant wants to call it "Grades" instead, hide the term column, or move it above Payments in the nav.

## 2. Goals and non-goals

**Goals**

1. Every member page follows the same anatomy: `PageHeader` (title + subtitle + optional eyebrow + optional meta badge) above one or more `PageSection`s (`card-member-elevated` wrappers).
2. Read-only listings — payments, course scores, donations, registrations, attendance — render through a uniform `IndexTable` + `DetailGrid` pair, configured by a `Member::Surface` descriptor that lives next to the module that owns the data.
3. The member surface contract is read-only. The kit covers index and detail; mutations remain bespoke.
4. Existing pages (Profile show, Profile edit, Security, Payments) are refactored onto the kit. After the refactor, Payments is descriptor-driven; Profile and Security keep their controllers but compose through the kit's components.
5. A new member surface is added by:
   - Defining the model.
   - Dropping `app/services/feature_modules/<name>/member_surface.rb` with the descriptor.
   - The kit auto-registers the surface, creates a default settings row on first access, surfaces it in the nav, and renders index + detail at `/:cid/member/<key>` and `/:cid/member/<key>/:id`.
6. **The customer admin can configure each descriptor-driven surface** at `/:cid/admin/settings/member` — visibility, label, icon, subtitle, navigation position, page size, visible columns, visible detail fields — without code changes.

**Non-goals**

- Filters or column-sort UI on the member side (deferred — YAGNI until a second descriptor wants them).
- Mutation flows (create / edit / destroy) through the kit. The single existing mutation (Profile edit) stays bespoke.
- Coupling with the code generator (`app/services/code_generator/*`).
- Engine extraction.
- Member-side admin features (search, export, bulk actions). Read-only listings only.
- Tenant authorship of new descriptors via the admin UI. Descriptors remain code-defined; the admin overlays *configure* what code already declared possible. Adding a new descriptor still means committing a `.rb` file.
- Configuration of bespoke pages (Home / Profile / Security). They appear in the settings page as read-only "built-in" entries that customers cannot relabel or hide.

## 3. Architecture

### 3.1 Two-tier component system

The kit splits into **primitives** (low-level building blocks) and **composers** (high-level shells that consume an effective surface).

```
PRIMITIVES                              COMPOSERS
(used by anything, including            (used by descriptor-driven surfaces)
 bespoke pages like Profile/Security)
─────────────────────────────────       ───────────────────────────────────
Member::PageHeaderComponent        Member::SurfaceIndexComponent
Member::PageSectionComponent       Member::SurfaceDetailComponent
Member::IndexTableComponent
Member::DetailGridComponent
Member::EmptyStateComponent
Member::PaginationComponent
```

### 3.2 Module-owned descriptor

A module declares a member surface by adding one file at `app/services/feature_modules/<module>/member_surface.rb`. The file assigns a `Member::Surface` instance to the constant `MemberSurface` under the module's namespace. Module folder names follow the existing project convention (singular, matching `FeatureModules::*::Registration#module_key`): `payment`, `email`, `sms`, `authentication`, etc.

```
app/services/feature_modules/
  payment/
    member_surface.rb        # NEW — replaces Member::PaymentsController
    provisioner.rb                # existing
    registration.rb               # existing
  courses/                        # FUTURE (illustrative)
    member_surface.rb
    provisioner.rb
    registration.rb
```

`Member::Surfaces` (registry) auto-discovers descriptors at boot by enumerating registered modules and looking up `FeatureModules::<Camelized>::MemberSurface` for each. There is no central manifest to update.

### 3.3 Per-tenant overlay

A descriptor declares the **shape** of a surface (what columns / fields exist, how they're scoped, how they're formatted). Each customer overlays an opinion on top of that shape: which subset is visible, what the labels read, where it sits in the nav, etc.

```
                ┌───────────────────────┐
                │  Member::Surface  │  ← code-defined, ships in the repo
                │  (descriptor)          │     (label, icon, scope, columns,
                └───────────┬───────────┘      detail rows, per_page default)
                            │
                            │ overlays
                            ▼
        ┌──────────────────────────────────────┐
        │ Member::SurfaceSetting           │  ← per-customer, in the DB
        │   customer_id  : 12345678             │     (enabled, label, icon,
        │   surface_key  : payments             │     subtitle, position,
        │   position     : 30                   │     per_page, visible_columns,
        │   enabled      : true                 │     visible_detail_rows)
        │   config       : { label, icon, ... } │
        └──────────────────────────────────────┘
                            │
                            │ resolved at request time
                            ▼
            ┌─────────────────────────────────┐
            │ Member::EffectiveSurface    │  ← Plain wrapper used by the
            │   delegates to descriptor where  │     controller / nav / kit
            │   no override is set, otherwise  │     components — same surface
            │   returns the override value     │     interface as the bare
            └─────────────────────────────────┘     descriptor.
```

The two layers are kept independent:

- The **descriptor** is the maximum capability — it declares every column / field that exists.
- The **settings row** can only narrow that — it can hide a column but not invent one, rename an existing label but not change which records are scoped in.
- A descriptor with no settings row resolves to the descriptor defaults (the system fails open: a brand-new module that the admin hasn't visited yet still works).

### 3.4 Routing

```ruby
# config/routes.rb — under the existing 2c. MEMBER block.
namespace :member do
  resource  :dashboard, only: :show, controller: "dashboards", path: ""
  resource  :profile,   only: %i[show edit update]
  resource  :security,  only: :show, controller: "securities"
  resources :surfaces,  only: %i[index show], param: :id, path: ":key"
end
```

```ruby
# config/routes.rb — under the existing 2b. ADMIN settings block.
namespace :settings do
  # ...
  resource :member, only: %i[show update], controller: "settings/member"
end
```

The member `:key` segment captures into `params[:key]` and resolves through `Member::Surfaces.fetch(key, customer:)`. Existing user-visible URLs are preserved: `/:cid/member/payments` continues to resolve because the Payments descriptor declares `key: :payments`.

`Member::PaymentsController` and `app/views/member/payments/*` are deleted as part of this work — the descriptor replaces them.

### 3.5 Generic surface controller

```ruby
class Member::SurfacesController < Member::BaseController
  before_action :load_surface

  def index
    scope                = @surface.index.scope.call(current_user)
    @records, @page_meta = Member::PageFilters.paginate(
      scope, page: params[:page], per_page: @surface.index.per_page
    )
    render "member/surfaces/index"
  end

  def show
    @record = @surface.index.scope.call(current_user).find_by(id: params[:id])
    authorize_owned!(@record)
    render "member/surfaces/show"
  end

  private

  def load_surface
    @surface = Member::Surfaces.fetch(params[:key], customer: current_customer)
    raise ActiveRecord::RecordNotFound unless @surface.enabled_for?(current_user)
  end
end
```

The two views `app/views/member/surfaces/index.html.erb` and `show.html.erb` are one-liners that render `SurfaceIndexComponent` / `SurfaceDetailComponent` with `@surface`, `@records` / `@record`, and `@page_meta`. Note `@surface` here is an *effective surface* — descriptor + customer overlay merged.

## 4. The `Member::Surface` descriptor

### 4.1 Top-level shape

```ruby
Member::Surface = Struct.new(
  :key,           # Symbol — URL slug AND nav key (must match `\A[a-z][a-z0-9_]*\z`)
  :label,         # String — top-nav label (admin can override)
  :icon,          # Symbol — Heroicons key (admin can override)
  :enabled_for,   # ->(user) -> Boolean — module-level gate (admin overlay AND'd on top)
  :index,         # Member::Surface::Index
  :detail,        # Member::Surface::Detail
  :default_position, # Integer — fallback nav order when no SurfaceSetting row exists
  keyword_init: true
) do
  def enabled_for?(user) = enabled_for.call(user)

  def validate!
    raise ArgumentError, "key must be lowercase identifier" unless key.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
    raise ArgumentError, "label required"                   if label.blank?
    raise ArgumentError, "index required"                   unless index.is_a?(Index)
    raise ArgumentError, "detail required"                  unless detail.is_a?(Detail)
    index.validate!
    detail.validate!
  end
end
```

### 4.2 Index spec

```ruby
Member::Surface::Index = Struct.new(
  :title,         # String
  :subtitle,      # String — optional (admin can override)
  :scope,         # ->(user) -> ActiveRecord::Relation (must be tenant- and user-scoped)
  :columns,       # Array<Hash> — see column shape below
  :empty_state,   # Hash { headline:, body:, icon: }
  :per_page,      # Integer — descriptor default; admin can override
  keyword_init: true
)

# Column shape (NEW — `key:` is required for admin-configurable visibility):
#   { key:       Symbol  (REQUIRED — stable id used by SurfaceSetting#visible_columns)
#     label:     String,
#     value:     ->(record) -> Object,
#     format:    Symbol (see Formatters table — defaults to :string),
#     align:     :left | :right | :center (default :left),
#     hideable:  Boolean (default true — false locks the column always-visible) }
```

### 4.3 Detail spec

```ruby
Member::Surface::Detail = Struct.new(
  :title,         # ->(record) -> String
  :subtitle,      # ->(record) -> String — optional
  :meta,          # ->(record) -> { label:, tone: } — optional badge in the header
  :sections,      # Array<Hash> — see section shape below
  keyword_init: true
)

# Section shape (one of two flavors):
#
#   Grid section (label / value pairs):
#     { key:    Symbol (REQUIRED — stable id used by SurfaceSetting#visible_sections),
#       title:  String   (optional),
#       when:   ->(record) -> Boolean (optional; defaults true),
#       rows:   [
#         { key:    Symbol (REQUIRED — stable id used by SurfaceSetting#visible_detail_rows),
#           label:  String,
#           value:  ->(r) {...},
#           format: :money,
#           span:   1|2,
#           when:   ->(r) {...} (optional),
#           hideable: Boolean (default true) },
#         ...
#       ]
#     }
#
#   List section (line items, e.g. refunds, assignments):
#     { key:    Symbol (REQUIRED),
#       title:  String,
#       when:   ->(record) -> Boolean (optional),
#       hideable: Boolean (default true),
#       list:   ->(record) -> [ { left:, right:, format: } ] }
```

### 4.4 Format vocabulary

`Member::Formatters` is a single module with one method per format key. The kit calls `Member::Formatters.format(value, key)` (returning an html-safe string).

| Format key       | Renders as                                                                |
|------------------|---------------------------------------------------------------------------|
| `:string`        | `h(value)`                                                                |
| `:date`          | `l(value, format: :long)`                                                 |
| `:datetime`      | `l(value, format: :long)`                                                 |
| `:money`         | `number_to_currency((value || 0) / 100.0)` — input is integer cents       |
| `:money_large`   | money, wrapped in `<span class="text-3xl font-semibold font-mono">`       |
| `:number`        | plain integer/decimal                                                     |
| `:number_large`  | number, wrapped in `<span class="text-3xl font-semibold">`                |
| `:status_pill`   | `<span class="badge badge-<tone>">value</span>` — tone via `STATUS_TONES` |
| `:mono`          | `<span class="font-mono break-all">value</span>`                          |

`STATUS_TONES` is a small map (`succeeded`/`active`/`paid` → `:success`, `failed`/`refused`/`cancelled` → `:danger`, `pending`/`processing` → `:warning`, else `:default`).

### 4.5 Worked example — Payments descriptor

The descriptor's `key:` is the URL slug, kept as `:payments` to preserve today's user-facing URL `/:cid/member/payments`. The module-toggle key (`FeatureModules::Module.enabled?(key: ...)`) is independent — `Member::Navigation` already uses `"payments"` for it; we keep that as-is.

```ruby
# app/services/feature_modules/payment/member_surface.rb
module FeatureModules::Payment
  MemberSurface = Member::Surface.new(
    key:   :payments,
    label: "Payments",
    icon:  :credit_card,
    default_position: 30,
    enabled_for: ->(user) {
      FeatureModules::Module.enabled?(key: "payments", customer_id: user.customer_id)
    },
    index: Member::Surface::Index.new(
      title:    "Payments",
      subtitle: "A history of payments tied to your account.",
      scope:    ->(user) {
        Payments::Payment
          .where(user_id: user.id, customer_id: user.customer_id)
          .order(created_at: :desc)
      },
      columns: [
        { key: :date,     label: "Date",   value: ->(r) { r.created_at }, format: :date },
        { key: :vendor,   label: "Vendor", value: ->(r) { r.provider.titleize } },
        { key: :amount,   label: "Amount", value: ->(r) { r.amount_cents }, format: :money, align: :right, hideable: false },
        { key: :status,   label: "Status", value: ->(r) { r.status }, format: :status_pill }
      ],
      empty_state: {
        headline: "No payments yet",
        body:     "Your payment history will appear here.",
        icon:     :credit_card
      },
      per_page: 20
    ),
    detail: Member::Surface::Detail.new(
      title:    ->(r) { "Payment #{r.out_trade_no}" },
      subtitle: ->(r) { "Created #{I18n.l(r.created_at, format: :long)}" },
      meta:     ->(r) { { label: r.status, tone: r.status == "succeeded" ? :success : :default } },
      sections: [
        {
          key: :primary,
          rows: [
            { key: :amount,      label: "Amount",  value: ->(r) { r.amount_cents }, format: :money_large, hideable: false },
            { key: :vendor,      label: "Vendor",  value: ->(r) { r.provider.titleize } },
            { key: :flow,        label: "Flow",    value: ->(r) { r.flow.upcase } },
            { key: :paid_at,     label: "Paid at", value: ->(r) { r.paid_at }, format: :datetime,
              when: ->(r) { r.paid_at } },
            { key: :psp_txn_id,  label: "PSP transaction id", value: ->(r) { r.psp_transaction_id },
              format: :mono, span: 2, when: ->(r) { r.psp_transaction_id.present? } }
          ]
        },
        {
          key:   :refunds,
          title: "Refunds",
          when:  ->(r) { r.payment_refunds.any? },
          list:  ->(r) {
            r.payment_refunds.map { |x|
              { left: I18n.l(x.created_at, format: :long), right: x.amount_cents, format: :money }
            }
          }
        }
      ]
    )
  )
end
```

This file completely replaces `Member::PaymentsController` and the two `app/views/member/payments/*.erb` files.

### 4.6 Worked example — Course scores (illustrative, not built)

```ruby
# app/services/feature_modules/courses/member_surface.rb
module FeatureModules::Courses
  MemberSurface = Member::Surface.new(
    key:   :courses,
    label: "My courses",
    icon:  :academic_cap,
    default_position: 40,
    enabled_for: ->(user) {
      FeatureModules::Module.enabled?(key: "courses", customer_id: user.customer_id)
    },
    index: Member::Surface::Index.new(
      title:    "My courses",
      subtitle: "Your enrolled courses and grades.",
      scope:    ->(user) {
        Courses::Enrollment
          .where(user_id: user.id, customer_id: user.customer_id)
          .includes(:course)
          .order(created_at: :desc)
      },
      columns: [
        { key: :course, label: "Course", value: ->(e) { e.course.title }, hideable: false },
        { key: :term,   label: "Term",   value: ->(e) { e.course.term } },
        { key: :score,  label: "Score",  value: ->(e) { e.score }, format: :number, align: :right },
        { key: :status, label: "Status", value: ->(e) { e.status }, format: :status_pill }
      ],
      empty_state: {
        headline: "No enrollments yet",
        body:     "Courses you enroll in will appear here.",
        icon:     :academic_cap
      },
      per_page: 20
    ),
    detail: Member::Surface::Detail.new(
      title:    ->(e) { e.course.title },
      subtitle: ->(e) { e.course.term },
      meta:     ->(e) { { label: e.status.titleize, tone: e.passed? ? :success : :warning } },
      sections: [
        { key: :grade,
          rows: [
            { key: :score,        label: "Score",        value: ->(e) { e.score }, format: :number_large, hideable: false },
            { key: :letter,       label: "Letter grade", value: ->(e) { e.letter_grade } },
            { key: :instructor,   label: "Instructor",   value: ->(e) { e.course.instructor_name } },
            { key: :completed_at, label: "Completed at", value: ->(e) { e.completed_at }, format: :datetime,
              when: ->(e) { e.completed_at } }
        ]},
        { key:   :assignments,
          title: "Assignments",
          when:  ->(e) { e.assignments.any? },
          list:  ->(e) { e.assignments.map { |a| { left: a.title, right: a.score, format: :number } } } }
      ]
    )
  )
end
```

A tenant who calls these "Grades" instead of "My courses", hides the term column, and reorders so this lives above Payments does so entirely through `/:cid/admin/settings/member` — no descriptor change.

## 5. Effective surface (overlay layer)

### 5.1 The wrapping object

```ruby
class Member::EffectiveSurface
  def initialize(descriptor:, settings:)
    @descriptor = descriptor
    @settings   = settings  # Member::SurfaceSetting or NullSurfaceSetting
  end

  def key      = @descriptor.key
  def label    = @settings.label_or(@descriptor.label)
  def icon     = @settings.icon_or(@descriptor.icon)
  def position = @settings.position_or(@descriptor.default_position)
  def enabled? = @settings.enabled?

  def enabled_for?(user)
    enabled? && @descriptor.enabled_for?(user)
  end

  def index  = @effective_index  ||= EffectiveIndex.new(descriptor.index, settings)
  def detail = @effective_detail ||= EffectiveDetail.new(descriptor.detail, settings)

  attr_reader :descriptor, :settings
end
```

`EffectiveIndex` exposes the same interface as the descriptor's `Surface::Index`:

```ruby
class Member::EffectiveSurface::EffectiveIndex
  def title       = @descriptor.title
  def subtitle    = @settings.subtitle_or(@descriptor.subtitle)
  def scope       = @descriptor.scope          # never overridable — security-critical
  def empty_state = @descriptor.empty_state
  def per_page    = @settings.per_page_or(@descriptor.per_page || 20)

  def columns
    visible = @settings.visible_column_keys # nil => all
    @descriptor.columns.select { |c|
      c[:hideable] == false || visible.nil? || visible.include?(c[:key])
    }
  end
end
```

`EffectiveDetail` does the same for `sections` and per-section `rows` against `visible_section_keys` and `visible_detail_row_keys`. Sections / rows with `hideable: false` are always retained.

### 5.2 Null settings

```ruby
class Member::NullSurfaceSetting
  def enabled?                        = true
  def label_or(default)               = default
  def icon_or(default)                = default
  def subtitle_or(default)            = default
  def position_or(default)            = default
  def per_page_or(default)            = default
  def visible_column_keys             = nil
  def visible_detail_row_keys         = nil
  def visible_section_keys            = nil
end
```

Used when no settings row exists yet for `(customer_id, surface_key)` — system fails open with descriptor defaults.

### 5.3 Surfaces registry — customer-aware fetch

```ruby
module Member::Surfaces
  def self.for(customer:)
    descriptors      = all_descriptors                                # discovered descriptors
    settings_by_key  = SurfaceSetting.where(customer_id: customer.id).index_by { |s| s.surface_key.to_sym }

    descriptors.map do |d|
      EffectiveSurface.new(
        descriptor: d,
        settings:   settings_by_key.fetch(d.key) { NullSurfaceSetting.new }
      )
    end.sort_by(&:position)
  end

  def self.fetch(key, customer:)
    found = self.for(customer: customer).find { |s| s.key == key.to_sym }
    raise ActiveRecord::RecordNotFound, "no member surface for #{key.inspect}" if found.nil?
    found
  end
end
```

`Member::Surfaces.all_descriptors` is the unscoped list (used by the admin settings page so the admin sees a row per descriptor regardless of customer).

## 6. Storage — `Member::SurfaceSetting`

### 6.1 Table

```ruby
create_table :member_surface_settings do |t|
  t.references :customer, null: false, foreign_key: true, type: :bigint
  t.string  :surface_key,  null: false      # e.g. "payments"
  t.boolean :enabled,      null: false, default: true
  t.integer :position,     null: false, default: 0
  t.json    :config,       null: false, default: {}
  t.timestamps
end

add_index :member_surface_settings, %i[customer_id surface_key], unique: true
```

Typed columns chosen because they're the two hottest read paths (visibility and sort order); everything else (label / icon / subtitle / per_page / visible_column_keys / visible_detail_row_keys / visible_section_keys) lives in the JSON `config` blob — same idiom as `Captcha::ProviderSettings#config` and `Payments::MerchantAccount#credentials`. New configurable knobs added later require no migration.

### 6.2 Model

```ruby
module Member
  class SurfaceSetting < ApplicationRecord
    include JsonSerializable

    belongs_to :customer
    json_attribute :config, default: {}

    validates :surface_key, presence: true,
                            uniqueness: { scope: :customer_id },
                            inclusion:  { in: ->(_) { Member::Surfaces.descriptor_keys.map(&:to_s) } }

    # Lazy upsert — used by the admin settings page (and any other consumer
    # that wants to be sure a row exists before writing to it).
    def self.for_customer_surface(customer_id:, surface_key:)
      find_or_create_by!(customer_id: customer_id, surface_key: surface_key.to_s)
    end

    # Overlay accessors — keep the *_or naming consistent with NullSurfaceSetting
    # so EffectiveSurface can hand the same message off to either object.
    def label_or(default);    config_value(:label).presence    || default; end
    def icon_or(default);     (config_value(:icon).presence || default).to_sym; end
    def subtitle_or(default); config_value(:subtitle).presence || default; end
    def per_page_or(default); (config_value(:per_page).to_i.positive? ? config_value(:per_page).to_i : default); end
    def position_or(default); position.zero? ? default : position; end

    def visible_column_keys
      Array(config_value(:visible_column_keys)).map(&:to_sym).presence
    end

    def visible_detail_row_keys
      Array(config_value(:visible_detail_row_keys)).map(&:to_sym).presence
    end

    def visible_section_keys
      Array(config_value(:visible_section_keys)).map(&:to_sym).presence
    end

    def write_overlay(label: nil, icon: nil, subtitle: nil, per_page: nil,
                      visible_column_keys: nil, visible_detail_row_keys: nil,
                      visible_section_keys: nil)
      next_config = config_json.dup
      next_config["label"]                    = label                 unless label.nil?
      next_config["icon"]                     = icon.to_s             unless icon.nil?
      next_config["subtitle"]                 = subtitle              unless subtitle.nil?
      next_config["per_page"]                 = per_page.to_i         unless per_page.nil?
      next_config["visible_column_keys"]      = Array(visible_column_keys).map(&:to_s)      unless visible_column_keys.nil?
      next_config["visible_detail_row_keys"]  = Array(visible_detail_row_keys).map(&:to_s)  unless visible_detail_row_keys.nil?
      next_config["visible_section_keys"]     = Array(visible_section_keys).map(&:to_s)     unless visible_section_keys.nil?
      self.config_json = next_config
    end

    private

    def config_value(key) = config_json[key.to_s]
  end
end
```

## 7. Admin settings page — `/:cid/admin/settings/member`

### 7.1 Route + controller

```ruby
# config/routes.rb (existing 2b. ADMIN settings block — appended)
namespace :settings do
  # ... existing ...
  resource :member, only: %i[show update], controller: "settings/member"
end
```

```ruby
# app/controllers/admin/settings/member_controller.rb
module Admin
  module Settings
    class MemberController < ::Admin::ApplicationController
      dashboard_menu_item :settings

      def show
        @rows = build_rows
      end

      def update
        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   params.require(:member_settings)
        )
        if result.success?
          redirect_to "/#{current_customer.id}/admin/settings/member",
                      notice: "Member surface settings updated."
        else
          @rows   = build_rows
          @errors = result.errors
          render :show, status: :unprocessable_entity
        end
      end

      private

      def build_rows
        ::Member::Surfaces.for(customer: current_customer).map { |effective|
          ::Admin::Settings::MemberRowPresenter.new(effective: effective)
        }
      end
    end
  end
end
```

### 7.2 Reform contract + Trailblazer activity

Per project convention:

```ruby
# app/concepts/member/settings/contract/update.rb
module Member::Settings::Contract
  class Update < Reform::Form
    collection :rows, populate_if_empty: ->(*) { OpenStruct.new } do
      property :surface_key
      property :enabled,        type: Reform::Form::Coercion::DRY::Types::Bool
      property :position,       type: Reform::Form::Coercion::DRY::Types::Integer
      property :label
      property :icon
      property :subtitle
      property :per_page,       type: Reform::Form::Coercion::DRY::Types::Integer
      collection :visible_column_keys
      collection :visible_detail_row_keys
      collection :visible_section_keys

      validates :surface_key, presence: true,
                              inclusion: { in: ->(_) { Member::Surfaces.descriptor_keys.map(&:to_s) } }
      validates :position,    numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
      validates :per_page,    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 200 }, allow_nil: true
    end
  end
end
```

```ruby
# app/concepts/member/settings/operation/update.rb
module Member::Settings::Operation
  class Update
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def [](k) = send(k)
    end

    def self.call(customer:, params:)
      form = Member::Settings::Contract::Update.new(OpenStruct.new(rows: []))
      return Result.new(success?: false, errors: form.errors) unless form.validate(params.to_unsafe_h)

      form.rows.each do |row|
        next if Member::Surfaces.descriptor_for(row.surface_key).nil?

        setting = Member::SurfaceSetting.for_customer_surface(
          customer_id: customer.id, surface_key: row.surface_key
        )
        setting.enabled  = row.enabled.nil? ? true : row.enabled
        setting.position = row.position || setting.position
        setting.write_overlay(
          label:                   row.label,
          icon:                    row.icon,
          subtitle:                row.subtitle,
          per_page:                row.per_page,
          visible_column_keys:     row.visible_column_keys,
          visible_detail_row_keys: row.visible_detail_row_keys,
          visible_section_keys:    row.visible_section_keys
        )
        setting.save!
      end

      Result.new(success?: true, errors: nil)
    end
  end
end
```

### 7.3 View / form layout

Single ERB at `app/views/admin/settings/member/show.html.erb` with one row per descriptor. Each row is a small form section:

```
┌──────────────────────────────────────────────────────────────────┐
│  Built-in (locked)                                                │
│    Home       — always visible to members                    │
│    Profile    — always visible to members                    │
│    Security   — always visible to members                    │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  Configurable surfaces                                            │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Payments                                                    │  │
│  │ [✓] Visible to members                                 │  │
│  │ Label    [Payments               ]                          │  │
│  │ Icon     [credit_card v]                                    │  │
│  │ Subtitle [A history of payments tied to your account.    ]  │  │
│  │ Position [30]                                               │  │
│  │ Page size [20]                                              │  │
│  │                                                             │  │
│  │ Index columns                                               │  │
│  │   [✓] Date                                                  │  │
│  │   [✓] Vendor                                                │  │
│  │   [✓] Amount  (always shown)                                │  │
│  │   [✓] Status                                                │  │
│  │                                                             │  │
│  │ Detail fields                                               │  │
│  │   [✓] Amount  (always shown)                                │  │
│  │   [✓] Vendor                                                │  │
│  │   [✓] Flow                                                  │  │
│  │   [✓] Paid at                                               │  │
│  │   [✓] PSP transaction id                                    │  │
│  │   [✓] Refunds (section)                                     │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                                                              [ Save ]
```

Submit posts to `PATCH /:cid/admin/settings/member` with the structured `member_settings[rows][...]` params consumed by the Reform collection.

A `ViewComponent` — `Admin::Settings::MemberSurfaceCardComponent` — renders one such row given a descriptor + the customer's current settings row. The page passes the array of components into `AdminPageComponent` (existing convention).

### 7.4 What is and isn't admin-controlled

| Knob                            | Source              | Notes                                                          |
|---------------------------------|---------------------|----------------------------------------------------------------|
| Visible to members         | `enabled`           | AND'd with descriptor's `enabled_for` (module-toggle gate)     |
| Label                           | `config[:label]`    | Falls back to descriptor `label`                               |
| Icon                            | `config[:icon]`     | Choice limited to a fixed set of Heroicons (UI dropdown)       |
| Subtitle                        | `config[:subtitle]` | Index page subtitle                                            |
| Navigation position             | `position`          | Lower = higher in nav. Bespoke entries are pinned (Home=0, Profile=10, Security=20) |
| Page size (per_page)            | `config[:per_page]` | 1–200; falls back to descriptor default                        |
| Visible index columns           | `config[:visible_column_keys]` | Subset of descriptor columns whose `hideable` ≠ false |
| Visible detail rows             | `config[:visible_detail_row_keys]` | Subset of descriptor rows whose `hideable` ≠ false |
| Visible detail sections         | `config[:visible_section_keys]`    | Subset of descriptor sections whose `hideable` ≠ false |

Not admin-controlled (deliberate):

- The query / scope (security-critical — descriptor defines what records this user can see).
- Column / row format (`:money`, `:date`, etc.) — a presentational concern owned by the descriptor.
- Empty state copy.
- Bespoke surfaces (Home / Profile / Security) — they're built-in, listed read-only.

## 8. Authorization contract

Unchanged from the 2026-05-15 skeleton on the member side. All three layers continue to apply: URL gate (`require_member!`), tenant gate (cross-tenant 404), ownership gate (`authorize_owned!`). The descriptor's `scope:` lambda is required to scope by `user_id` and `customer_id`. `SurfacesController#show` calls `authorize_owned!(@record)` after `find` — a belt-and-suspenders second check.

`enabled_for?` on the effective surface is the AND of (descriptor module-toggle gate) AND (admin-overlay `enabled` flag). When either is false, `SurfacesController#load_surface` raises `ActiveRecord::RecordNotFound` (404). Nav-item visibility uses the same predicate, so the surface is hidden from the nav at the same time it 404s direct-URL access.

The admin settings page at `/:cid/admin/settings/member` is an `admin/owner`-protected URL (inherits the `/admin/*` URL gate).

## 9. Refactoring existing pages

| Page         | Today                                                     | After                                                               |
|--------------|-----------------------------------------------------------|---------------------------------------------------------------------|
| Home         | hand-written; uses `HeroCardComponent` + status cards     | unchanged (deliberately bespoke)                                    |
| Profile show | hand-written `<header>` + `<dl>` block                    | `PageHeader` + one `PageSection` containing `DetailGrid`            |
| Profile edit | hand-written form                                         | `PageHeader` + one `PageSection`; form body stays bespoke           |
| Security     | hand-written `<header>` + three `<section>`s              | `PageHeader` + three `PageSection`s                                 |
| Payments     | `Member::PaymentsController` + two views             | descriptor-driven via `Member::SurfacesController`             |

Net file delta:

- **Deleted:** `app/controllers/member/payments_controller.rb`, `app/views/member/payments/index.html.erb`, `app/views/member/payments/show.html.erb`.
- **Added:** descriptor + kit components + surfaces controller + admin settings page (controller, contract, activity, view, presenter, component).
- **Modified:** `app/views/member/profiles/show.html.erb`, `app/views/member/profiles/edit.html.erb`, `app/views/member/securities/show.html.erb` (wrapped in primitives; same controllers, same routes).

`Member::Navigation` is updated to read from `Member::Surfaces.for(customer:)` for descriptor-driven entries. The bespoke entries (`:home`, `:profile`, `:security`) remain hardcoded with pinned positions (0, 10, 20).

## 10. Styling vocabulary

The member token namespace is unchanged. This spec adds no new tokens, no new component utilities, no new fonts. The kit standardizes which existing utilities to use where:

| Surface element            | Class / token                                                |
|----------------------------|--------------------------------------------------------------|
| Page background            | `bg-canvas` (set by shell — pages do not override)           |
| Card                       | `card-member-elevated`                                  |
| Primary CTA                | `btn-member`                                            |
| Secondary CTA              | `btn btn-ghost`                                              |
| Destructive CTA            | `btn btn-ghost text-danger`                                  |
| Page H1                    | `text-title`                                                 |
| Card H2                    | `text-heading`                                               |
| Section header (above list)| `section-header`                                             |
| Body copy                  | `text-body` / `text-body-sm`                                 |
| Label (`<dt>`)             | `text-label`                                                 |
| Status badge               | `badge badge-{success\|warning\|danger\|default}`            |
| Mono / id                  | `font-mono` (+ `break-all` for long ids)                     |

The admin settings page uses the existing admin design system (`admin-page`, `card`, `form-label`, `input-field`, `btn btn-primary` etc.) — not the member tokens.

## 11. Testing

Unit:

- `spec/services/member/surface_spec.rb` — descriptor validation; key/label/columns; rejects column without `key:`.
- `spec/services/member/surfaces_spec.rb` — registry + `for(customer:)` + `fetch(key, customer:)` + descriptor-only fallback when no settings row exists.
- `spec/services/member/effective_surface_spec.rb` — overlay merge: descriptor-only, settings-only override, hideable-false guard, default fallbacks.
- `spec/services/member/formatters_spec.rb` — every advertised format key.
- `spec/services/member/page_filters_spec.rb` — pagination `[records, page_meta]` shape.
- `spec/models/member/surface_setting_spec.rb` — JSON config round-trip; `for_customer_surface` upsert; `write_overlay` partial updates.
- `spec/concepts/member/settings/operation/update_spec.rb` — happy path saves N rows; bad surface_key rejected; per_page bounds.

Component:

- `page_header_component_spec`, `page_section_component_spec`, `index_table_component_spec`, `detail_grid_component_spec`, `empty_state_component_spec`, `pagination_component_spec`.
- `surface_index_component_spec`, `surface_detail_component_spec` (using a stub `EffectiveSurface`).
- `admin/settings/member_surface_card_component_spec.rb` — renders one descriptor row's form section.

Request / system:

- `spec/requests/member/surfaces_spec.rb` — drives index + show with descriptor + settings overlay (visibility off → 404; visible_column_keys narrows; per_page override applies).
- `spec/requests/admin/settings/member_spec.rb` — admin GET shows form pre-populated; PATCH persists rows; non-admin → redirect.
- `spec/system/admin/settings/member_spec.rb` — Capybara: rename Payments to "Donations", uncheck a column, save, then visit member payments — sees "Donations" in nav, table is missing the column.
- `spec/system/member/payments_spec.rb` — kept; URL-level + visual contract.
- `spec/system/member/surface_kit_spec.rb` — stub descriptor + every advertised format key.

Stale-test policy applies: where a request or system spec fails because the markup intentionally moved into a primitive component, the spec is rewritten — not the production code reverted.

## 12. Implementation phases

The implementation plan (produced separately by `writing-plans`) breaks this into five phases, each independently mergeable:

1. **Primitives** — `PageHeader`, `PageSection`, `IndexTable`, `DetailGrid`, `EmptyState`, `Pagination`, plus `Formatters` and `PageFilters`.
2. **Refactor bespoke pages** — Profile show, Profile edit, Security wrapped in primitives.
3. **Surface descriptor + overlay layer** — `Member::Surface`, `Member::SurfaceSetting` model + migration, `Member::EffectiveSurface`, `Member::Surfaces` registry with `for(customer:)`. Verified by service / model specs only.
4. **Composers + Payments migration** — `SurfaceIndexComponent`, `SurfaceDetailComponent`, `Member::SurfacesController`, route block update, the Payments descriptor file, deletion of the old payments controller/views/specs, navigation update.
5. **Admin settings page** — `/:cid/admin/settings/member` controller, Reform contract, Trailblazer activity, view, presenter, ViewComponent. Verified by request + system specs.
6. **Kit smoke spec** — stub-descriptor end-to-end. Locks in the kit's external contract.

## 13. Risks and open questions

- **Filters / sort.** Deliberately deferred. The `Surface::Index` shape leaves room (`filters:`, `sort:`) but the kit ignores them today.
- **Pagination strategy.** Keep `LIMIT/OFFSET`. If a future surface needs cursor pagination, `paginate` becomes a strategy lookup.
- **Module-disabled UX.** Direct URL access while the module is disabled returns 404 (not redirect). Same for admin-disabled overlay.
- **Reflection-based registry timing.** `Member::Surfaces.all_descriptors` enumerates `FeatureModules::*::MemberSurface` lazily on first call.
- **i18n.** Strings in descriptors are plain strings; the admin overlay stores user-entered strings too. If/when i18n is adopted project-wide, descriptors switch to `I18n.t(...)` and the overlay continues to store the customer's literal override (which wins).
- **Naming collision with admin's `EmptyStateComponent`.** Member variant lives in the `Member::` namespace.
- **Bespoke entries in the settings page.** Listed read-only. We do *not* let the admin reorder Profile / Security relative to descriptor surfaces (avoids an extra typed field on every row). Pinned positions: Home=0, Profile=10, Security=20; descriptor surfaces occupy 30+.
- **`hideable: false` ergonomics.** Descriptor authors must remember to mark security-critical or "user expects this to always be visible" columns as `hideable: false`. Default is `true`.
- **Schema-vs-config split.** Visibility (`enabled`) and ordering (`position`) are typed columns because every settings read needs them; everything else is JSON. If a future feature needs to query against (say) `per_page`, we promote it. Don't do it speculatively.
- **What about the admin page itself being multi-tenant?** It's at `/:cid/admin/settings/member`. The controller scopes `SurfaceSetting.where(customer_id: current_customer.id)`. The platform owner viewing customer X's admin sees X's settings, not their own.

## 14. Acceptance criteria

The kit is considered done when:

1. `Member::Surface`, `Member::Surfaces`, `Member::EffectiveSurface`, `Member::SurfaceSetting`, and `Member::Formatters` exist with full unit coverage.
2. All page-kit components have component specs.
3. The Payments descriptor at `app/services/feature_modules/payment/member_surface.rb` drives `/:cid/member/payments` and `/:cid/member/payments/:id`. The old `Member::PaymentsController` and its views and request spec are deleted.
4. Profile show, Profile edit, and Security pages are recomposed through `PageHeader` + `PageSection` (and `DetailGrid` where applicable). Their controllers and routes are unchanged.
5. The member navigation derives descriptor-driven entries from `Member::Surfaces.for(customer:)` — bespoke entries hardcoded.
6. `/:cid/admin/settings/member` lists every descriptor (plus locked bespoke entries), supports save, and the saved overlay is visible on the next member visit.
7. `surface_kit_spec.rb` registers a stub descriptor with all advertised formats and renders successfully.
8. All new and existing member + admin specs pass.
9. A reader handed only the Course-scores descriptor in §4.6 can paste it into a new module folder, restart the server, and:
   - See `/:cid/member/courses` index and detail render with descriptor defaults.
   - Visit `/:cid/admin/settings/member` as a customer admin and find a freshly-listed "Courses" row, configurable as described in §7.
