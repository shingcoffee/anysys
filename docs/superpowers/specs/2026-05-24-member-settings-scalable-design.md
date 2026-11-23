# Member Admin Settings — Scalable Source-Driven Architecture — Design

**Date:** 2026-05-24
**Status:** Draft for review
**Builds on:** [`2026-05-23-member-page-kit-design.md`](2026-05-23-member-page-kit-design.md) (descriptor + overlay layer)

**Scope:** Restructure `/:cid/admin/settings/member` so it scales as the number of member surfaces grows. Today the page renders every descriptor as one tall card on a single route; the hardcoded "Built-in" card sits next to it; only `FeatureModules::*` is a discovery target. After this work, surfaces flow from a pluggable `SurfaceSource` contributor (parallel to `SettingsContributor` / `SidebarContributor`), the admin URL splits into a hub → per-source → per-surface drill-down, and an `Entities` source ships alongside the existing `Modules` source so each customer Entity contributes a member surface automatically.

---

## 1. Background and motivation

The 2026-05-23 spec landed a descriptor-driven member page kit and a per-tenant overlay layer. It got two things right that this spec preserves:

1. The descriptor → overlay → effective-surface pipeline is the only consumer-facing surface contract. `Navigation`, `SurfacesController`, and the kit components don't need to know where descriptors come from.
2. Storage is shaped for evolution (`SurfaceSetting#config` JSON blob, no migration when a new knob is added).

What it got partially right but didn't generalize:

1. **Discovery is single-purpose.** `Member::Surfaces.ensure_discovered!` only enumerates `FeatureModules::Module.all` and looks for `FeatureModules::<X>::MemberSurface`. A tenant that defines a custom Entity (e.g. "Course") cannot expose it as a member surface without a code change. This is the single biggest scalability ceiling.
2. **The admin page collapses every descriptor onto one route.** With today's two configurable surfaces it works; with five modules + N entities it becomes one giant scrolling form with one giant Save button. The bespoke entries (Home / Profile / Security) are hardcoded into a separate `MemberBespokeCardComponent` rather than being just another source of surfaces — special-casing that has to be duplicated every time we add a new "kind" of surface.

The motivating example: a customer admin lands on `/:cid/admin/settings/member`, sees three cards — **Built-in** (locked: Home, Profile, Security), **Modules** (3 surfaces: Payments, Donations, …), **Entities** (12 surfaces: Courses, Events, …) — clicks a card to drill into the source's surfaces, clicks one surface to edit its overlay. Adding a thirteenth entity makes a thirteenth row appear on the Entities page; nothing else changes.

## 2. Goals and non-goals

**Goals**

1. Surfaces flow into `Member::Surfaces` from one or more pluggable `SurfaceSource` contributors. Adding a new kind of source (modules, entities, future X) means adding one file under `app/services/member/sources/`.
2. The admin settings UI scales linearly with two factors (number of sources × surfaces per source) without scrolling-fatigue: hub lists sources, per-source page lists surfaces, per-surface page edits one overlay.
3. Existing member member-facing behavior is untouched: `Navigation`, `SurfacesController`, `Surface{Index,Detail}Component`, the descriptor shape, the `SurfaceSetting` model's overlay accessors, and `EffectiveSurface`'s public surface remain wire-compatible.
4. The `Builtin` source replaces the special-cased `MemberBespokeCardComponent`. Bespoke entries become regular descriptors that happen to live in a `editable? = false` source.
5. An `Entities` source ships in this spec, generating one descriptor per `Entity` row owned by the customer. The mapping from entity field schema to surface columns lives in a single `EntitySurfaceBuilder` service.
6. Migration of today's two existing tenant rows (created by the prior spec for Payments) is automatic — they get back-filled with `source_key = "modules"` and continue to round-trip through the new UI.

**Non-goals**

- **Authoring new descriptors via the admin UI.** Code-defined descriptors plus tenant overlay remain the only model. Entities are an exception only because each Entity row already encodes the schema we need; the admin doesn't write the Entity from this page.
- **Cross-source operations.** Bulk enable/disable across sources, search across surfaces, copy-an-overlay-from-customer-X — all out of scope.
- **Renaming Built-in surfaces.** Home / Profile / Security are listed but not editable.
- **Sidebar children.** The settings sidebar keeps a single "Member" entry pointing at the hub. We don't grow the sidebar by source × surface — drill-down lives in-page.
- **Filters / sort UI on the member side.** Same as the prior spec — deferred.

## 3. Architecture

### 3.1 Three-layer split

```
┌─────────────────────────────────────────────────────────────────┐
│  PRODUCERS                                                       │
│  ──────────                                                      │
│  Member::SurfaceSource  ← pluggable contributor             │
│    .key            (e.g. :builtin, :modules, :entities)          │
│    .name           (e.g. "Built-in", "Modules", "Entities")      │
│    .description    (one-liner for the hub card)                  │
│    .editable?      (false locks bespoke surfaces read-only)      │
│    .position       (display order on the hub)                    │
│    #surfaces       → Array<Member::Surface> for one customer│
│    #surface_for(key:) → Member::Surface | nil               │
│                                                                  │
│  Concrete sources (ship in this spec):                           │
│    Member::Sources::Builtin    — Home / Profile / Security  │
│    Member::Sources::Modules    — FeatureModules::*::MemberSurface │
│    Member::Sources::Entities   — one descriptor per Entity row │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  REGISTRY                                                        │
│  ────────                                                        │
│  Member::Surfaces  ← unchanged member-facing API            │
│    .for(customer:)        → Array<EffectiveSurface>  (existing)  │
│    .fetch(key, customer:) → EffectiveSurface         (existing)  │
│    .sources                                          (NEW)       │
│    .source_for(key)                                  (NEW)       │
│    .surfaces_in(source_key:, customer:)              (NEW)       │
│    .all_descriptors        DEPRECATED → use sources              │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  STORAGE  (existing + 1 new column)                              │
│  ────────                                                        │
│  Member::SurfaceSetting  (customer_id, surface_key,         │
│                                source_key NEW,                   │
│                                enabled, position, config JSON)   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Surface key namespacing

Surface keys are globally unique across all sources, so the existing storage and `EffectiveSurface` plumbing don't change. Sources prefix their keys to guarantee uniqueness:

| Source     | Key shape                          | Examples                                              |
|------------|------------------------------------|-------------------------------------------------------|
| Built-in   | `builtin_<entry>`                  | `builtin_home`, `builtin_profile`, `builtin_security` |
| Modules    | (descriptor's own key — no prefix) | `payments`                                            |
| Entities   | `entity_<entity_key>`              | `entity_courses`, `entity_events`                     |

`Modules` does **not** prefix because today's existing data uses the bare key (`payments`) and we don't want to migrate. New source kinds added after this spec MUST prefix.

### 3.3 What `Member::Navigation` consumes

Unchanged: `Member::Surfaces.for(customer:)` returns a flat `Array<EffectiveSurface>` sorted by `position`. The `BESPOKE_ITEMS` constant in `Member::Navigation` is **deleted** because Home / Profile / Security now arrive as ordinary effective surfaces from the `Builtin` source. The nav builder's `path:` lambda takes the effective surface and uses `descriptor.respond_to?(:path_seg) ? "/#{customer.id}/member/#{descriptor.path_seg}".chomp("/") : "/#{customer.id}/member/#{effective.key}"` — descriptor surfaces hit the kit URL pattern, built-in adapters expose the `path_seg` they were built with.

**Breaking nav key change.** Today `Navigation::Item#key` is one of `:home`, `:profile`, `:security`, or a descriptor key. After this work the built-in keys become `:builtin_home`, `:builtin_profile`, `:builtin_security`. Anything that asserted on the literal symbol (top-nav component spec, system specs) is rewritten under the stale-test policy. There are no production callers that switch on these symbols outside the navigation file itself.

## 4. The `SurfaceSource` contract

### 4.1 Base class

```ruby
# app/services/member/surface_source.rb
module Member
  class SurfaceSource
    # ---- subclass interface (class methods) ----
    def self.key             ; raise NotImplementedError ; end
    def self.name            ; raise NotImplementedError ; end
    def self.description     ; "" ; end
    def self.editable?       ; true ; end
    def self.position        ; 100 ; end

    def self.register!
      Member::Surfaces::SourceRegistry.register(self)
    end

    # ---- instance interface ----
    def initialize(customer:) ; @customer = customer ; end
    attr_reader :customer

    def surfaces             ; raise NotImplementedError ; end   # → [Member::Surface]
    def surface_for(key:)    ; surfaces.find { |s| s.key == key.to_sym } ; end
  end
end
```

### 4.2 Source registry

The previous `Surfaces.ensure_discovered!` is replaced with explicit registration. Each source class calls `register!` at the end of its file (same idiom as `Payments::Gateways::Base#register!` and `Captcha::Providers::Base#register!`).

```ruby
# app/services/member/surfaces/source_registry.rb
module Member
  module Surfaces
    module SourceRegistry
      class << self
        def register(klass)
          @sources ||= {}
          @sources[klass.key.to_sym] = klass
        end

        def all
          @sources ||= {}
          @sources.values.sort_by(&:position)
        end

        def find(key)
          (@sources || {})[key.to_sym]
        end

        def reset!
          @sources = {}
        end
      end
    end
  end
end
```

The three concrete source files are loaded eagerly at boot via Rails autoloading + an initializer that requires them once (`config/initializers/member_surface_sources.rb`). Tests use `SourceRegistry.reset!` + `register!` to substitute fakes, mirroring how `Member::Surfaces.reset!` is used today.

### 4.3 `Member::Sources::Builtin`

```ruby
# app/services/member/sources/builtin.rb
module Member
  module Sources
    class Builtin < Member::SurfaceSource
      def self.key         ; :builtin ; end
      def self.name        ; "Built-in" ; end
      def self.description ; "Always-visible member pages." ; end
      def self.editable?   ; false ; end
      def self.position    ; 0 ; end

      ENTRIES = [
        { key: :builtin_home,     label: "Home",     icon: :home,         path_seg: "",         default_position:  0 },
        { key: :builtin_profile,  label: "Profile",  icon: :user,         path_seg: "profile",  default_position: 10 },
        { key: :builtin_security, label: "Security", icon: :shield_check, path_seg: "security", default_position: 20 }
      ].freeze

      def surfaces
        ENTRIES.map { |e| BuiltinSurface.new(**e) }
      end

      register!
    end
  end
end
```

`BuiltinSurface` is a tiny adapter that quacks like `Member::Surface` (responds to `key`, `label`, `icon`, `default_position`, `enabled_for?`, `index`, `detail`) but raises if anyone calls `index.scope` or `detail.sections` — these surfaces are not driven by the kit; they are routed to bespoke controllers (`profiles#show`, `securities#show`). The override path in `Member::Navigation::Item` uses `path_seg` instead of the kit URL pattern. `editable? = false` on the source guarantees the admin UI never lets anyone get into a position to call those methods.

### 4.4 `Member::Sources::Modules`

```ruby
# app/services/member/sources/modules.rb
module Member
  module Sources
    class Modules < Member::SurfaceSource
      def self.key         ; :modules ; end
      def self.name        ; "Modules" ; end
      def self.description ; "Read-only surfaces shipped by feature modules." ; end
      def self.position    ; 10 ; end

      def surfaces
        FeatureModules::Module.available_for_customer(customer.id).flat_map do |fm|
          ns_name = "FeatureModules::#{fm.key.camelize}"
          ns      = ns_name.safe_constantize or next []
          surface = ns.const_defined?(:MemberSurface, false) ? ns.const_get(:MemberSurface) : nil
          next [] unless surface.is_a?(Member::Surface)

          surface.validate!
          [surface]
        end
      end

      register!
    end
  end
end
```

Behavior is identical to today's `Surfaces.ensure_discovered!`, but scoped per-customer: a tenant who hasn't enabled Payments doesn't see the Payments descriptor on their settings page. (Today, every descriptor is visible to every customer; this is a small but desirable behavior change.)

### 4.5 `Member::Sources::Entities`

```ruby
# app/services/member/sources/entities.rb
module Member
  module Sources
    class Entities < Member::SurfaceSource
      def self.key         ; :entities ; end
      def self.name        ; "Entities" ; end
      def self.description ; "Surfaces auto-generated from custom entity schemas." ; end
      def self.position    ; 20 ; end

      def surfaces
        ::Entity.where(customer_id: customer.id).map { |entity|
          Member::EntitySurfaceBuilder.call(entity: entity)
        }
      end

      register!
    end
  end
end
```

### 4.6 `Member::EntitySurfaceBuilder`

```ruby
# app/services/member/entity_surface_builder.rb
module Member
  module EntitySurfaceBuilder
    DEFAULT_POSITION_BASE = 200

    def self.call(entity:)
      schema  = entity.property_schema_json || []
      data_fields = schema.reject { |f| f["type"] == "Calculated" }

      columns = data_fields.map { |f|
        slug = f["name_slug"] || f["key"]
        {
          key:      slug.to_sym,
          label:    f["name"].presence || slug.to_s.titleize,
          value:    ->(entry) { entry.data_json[slug] },
          format:   format_for(f["type"]),
          align:    align_for(f["type"]),
          hideable: true
        }
      }
      columns = [{ key: :id, label: "ID", value: ->(e) { e.id }, hideable: false }] if columns.empty?

      Member::Surface.new(
        key:   :"entity_#{entity.name_slug}",
        label: entity.name,
        icon:  :rectangle_stack,
        default_position: DEFAULT_POSITION_BASE + entity.id.to_i,
        enabled_for: ->(user) { user.customer_id == entity.customer_id },
        index: Member::Surface::Index.new(
          title:    entity.name,
          subtitle: entity.description.presence || "Records linked to your account.",
          scope:    ->(user) {
            # Member-facing scope is intentionally empty until per-entry
            # user ownership lands (see §13). The admin still configures
            # the surface; the member sees the empty state.
            EntityEntry.none
          },
          columns: columns,
          empty_state: {
            headline: "No #{entity.name.downcase} yet",
            body:     "Records will appear here once they're linked to your account.",
            icon:     :rectangle_stack
          },
          per_page: 20
        ),
        detail: Member::Surface::Detail.new(
          title:    ->(entry) { "##{entry.id}" },
          subtitle: ->(entry) { I18n.l(entry.created_at, format: :long) },
          sections: [{
            key:   :primary,
            rows:  columns.map { |c|
              { key: c[:key], label: c[:label], value: c[:value],
                format: c[:format], hideable: c[:hideable] }
            }
          }]
        )
      ).tap(&:validate!)
    end

    def self.format_for(type)
      case type.to_s.downcase
      when "money", "currency" then :money
      when "number", "integer", "decimal" then :number
      when "datetime", "timestamp" then :datetime
      when "date"                  then :date
      else                              :string
      end
    end

    def self.align_for(type)
      %w[money currency number integer decimal].include?(type.to_s.downcase) ? :right : :left
    end
  end
end
```

**4.6.1 Entity field schema (actual shape, verified against `app/models/entity.rb`).** `Entity` exposes a JSON `property_schema` array via `property_schema_json`. Each element is a hash with at least `"name"`, `"name_slug"`, and `"type"`. Calculated fields (`type: "Calculated"`) are skipped; everything else becomes a column. Field labels come from `"name"`; field values are read from `entry.data_json[slug]`.

**4.6.2 `EntityEntry` and the user-ownership gap.** Records are persisted as `EntityEntry` rows (table: `entity_entries`, columns: `id, entity_id, customer_id, data, timestamps`). The table currently has **no `user_id` column** — entries are tenant-scoped but not user-scoped. The member kit's contract requires record-level scoping by `(user_id, customer_id)`, so the Entities source's `scope:` lambda intentionally returns `EntityEntry.none` until per-entry user ownership is added in a follow-up. The Entities source still produces a configurable descriptor (so the admin can preview / configure / hide the surface), and the member sees the empty-state — never a leaked record. Adding `user_id` to `entity_entries` is an explicit follow-up project (see §13, "Open question: per-entry ownership"); shipping this design without it is safe by construction.

### 4.7 `Member::Surfaces` — public API additions

```ruby
# app/services/member/surfaces.rb (selected diff)
module Member
  module Surfaces
    # ----- Existing public methods, internals revised -----
    def self.for(customer:)
      sources = SourceRegistry.all.map { |klass| klass.new(customer: customer) }
      descriptors = sources.flat_map { |s| s.surfaces.map { |d| [s.class.key, d] } }

      settings_by_key = SurfaceSetting.where(customer_id: customer.id)
                                      .index_by { |s| s.surface_key.to_sym }

      descriptors.map do |source_key, descriptor|
        EffectiveSurface.new(
          descriptor: descriptor,
          settings:   settings_by_key.fetch(descriptor.key) { NullSurfaceSetting.new },
          source_key: source_key
        )
      end.sort_by(&:position)
    end

    def self.fetch(key, customer:)
      found = self.for(customer: customer).find { |s| s.key == key.to_sym }
      raise ActiveRecord::RecordNotFound, "no member surface for #{key.inspect}" if found.nil?
      found
    end

    # ----- New public methods -----
    def self.sources                       ; SourceRegistry.all                      ; end
    def self.source_for(key)               ; SourceRegistry.find(key)                ; end
    def self.surfaces_in(source_key:, customer:)
      effectives = self.for(customer: customer)
      effectives.select { |e| e.source_key == source_key.to_sym }
    end

    # ----- Removed in this PR -----
    # `all_descriptors`, `descriptor_keys`, `descriptor_for`, and `register`
    # (used only by the old test helpers and the prior contract validator) are
    # removed. The contract no longer validates `surface_key` against a global
    # list — see §8 — so these helpers have no remaining callers. Tests
    # register fakes via `SourceRegistry.register(FakeSource)` +
    # `SourceRegistry.reset!`.
  end
end
```

`EffectiveSurface` gains a `source_key` reader (one line) — it's the only consumer-facing change to that class.

## 5. Storage delta

### 5.1 Migration

```ruby
class AddSourceKeyToMemberSurfaceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :member_surface_settings, :source_key, :string
    add_index  :member_surface_settings, %i[customer_id source_key]

    # Back-fill: every existing row was created by the Modules source.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE member_surface_settings
             SET source_key = 'modules'
           WHERE source_key IS NULL
        SQL
      end
    end
  end
end
```

`source_key` is denormalized — it's recoverable from the resolved descriptor — but having it on the row enables one-shot per-source counts on the hub (`SELECT source_key, COUNT(*) FROM member_surface_settings WHERE customer_id = ? GROUP BY source_key`) without instantiating every source for every page render.

### 5.2 `Member::SurfaceSetting`

Adds one accessor and one validation:

```ruby
class Member::SurfaceSetting < ApplicationRecord
  # ... existing ...
  validates :source_key, presence: true,
                         inclusion: { in: ->(_) { Member::Surfaces::SourceRegistry.all.map { |s| s.key.to_s } } }
end
```

`source_key` is set by the operation — never accepted from form input. The operation reads `effective_surface.source_key` and writes it onto the row.

## 6. Admin URL structure

### 6.1 Three routes, three controllers

```ruby
# config/routes.rb (selected diff)
namespace :settings do
  resource :member, only: %i[show update],
                         controller: "settings/members" do
    resources :sources,  only: %i[show update],
                         param:  :key,
                         controller: "settings/member_sources" do
      resources :surfaces, only: %i[show update],
                           param:  :key,
                           controller: "settings/member_surfaces"
    end
  end
end
```

| URL                                                                                        | Controller                                       | Purpose                                                              |
|--------------------------------------------------------------------------------------------|--------------------------------------------------|----------------------------------------------------------------------|
| `GET  /:cid/admin/settings/member`                                                    | `Admin::Settings::MembersController#show`   | Hub — one card per source                                            |
| `PATCH /:cid/admin/settings/member`                                                   | `Admin::Settings::MembersController#update` | Cross-source bulk save (used by inline toggles on hub)               |
| `GET  /:cid/admin/settings/member/sources/:key`                                       | `MemberSourcesController#show`              | Per-source page — compact list of surfaces                           |
| `PATCH /:cid/admin/settings/member/sources/:key`                                      | `MemberSourcesController#update`            | Per-source bulk save (used by inline toggles on the source page)     |
| `GET  /:cid/admin/settings/member/sources/:source_key/surfaces/:key`                  | `MemberSurfacesController#show`             | Per-surface deep editor                                              |
| `PATCH /:cid/admin/settings/member/sources/:source_key/surfaces/:key`                 | `MemberSurfacesController#update`           | Per-surface save                                                     |

All three controllers call into the existing `Member::Settings::Operation::Update` (it already accepts a `rows: [...]` collection — per-surface save is just a one-element rows array).

### 6.2 Authorization

Every URL above sits under `/:cid/admin/...` so the existing admin URL gate (`require_admin_or_owner!`) protects all three controllers. The operation always derives `current_customer` from the controller, never trusts a `customer_id` form field, and uses `for_customer_surface(customer_id: current_customer.id, ...)` exactly as today. Editing a Built-in surface (`source.editable? = false`) is rejected at the operation: any incoming row whose source is not editable is dropped silently. The UI never offers the form for those, but defense-in-depth covers a hand-crafted POST.

### 6.3 Settings sidebar

Unchanged in `SettingsContributor`: a single "Member" entry pointing at `/:cid/admin/settings/member`. We deliberately do not grow the sidebar by source × surface — that's what the in-page hub is for.

## 7. UI components

### 7.1 The three new ViewComponents

```
app/components/admin/settings/
  member_hub_card_component.{rb,erb}
    └─ One per source. Title, description, "X surfaces (Y enabled)",
       primary action: "Configure" (or "View" if !editable?).
       Linked to /:cid/admin/settings/member/sources/<source_key>.

  member_source_row_component.{rb,erb}
    └─ One per surface on the per-source page. Compact: icon, label,
       position number, [✓] enabled checkbox (POSTs inline with stimulus
       form-submission), [Edit] link. For !editable sources, the row
       renders read-only without a form wrapper.

  member_surface_form_component.{rb,erb}
    └─ The full editor used on the per-surface page. Same fields as
       today's MemberSurfaceCardComponent (label/icon/subtitle/
       position/per_page/empty-state copy/visible columns/sections/rows),
       but renders a single <form> POST'ing to the nested route.
       Replaces today's MemberSurfaceCardComponent.
```

### 7.2 Components that go away

- `Admin::Settings::MemberSurfaceCardComponent` — replaced by `MemberSurfaceFormComponent`. Its existing spec is rewritten (stale-test policy: production code intentionally moved).
- `Admin::Settings::MemberBespokeCardComponent` — deleted. Built-in entries now flow through the hub like any other source. Its spec is deleted with it.

### 7.3 Hub layout (`/:cid/admin/settings/member`)

```
┌───────────────────────────────────────────────────────────────────┐
│  Member surfaces                                              │
│  Choose what your members see and how it's labelled.               │
├───────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Built-in                                            🔒 LOCKED│  │
│  │ Always-visible member pages.                            │  │
│  │ 3 surfaces                                          [ View ] │  │
│  └─────────────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Modules                                                      │  │
│  │ Read-only surfaces shipped by feature modules.               │  │
│  │ 1 surface — 1 enabled                          [ Configure ] │  │
│  └─────────────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Entities                                                     │  │
│  │ Surfaces auto-generated from custom entity schemas.          │  │
│  │ 12 surfaces — 9 enabled                        [ Configure ] │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

### 7.4 Per-source layout (`.../sources/:key`)

```
┌───────────────────────────────────────────────────────────────────┐
│  ‹ Member surfaces                                            │
│  Modules                                                           │
│  Read-only surfaces shipped by feature modules.                    │
├───────────────────────────────────────────────────────────────────┤
│   #  ▾  Surface                                                    │
│  30     💳  Payments               [✓] enabled        [ Edit › ]   │
│   ─                                                                │
└───────────────────────────────────────────────────────────────────┘
```

The enabled checkbox auto-submits via a Stimulus controller (`form#requestSubmit()` on change). Position is a small read-only label; reordering happens on the per-surface deep editor.

### 7.5 Per-surface layout (`.../sources/:source_key/surfaces/:key`)

Same fields as today's giant card, scoped to one surface, with a single Save / Cancel pair at the bottom. The breadcrumb is `Member surfaces › Modules › Payments`.

## 8. Controller skeletons

```ruby
# app/controllers/admin/settings/members_controller.rb
module Admin
  module Settings
    class MembersController < ApplicationController
      dashboard_menu_item :settings

      def show
        @sources = ::Member::Surfaces.sources.map do |source_class|
          ::Admin::Settings::MemberHubCardPresenter.new(
            source_class: source_class,
            customer:     current_customer
          )
        end
      end

      def update
        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   params.fetch(:member_settings, {})
        )
        respond_after(result, redirect: "/#{current_customer.id}/admin/settings/member")
      end

      private

      def respond_after(result, redirect:)
        if result.success?
          redirect_to redirect, notice: "Member surface settings saved."
        else
          flash.now[:alert] = result.errors.full_messages.join(", ")
          render :show, status: :unprocessable_entity
        end
      end
    end
  end
end
```

```ruby
# app/controllers/admin/settings/member_sources_controller.rb
module Admin
  module Settings
    class MemberSourcesController < ApplicationController
      dashboard_menu_item :settings

      before_action :load_source

      def show
        @rows = ::Member::Surfaces.surfaces_in(
          source_key: @source.key,
          customer:   current_customer
        ).map { |effective| ::Admin::Settings::MemberRowPresenter.new(effective: effective) }
      end

      def update
        return head(:forbidden) unless @source.editable?

        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   params.fetch(:member_settings, {})
        )
        if result.success?
          redirect_to "/#{current_customer.id}/admin/settings/member/sources/#{@source.key}",
                      notice: "Saved."
        else
          @rows = build_rows
          render :show, status: :unprocessable_entity
        end
      end

      private

      def load_source
        @source = ::Member::Surfaces.source_for(params[:key]) or raise ActiveRecord::RecordNotFound
      end
    end
  end
end
```

```ruby
# app/controllers/admin/settings/member_surfaces_controller.rb
module Admin
  module Settings
    class MemberSurfacesController < ApplicationController
      dashboard_menu_item :settings

      before_action :load_surface

      def show
        @presenter = ::Admin::Settings::MemberRowPresenter.new(effective: @effective)
      end

      def update
        return head(:forbidden) unless @source.editable?

        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   params.fetch(:member_settings, {})
        )
        if result.success?
          redirect_to "/#{current_customer.id}/admin/settings/member/sources/#{@source.key}/surfaces/#{@effective.key}",
                      notice: "Surface saved."
        else
          @presenter = ::Admin::Settings::MemberRowPresenter.new(effective: @effective)
          render :show, status: :unprocessable_entity
        end
      end

      private

      def load_surface
        @source    = ::Member::Surfaces.source_for(params[:source_key]) or raise ActiveRecord::RecordNotFound
        @effective = ::Member::Surfaces.fetch(params[:key], customer: current_customer)
        raise ActiveRecord::RecordNotFound unless @effective.source_key == @source.key
      end
    end
  end
end
```

**Operation changes (`Member::Settings::Operation::Update`):**

1. The Reform contract previously validated `surface_key` against the global `Member::Surfaces.descriptor_keys` list. The new set of valid surface keys is **customer-specific** (Entities yields different surfaces for different customers), so the contract drops that `inclusion:` validator. The operation instead resolves each row's `surface_key` via `Member::Surfaces.fetch(row.surface_key, customer: customer)` and skips the row (with an error attached to `:surface_key`) if it doesn't resolve. This is the only place the (customer × surface) tuple is authoritatively known.
2. After resolving the effective surface, the operation looks up `Member::Surfaces.source_for(effective.source_key)`; if `editable? = false`, the row is silently dropped (defense in depth — the UI never offers the form for those, but a hand-crafted POST would otherwise update the row).
3. The operation writes `setting.source_key = effective.source_key.to_s` before save, so the denormalized column stays in lockstep with what the registry resolves to.

## 9. Refactoring existing pages

| Page                                                | Today                                                                                                  | After                                                                                              |
|-----------------------------------------------------|--------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| Settings sidebar entry                              | One link to `/:cid/admin/settings/member`                                                         | Unchanged                                                                                          |
| `/:cid/admin/settings/member`                  | Lists every descriptor as a tall card, plus a `BespokeCardComponent`                                   | Hub: one card per source, with counts and a drill-in CTA                                           |
| (no equivalent today)                               | —                                                                                                      | `.../sources/:key`: list of surfaces in that source                                                |
| (no equivalent today)                               | —                                                                                                      | `.../sources/:source_key/surfaces/:key`: full editor for one surface                               |
| `Member::Surfaces.ensure_discovered!`          | Walks `FeatureModules::Module.all` directly                                                            | Replaced by `Sources::Modules#surfaces` — same outcome, called via the registry                    |
| `Member::Navigation::BESPOKE_ITEMS`            | Hardcoded in the navigation file                                                                       | Deleted. `Builtin#surfaces` returns the same three entries as ordinary descriptors                 |
| `Admin::Settings::MemberBespokeCardComponent`  | Renders Built-in as a separate locked card                                                             | Deleted. Built-in is just another source on the hub                                                |
| `Admin::Settings::MemberSurfaceCardComponent`  | Renders the full editor inline on the hub                                                              | Replaced by `MemberSurfaceFormComponent`, now lives on `.../surfaces/:key`                    |

## 10. Testing

Unit:

- `spec/services/member/surface_source_spec.rb` — base class API; `register!` updates the registry; subclassing without a `key` raises.
- `spec/services/member/surfaces/source_registry_spec.rb` — registration, lookup, sort by `position`, `reset!`.
- `spec/services/member/sources/builtin_spec.rb` — yields three surfaces; `editable? = false`; surface keys match the prefix rule.
- `spec/services/member/sources/modules_spec.rb` — yields one descriptor per available module; skips modules not enabled for this customer.
- `spec/services/member/sources/entities_spec.rb` — yields one descriptor per `Entity` row owned by the customer.
- `spec/services/member/entity_surface_builder_spec.rb` — column derivation, scope filter (security boundary), empty-state copy, hideable propagation from `required`.
- `spec/services/member/surfaces_spec.rb` — `for(customer:)`, `fetch(key, customer:)`, `sources`, `source_for(key)`, `surfaces_in(source_key:, customer:)`.
- `spec/models/member/surface_setting_spec.rb` — `source_key` validation; existing overlay accessors still round-trip.
- `spec/concepts/member/settings/operation/update_spec.rb` — drops rows whose source is `editable? = false`; sets `source_key` from the resolved descriptor.

Component:

- `spec/components/admin/settings/member_hub_card_component_spec.rb` — renders source name, description, count summary, "Configure"/"View" CTA based on `editable?`.
- `spec/components/admin/settings/member_source_row_component_spec.rb` — renders enabled checkbox + Edit link; locks read-only for `!editable?`.
- `spec/components/admin/settings/member_surface_form_component_spec.rb` — full field set; locks `hideable: false` columns; emits `surface_key` hidden field.

Request:

- `spec/requests/admin/settings/members_spec.rb` — hub renders for admin; denies member; bulk PATCH round-trips.
- `spec/requests/admin/settings/member_sources_spec.rb` — per-source page renders; toggle PATCH persists; PATCH on built-in source returns 403.
- `spec/requests/admin/settings/member_surfaces_spec.rb` — per-surface deep edit round-trips; mismatched source/surface returns 404.

System:

- `spec/system/admin/settings/member_spec.rb` — full drill-down: hub → Modules → Payments → rename to "Donations" → save → member navigation reflects the override.
- `spec/system/admin/settings/member_entities_spec.rb` — create an Entity with a field schema, log in as admin, verify the Entities source card shows it, drill in and overlay it.

Stale-test policy applies: `member_bespoke_card_component_spec.rb` is deleted; `member_surface_card_component_spec.rb` is rewritten as `member_surface_form_component_spec.rb`.

## 11. Acceptance criteria

This work is done when:

1. `Member::SurfaceSource`, `Member::Surfaces::SourceRegistry`, and the three concrete sources (`Builtin`, `Modules`, `Entities`) exist with full unit coverage.
2. `Member::EntitySurfaceBuilder` produces a valid `Member::Surface` for every `Entity` row owned by the customer.
3. `Member::Surfaces.for(customer:)` and `.fetch(key, customer:)` continue to drive `Navigation` and `SurfacesController` with no member-facing behavior change.
4. `EffectiveSurface#source_key` returns the resolved descriptor's source.
5. The migration adds `source_key`, back-fills existing rows with `'modules'`, and the validation rejects rows with a `source_key` not present in the registry.
6. `/:cid/admin/settings/member` is the hub of source cards. `/:cid/admin/settings/member/sources/:key` is the per-source list. `/:cid/admin/settings/member/sources/:source_key/surfaces/:key` is the per-surface editor.
7. Built-in entries (Home / Profile / Security) appear on the hub as one locked source. Their detail page is read-only. Their navigation entries continue to render in the member top nav exactly as today.
8. PATCHing any surface in the Built-in source returns 403.
9. An admin who creates a new `Entity` row in the maintenance entity-management UI sees a corresponding row appear under the Entities source on their next visit to the member settings hub — no code change, no restart.
10. All new and existing member + admin specs pass. The deprecated `Member::Surfaces.all_descriptors` and `Member::Surfaces.register` test helpers are removed; tests instead use `SourceRegistry.register(FakeSource)` + `SourceRegistry.reset!`.

## 12. Risks and open questions

- **Entity field schema shape.** §4.6.1 assumes `entity.field_schema_or_default` returns `{ fields: [{ key:, label:, type:, required: }, …] }`. The implementation plan's first task verifies the actual `Entity` model and adds a shim if needed. If the real schema is more complex (sections, nested fields), the builder grows accordingly — but that complexity stays inside the builder; nothing else cares.
- **`EntityRecord` query performance.** With many entities × many records, the member's "list every entity surface in nav" walk could N+1 on `Entity.where(customer_id:)`. The Entities source caches its result per request (memoized on `@surfaces`). Per-page server-side pagination (`per_page` overlay) keeps record-level reads bounded.
- **Source registration ordering at boot.** Sources self-register at file load. Rails autoloading guarantees the files are loaded before the first request that needs them; an eager-load initializer (`config/initializers/member_surface_sources.rb`) requires them explicitly so `Member::Surfaces.sources` always returns the full set in production.
- **What happens if a tenant has a `SurfaceSetting` row whose `surface_key` no longer matches any descriptor?** (E.g. they had a Course entity, deleted it, and the row is orphaned.) The settings page silently ignores orphaned rows. The operation does not delete them — that's a maintenance concern, not a settings-page concern. A future cleanup task can sweep them; out of scope here.
- **Inline-toggle UX without full-page reload.** The per-source page's enabled-toggle does a normal Rails form submit (Turbo Streams not assumed). Full reload + flash. Acceptable for an admin page; we don't need optimistic UI.
- **Migration safety.** The `add_column` is a single non-blocking column add on what should be a small table (one row per customer × surface, single-digit thousands at most). The back-fill is one `UPDATE`. Safe to ship in a single migration.
- **The deprecated `all_descriptors` / `register` helpers.** Removed in this PR (no callers remain after the refactor). Tests get rewritten — stale-test policy.
