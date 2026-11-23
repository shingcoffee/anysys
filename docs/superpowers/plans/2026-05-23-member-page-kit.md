# Member Page Kit & Surface Registry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the member area into a shared page kit (PageHeader, PageSection, IndexTable, DetailGrid, EmptyState, Pagination) plus a `Member::Surface` descriptor registry, so any module exposes a tenant-visible read-only listing by dropping a single descriptor file next to the module.

**Architecture:** Two-tier components — primitives are reusable building blocks; composers (`SurfaceIndexComponent`, `SurfaceDetailComponent`) read a `Member::Surface` descriptor and render index + detail. A generic `Member::SurfacesController` resolves `params[:key]` against a registry that auto-discovers `FeatureModules::*::MemberSurface` constants. Refactor lands in 12 phases: primitives + formatters first, then refactor existing pages, then descriptor + controller + Payments migration, then a smoke spec.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, TailwindCSS, RSpec, Capybara. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-23-member-page-kit-design.md`

---

## File Structure

**Created:**

- `app/services/member/formatters.rb` — single module with one method per format key.
- `app/services/member/page_filters.rb` — pagination helper returning `[records, page_meta]`.
- `app/services/member/surface.rb` — `Member::Surface` Struct + `Index` and `Detail` nested Structs + `validate!`.
- `app/services/member/surfaces.rb` — registry. Enumerates `FeatureModules::Module.all`, looks up `FeatureModules::<Camelized>::MemberSurface`, returns / fetches them.
- `app/components/member/page_header_component.rb` + `.html.erb`
- `app/components/member/page_section_component.rb` + `.html.erb`
- `app/components/member/index_table_component.rb` + `.html.erb`
- `app/components/member/detail_grid_component.rb` + `.html.erb`
- `app/components/member/empty_state_component.rb` + `.html.erb` (member variant; admin's top-level `EmptyStateComponent` is unchanged)
- `app/components/member/pagination_component.rb` + `.html.erb`
- `app/components/member/surface_index_component.rb` + `.html.erb`
- `app/components/member/surface_detail_component.rb` + `.html.erb`
- `app/controllers/member/surfaces_controller.rb`
- `app/views/member/surfaces/index.html.erb`
- `app/views/member/surfaces/show.html.erb`
- `app/services/feature_modules/payment/member_surface.rb` — replaces `PaymentsController`.
- Specs (one per new file, listed under each task).

**Modified:**

- `app/views/member/profiles/show.html.erb` — recompose through primitives.
- `app/views/member/profiles/edit.html.erb` — wrap header + section.
- `app/views/member/securities/show.html.erb` — wrap header + sections.
- `app/services/member/navigation.rb` — `:payments` entry derives from descriptor; bespoke entries hardcoded.
- `config/routes.rb` (line ~363) — replace `resources :payments, only: %i[index show]` with `resources :surfaces, only: %i[index show], param: :id, path: ":key"`.

**Deleted:**

- `app/controllers/member/payments_controller.rb`
- `app/views/member/payments/index.html.erb`
- `app/views/member/payments/show.html.erb`
- `spec/requests/member/payments_spec.rb` — coverage subsumed by `surfaces_spec.rb`.

---

## Conventions used in every task

- TDD: write the failing spec first, run it, watch it fail, write the minimum to pass, run it, commit.
- Run a single example with `bundle exec rspec <path> -e "<example name>"` (or pass the line: `<path>:NN`).
- Run a whole file with `bundle exec rspec <path>`.
- Commit messages follow the existing style in `git log` (`feat: ...`, `refactor: ...`, `test: ...`).
- Every member component inherits from `ApplicationComponent` (existing).
- Every spec for a member component requires `rails_helper` and uses `type: :component`.
- `Member::ShellComponent` already wraps the layout — none of the new components touch the shell.

---

## Phase 1 — Formatters

### Task 1: Member::Formatters

**Files:**
- Create: `app/services/member/formatters.rb`
- Test: `spec/services/member/formatters_spec.rb`

- [ ] **Step 1: Write the failing spec**

Write `spec/services/member/formatters_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Formatters do
  describe ".format" do
    it "renders :string by escaping HTML" do
      expect(described_class.format("<b>x</b>", :string)).to eq("&lt;b&gt;x&lt;/b&gt;")
    end

    it "renders :date with the long format" do
      d = Date.new(2026, 5, 23)
      expect(described_class.format(d, :date)).to eq(I18n.l(d, format: :long))
    end

    it "renders :datetime with the long format" do
      t = Time.utc(2026, 5, 23, 10, 0)
      expect(described_class.format(t, :datetime)).to eq(I18n.l(t, format: :long))
    end

    it "renders :money from integer cents" do
      expect(described_class.format(1234, :money)).to include("$12.34")
    end

    it "renders :money_large with hero classes" do
      out = described_class.format(1234, :money_large)
      expect(out).to include("text-3xl")
      expect(out).to include("font-mono")
      expect(out).to include("$12.34")
    end

    it "renders :number as the value" do
      expect(described_class.format(42, :number)).to eq("42")
    end

    it "renders :number_large with hero classes" do
      out = described_class.format(42, :number_large)
      expect(out).to include("text-3xl")
      expect(out).to include("42")
    end

    it "renders :status_pill with a tone class" do
      out = described_class.format("succeeded", :status_pill)
      expect(out).to include("badge-success")
      expect(out).to include("succeeded")
    end

    it "renders :status_pill default tone for unknown values" do
      out = described_class.format("weird", :status_pill)
      expect(out).to include("badge-default")
    end

    it "renders :mono with font-mono and break-all" do
      out = described_class.format("ABC123", :mono)
      expect(out).to include("font-mono")
      expect(out).to include("break-all")
      expect(out).to include("ABC123")
    end

    it "renders nil values as an empty string" do
      expect(described_class.format(nil, :string)).to eq("")
    end

    it "raises on unknown format keys" do
      expect { described_class.format("x", :unknown) }.to raise_error(ArgumentError, /unknown format/)
    end

    it "returns html_safe strings for HTML formats" do
      expect(described_class.format(1234, :money_large)).to be_html_safe
      expect(described_class.format("succeeded", :status_pill)).to be_html_safe
      expect(described_class.format("ABC", :mono)).to be_html_safe
    end
  end
end
```

- [ ] **Step 2: Run spec, confirm failure**

```
bundle exec rspec spec/services/member/formatters_spec.rb
```
Expected: red — `uninitialized constant Member::Formatters`.

- [ ] **Step 3: Write the implementation**

Create `app/services/member/formatters.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Single module mapping descriptor format keys to rendered strings.
  # The kit calls Member::Formatters.format(value, key); descriptors
  # never write Tailwind classes for known data shapes.
  module Formatters
    extend ActionView::Helpers::NumberHelper
    extend ActionView::Helpers::OutputSafetyHelper

    STATUS_TONES = {
      "succeeded" => :success, "active"  => :success, "paid"     => :success,
      "failed"    => :danger,  "refused" => :danger,  "cancelled" => :danger,
      "pending"   => :warning, "processing" => :warning
    }.freeze

    KNOWN = %i[string date datetime money money_large number number_large status_pill mono].freeze

    def self.format(value, key)
      return "" if value.nil?

      case key
      when :string        then ERB::Util.html_escape(value.to_s)
      when :date          then I18n.l(value, format: :long)
      when :datetime      then I18n.l(value, format: :long)
      when :money         then number_to_currency((value.to_i) / 100.0)
      when :money_large
        raw(%(<span class="text-3xl font-semibold font-mono">#{number_to_currency((value.to_i) / 100.0)}</span>))
      when :number        then value.to_s
      when :number_large
        raw(%(<span class="text-3xl font-semibold">#{ERB::Util.html_escape(value.to_s)}</span>))
      when :status_pill
        tone = STATUS_TONES.fetch(value.to_s, :default)
        raw(%(<span class="badge badge-#{tone}">#{ERB::Util.html_escape(value.to_s)}</span>))
      when :mono
        raw(%(<span class="font-mono break-all">#{ERB::Util.html_escape(value.to_s)}</span>))
      else
        raise ArgumentError, "unknown format key: #{key.inspect} (known: #{KNOWN.inspect})"
      end
    end
  end
end
```

- [ ] **Step 4: Run spec, confirm green**

```
bundle exec rspec spec/services/member/formatters_spec.rb
```
Expected: all green (12 examples).

- [ ] **Step 5: Commit**

```
git add app/services/member/formatters.rb spec/services/member/formatters_spec.rb
git commit -m "feat(member): add Formatters module for descriptor format keys"
```

---

## Phase 2 — Page filters / pagination helper

### Task 2: Member::PageFilters

**Files:**
- Create: `app/services/member/page_filters.rb`
- Test: `spec/services/member/page_filters_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PageFilters do
  describe ".paginate" do
    let(:customer) { create(:customer) }
    let(:user)     { create(:user, :member, customer: customer) }

    let!(:payments) do
      30.times.map do |i|
        order = Payments::Order.create!(
          customer_id:  customer.id,
          external_ref: "T-#{i}",
          subject:      "S",
          amount_cents: 100 + i,
          currency:     "CNY",
          status:       "pending"
        )
        Payments::Payment.create!(
          customer_id:      customer.id,
          user_id:          user.id,
          payment_order_id: order.id,
          provider:         "alipay",
          flow:             "qr",
          out_trade_no:     "X-#{i}",
          amount_cents:     100 + i,
          status:           "succeeded"
        )
      end
    end

    let(:scope) { Payments::Payment.where(user_id: user.id, customer_id: customer.id).order(:id) }

    it "returns the first page by default" do
      records, meta = described_class.paginate(scope, page: nil, per_page: 20)
      expect(records.size).to eq(20)
      expect(meta.page).to eq(1)
      expect(meta.per_page).to eq(20)
      expect(meta.total_count).to eq(30)
    end

    it "returns the requested page" do
      records, meta = described_class.paginate(scope, page: 2, per_page: 20)
      expect(records.size).to eq(10)
      expect(meta.page).to eq(2)
    end

    it "clamps page to 1 when given garbage" do
      _records, meta = described_class.paginate(scope, page: "abc", per_page: 20)
      expect(meta.page).to eq(1)
    end

    it "clamps page to 1 when given a number less than 1" do
      _records, meta = described_class.paginate(scope, page: -3, per_page: 20)
      expect(meta.page).to eq(1)
    end

    it "exposes total_pages" do
      _records, meta = described_class.paginate(scope, page: 1, per_page: 20)
      expect(meta.total_pages).to eq(2)
    end
  end
end
```

- [ ] **Step 2: Run spec, confirm failure**

```
bundle exec rspec spec/services/member/page_filters_spec.rb
```
Expected: red — constant missing.

- [ ] **Step 3: Implement**

Create `app/services/member/page_filters.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Pagination helper. Returns [records, meta] where meta exposes the
  # four fields PaginationComponent needs.
  module PageFilters
    Meta = Struct.new(:page, :per_page, :total_count, keyword_init: true) do
      def total_pages
        return 1 if total_count.zero?
        (total_count.to_f / per_page).ceil
      end
    end

    def self.paginate(scope, page:, per_page:)
      page_int = [page.to_i, 1].max
      total    = scope.count
      records  = scope.limit(per_page).offset((page_int - 1) * per_page).to_a
      [records, Meta.new(page: page_int, per_page: per_page, total_count: total)]
    end
  end
end
```

- [ ] **Step 4: Run spec, confirm green**

```
bundle exec rspec spec/services/member/page_filters_spec.rb
```
Expected: all green.

- [ ] **Step 5: Commit**

```
git add app/services/member/page_filters.rb spec/services/member/page_filters_spec.rb
git commit -m "feat(member): add PageFilters pagination helper"
```

---

## Phase 3 — Surface descriptor + registry

### Task 3: Member::Surface struct + nested Index/Detail + validate!

**Files:**
- Create: `app/services/member/surface.rb`
- Test: `spec/services/member/surface_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Surface do
  def valid_index
    Member::Surface::Index.new(
      title:    "Things",
      subtitle: "All your things",
      scope:    ->(_user) { [] },
      columns:  [
        { label: "Name",   value: ->(r) { r.name } },
        { label: "Amount", value: ->(r) { r.amount }, format: :money, align: :right }
      ],
      empty_state: { headline: "Nothing yet", body: "It will show up", icon: :sparkles },
      per_page: 20
    )
  end

  def valid_detail
    Member::Surface::Detail.new(
      title:    ->(r) { r.name },
      subtitle: ->(_r) { "subtitle" },
      meta:     ->(_r) { { label: "ok", tone: :success } },
      sections: [
        { rows: [{ label: "Name", value: ->(r) { r.name } }] }
      ]
    )
  end

  def valid_surface
    described_class.new(
      key:         :things,
      label:       "Things",
      icon:        :sparkles,
      enabled_for: ->(_user) { true },
      index:       valid_index,
      detail:      valid_detail
    )
  end

  describe "#validate!" do
    it "passes for a fully populated surface" do
      expect { valid_surface.validate! }.not_to raise_error
    end

    it "rejects a key with uppercase letters" do
      surface = valid_surface
      surface.key = :Things
      expect { surface.validate! }.to raise_error(ArgumentError, /key/)
    end

    it "rejects a key starting with a digit" do
      surface = valid_surface
      surface.key = :"1thing"
      expect { surface.validate! }.to raise_error(ArgumentError, /key/)
    end

    it "rejects a blank label" do
      surface = valid_surface
      surface.label = ""
      expect { surface.validate! }.to raise_error(ArgumentError, /label/)
    end

    it "rejects when index is not an Index" do
      surface = valid_surface
      surface.index = nil
      expect { surface.validate! }.to raise_error(ArgumentError, /index/)
    end

    it "rejects when detail is not a Detail" do
      surface = valid_surface
      surface.detail = nil
      expect { surface.validate! }.to raise_error(ArgumentError, /detail/)
    end

    it "rejects an Index without columns" do
      bad = valid_surface
      bad.index = Member::Surface::Index.new(
        title: "T", scope: ->(_u) { [] }, columns: [],
        empty_state: { headline: "x", body: "y", icon: :z }, per_page: 10
      )
      expect { bad.validate! }.to raise_error(ArgumentError, /columns/)
    end

    it "rejects a column missing :label" do
      bad = valid_surface
      bad.index = Member::Surface::Index.new(
        title: "T", scope: ->(_u) { [] },
        columns: [{ value: ->(r) { r } }],
        empty_state: { headline: "x", body: "y", icon: :z }, per_page: 10
      )
      expect { bad.validate! }.to raise_error(ArgumentError, /column.*label/)
    end

    it "rejects a column missing :value" do
      bad = valid_surface
      bad.index = Member::Surface::Index.new(
        title: "T", scope: ->(_u) { [] },
        columns: [{ label: "X" }],
        empty_state: { headline: "x", body: "y", icon: :z }, per_page: 10
      )
      expect { bad.validate! }.to raise_error(ArgumentError, /column.*value/)
    end
  end

  describe "#enabled_for?" do
    it "delegates to the lambda" do
      surface = valid_surface
      surface.enabled_for = ->(_u) { false }
      expect(surface.enabled_for?(double)).to be(false)
    end
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/services/member/surface_spec.rb
```
Expected: red.

- [ ] **Step 3: Implement**

Create `app/services/member/surface.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Descriptor for a read-only member surface (index + detail).
  # Modules ship one of these as FeatureModules::<Name>::MemberSurface.
  Surface = Struct.new(:key, :label, :icon, :enabled_for, :index, :detail, keyword_init: true) do
    KEY_RE = /\A[a-z][a-z0-9_]*\z/.freeze

    Index = Struct.new(:title, :subtitle, :scope, :columns, :empty_state, :per_page,
                       keyword_init: true) do
      def per_page_or_default
        per_page.presence || 20
      end
    end

    Detail = Struct.new(:title, :subtitle, :meta, :sections, keyword_init: true)

    def enabled_for?(user) = enabled_for.call(user)

    def validate!
      raise ArgumentError, "key must be a lowercase identifier (got: #{key.inspect})" unless key.to_s.match?(KEY_RE)
      raise ArgumentError, "label is required"  if label.to_s.strip.empty?
      raise ArgumentError, "index must be a Member::Surface::Index"  unless index.is_a?(Index)
      raise ArgumentError, "detail must be a Member::Surface::Detail" unless detail.is_a?(Detail)

      validate_index!(index)
      true
    end

    private

    def validate_index!(idx)
      raise ArgumentError, "index.columns must be a non-empty array" if Array(idx.columns).empty?

      idx.columns.each_with_index do |col, i|
        raise ArgumentError, "index.column[#{i}] missing :label" if col[:label].to_s.empty?
        raise ArgumentError, "index.column[#{i}] missing :value (must be a callable)" unless col[:value].respond_to?(:call)
      end
    end
  end
end
```

- [ ] **Step 4: Run, confirm green**

```
bundle exec rspec spec/services/member/surface_spec.rb
```
Expected: all green.

- [ ] **Step 5: Commit**

```
git add app/services/member/surface.rb spec/services/member/surface_spec.rb
git commit -m "feat(member): add Surface descriptor with validate!"
```

---

### Task 4: Member::Surfaces registry

**Files:**
- Create: `app/services/member/surfaces.rb`
- Test: `spec/services/member/surfaces_spec.rb`

The registry enumerates registered modules from `FeatureModules::Module.all` and looks up `FeatureModules::<Camelized>::MemberSurface` for each. Modules without a descriptor are skipped silently — they simply don't expose a member surface.

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Surfaces do
  let(:test_surface) do
    Member::Surface.new(
      key:   :test_widget,
      label: "Widgets",
      icon:  :sparkles,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Widgets", scope: ->(_u) { [] },
        columns: [{ label: "X", value: ->(r) { r } }],
        empty_state: { headline: "x", body: "y", icon: :z },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title: ->(_r) { "T" }, sections: [{ rows: [{ label: "X", value: ->(_r) { "v" } }] }]
      )
    )
  end

  before { described_class.register(test_surface) }
  after  { described_class.reset! }

  describe ".register" do
    it "validates the surface on register" do
      bad = test_surface.dup
      bad.label = ""
      expect { described_class.register(bad) }.to raise_error(ArgumentError, /label/)
    end
  end

  describe ".all" do
    it "includes registered surfaces" do
      expect(described_class.all.map(&:key)).to include(:test_widget)
    end
  end

  describe ".fetch" do
    it "returns the surface for a known key (string)" do
      expect(described_class.fetch("test_widget").key).to eq(:test_widget)
    end

    it "returns the surface for a known key (symbol)" do
      expect(described_class.fetch(:test_widget).key).to eq(:test_widget)
    end

    it "raises ActiveRecord::RecordNotFound on unknown keys" do
      expect { described_class.fetch(:nope) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/services/member/surfaces_spec.rb
```
Expected: red — constant missing.

- [ ] **Step 3: Implement**

Create `app/services/member/surfaces.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Registry of member surface descriptors. Auto-discovers descriptors
  # at first call by looking for FeatureModules::<Name>::MemberSurface
  # constants on every registered FeatureModules::Module record.
  #
  # Tests can call .register(surface) to add a stub descriptor, and .reset!
  # to clear discovered + registered state.
  module Surfaces
    class << self
      def register(surface)
        surface.validate!
        registry[surface.key.to_sym] = surface
      end

      def all
        ensure_discovered!
        registry.values
      end

      def fetch(key)
        ensure_discovered!
        registry.fetch(key.to_sym) { raise ActiveRecord::RecordNotFound, "no member surface for #{key.inspect}" }
      end

      def reset!
        @registry   = {}
        @discovered = false
      end

      private

      def registry
        @registry ||= {}
      end

      def ensure_discovered!
        return if @discovered

        @discovered = true
        FeatureModules::Module.all.find_each do |fm|
          ns_name = "FeatureModules::#{fm.key.camelize}"
          ns      = ns_name.safe_constantize or next
          surface = ns.const_defined?(:MemberSurface, false) ? ns.const_get(:MemberSurface) : nil
          next unless surface.is_a?(Member::Surface)

          surface.validate!
          registry[surface.key.to_sym] ||= surface
        end
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
        # During boot before migrations have run.
        @discovered = false
      end
    end
  end
end
```

- [ ] **Step 4: Run, confirm green**

```
bundle exec rspec spec/services/member/surfaces_spec.rb
```
Expected: all green (5 examples).

- [ ] **Step 5: Commit**

```
git add app/services/member/surfaces.rb spec/services/member/surfaces_spec.rb
git commit -m "feat(member): add Surfaces registry with auto-discovery"
```

---

## Phase 4 — Page header primitive

### Task 5: PageHeaderComponent

**Files:**
- Create: `app/components/member/page_header_component.rb`
- Create: `app/components/member/page_header_component.html.erb`
- Test: `spec/components/member/page_header_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PageHeaderComponent, type: :component do
  it "renders a title and subtitle" do
    render_inline(described_class.new(title: "Payments", subtitle: "Your account history"))
    expect(page).to have_css("h1.text-title", text: "Payments")
    expect(page).to have_css("p.text-body-sm", text: "Your account history")
  end

  it "renders an eyebrow link when given a hash" do
    render_inline(described_class.new(
      title:   "Payment ABC",
      eyebrow: { label: "← Back to payments", path: "/12345678/member/payments" }
    ))
    expect(page).to have_link("← Back to payments", href: "/12345678/member/payments")
  end

  it "renders a meta badge with the requested tone" do
    render_inline(described_class.new(title: "X", meta: { label: "succeeded", tone: :success }))
    expect(page).to have_css("span.badge.badge-success", text: "succeeded")
  end

  it "renders action links with the right variant class" do
    render_inline(described_class.new(
      title:   "X",
      actions: [
        { label: "Edit",   path: "/edit",   variant: :primary },
        { label: "Cancel", path: "/cancel", variant: :ghost }
      ]
    ))
    expect(page).to have_link("Edit", href: "/edit")
    expect(page.find_link("Edit")[:class]).to include("btn-member")
    expect(page.find_link("Cancel")[:class]).to include("btn-ghost")
  end

  it "omits subtitle, eyebrow, meta, and actions when not given" do
    render_inline(described_class.new(title: "Just a title"))
    expect(page).to have_css("h1", text: "Just a title")
    expect(page).not_to have_css("p.text-body-sm")
    expect(page).not_to have_css("span.badge")
    expect(page).not_to have_css("a")
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/components/member/page_header_component_spec.rb
```
Expected: red.

- [ ] **Step 3: Implement the component class**

Create `app/components/member/page_header_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Top-of-page header: optional eyebrow / breadcrumb, title, subtitle,
  # optional right-aligned meta badge, optional action links.
  class PageHeaderComponent < ApplicationComponent
    def initialize(title:, subtitle: nil, eyebrow: nil, meta: nil, actions: [])
      @title    = title
      @subtitle = subtitle
      @eyebrow  = eyebrow
      @meta     = meta
      @actions  = Array(actions)
    end

    attr_reader :title, :subtitle, :eyebrow, :meta, :actions

    def variant_class(variant)
      case variant
      when :primary then "btn-member"
      when :danger  then "btn btn-ghost text-danger"
      else               "btn btn-ghost"
      end
    end
  end
end
```

- [ ] **Step 4: Implement the template**

Create `app/components/member/page_header_component.html.erb`:

```erb
<header class="mb-8">
  <% if eyebrow.present? %>
    <p class="mb-2 text-sm">
      <%= link_to eyebrow[:label], eyebrow[:path], class: "text-member-accent-text hover:underline font-medium" %>
    </p>
  <% end %>

  <div class="flex items-end justify-between flex-wrap gap-4">
    <div>
      <h1 class="text-title"><%= title %></h1>
      <% if subtitle.present? %>
        <p class="text-body-sm"><%= subtitle %></p>
      <% end %>
    </div>

    <div class="flex items-center gap-3 flex-wrap">
      <% if meta.present? %>
        <span class="badge badge-<%= meta[:tone] || :default %>"><%= meta[:label] %></span>
      <% end %>

      <% actions.each do |action| %>
        <%= link_to action[:label], action[:path], class: variant_class(action[:variant]) %>
      <% end %>
    </div>
  </div>
</header>
```

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/components/member/page_header_component_spec.rb
```
Expected: all green (5 examples).

- [ ] **Step 6: Commit**

```
git add app/components/member/page_header_component.rb \
        app/components/member/page_header_component.html.erb \
        spec/components/member/page_header_component_spec.rb
git commit -m "feat(member): add PageHeaderComponent primitive"
```

---

### Task 6: PageSectionComponent

**Files:**
- Create: `app/components/member/page_section_component.rb`
- Create: `app/components/member/page_section_component.html.erb`
- Test: `spec/components/member/page_section_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PageSectionComponent, type: :component do
  it "wraps content in a card-member-elevated section" do
    render_inline(described_class.new) { "<p>body</p>".html_safe }
    expect(page).to have_css("section.card-member-elevated p", text: "body")
  end

  it "renders an optional title and description above the body" do
    render_inline(described_class.new(title: "Refunds", description: "Money back")) { "x" }
    expect(page).to have_css("h2.text-heading", text: "Refunds")
    expect(page).to have_css("p.text-body-sm", text: "Money back")
  end

  it "supports density: :flush for tables (no inner padding wrapper)" do
    render_inline(described_class.new(density: :flush)) { "<table></table>".html_safe }
    section = page.find("section.card-member-elevated")
    expect(section[:class]).to include("p-0")
    expect(section[:class]).to include("overflow-hidden")
  end

  it "supports density: :compact" do
    render_inline(described_class.new(density: :compact)) { "x" }
    expect(page).to have_css("section.card-member-elevated.p-4")
  end

  it "raises on unknown density" do
    expect {
      render_inline(described_class.new(density: :wat)) { "x" }
    }.to raise_error(ArgumentError, /density/)
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/components/member/page_section_component_spec.rb
```
Expected: red.

- [ ] **Step 3: Implement the component class**

Create `app/components/member/page_section_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # card-member-elevated wrapper with an optional title/description
  # header. density :default keeps the card's intrinsic padding,
  # :compact tightens it (p-4), :flush removes it entirely (used by tables).
  class PageSectionComponent < ApplicationComponent
    DENSITY_CLASSES = {
      default: "",
      compact: "p-4",
      flush:   "p-0 overflow-hidden"
    }.freeze

    def initialize(title: nil, description: nil, density: :default)
      unless DENSITY_CLASSES.key?(density)
        raise ArgumentError, "unknown density: #{density.inspect} (expected #{DENSITY_CLASSES.keys.inspect})"
      end

      @title       = title
      @description = description
      @density     = density
    end

    attr_reader :title, :description, :density

    def section_classes
      ["card-member-elevated", DENSITY_CLASSES.fetch(density)].reject(&:empty?).join(" ")
    end
  end
end
```

- [ ] **Step 4: Implement the template**

Create `app/components/member/page_section_component.html.erb`:

```erb
<section class="<%= section_classes %>">
  <% if title.present? %>
    <header class="mb-3">
      <h2 class="text-heading"><%= title %></h2>
      <% if description.present? %>
        <p class="text-body-sm"><%= description %></p>
      <% end %>
    </header>
  <% end %>

  <%= content %>
</section>
```

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/components/member/page_section_component_spec.rb
```
Expected: 5 green.

- [ ] **Step 6: Commit**

```
git add app/components/member/page_section_component.rb \
        app/components/member/page_section_component.html.erb \
        spec/components/member/page_section_component_spec.rb
git commit -m "feat(member): add PageSectionComponent primitive"
```

---

## Phase 5 — Tabular primitives

### Task 7: IndexTableComponent

**Files:**
- Create: `app/components/member/index_table_component.rb`
- Create: `app/components/member/index_table_component.html.erb`
- Test: `spec/components/member/index_table_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::IndexTableComponent, type: :component do
  Row = Struct.new(:id, :name, :amount_cents, :status, keyword_init: true)

  let(:records) do
    [
      Row.new(id: 1, name: "Alpha", amount_cents: 1000, status: "succeeded"),
      Row.new(id: 2, name: "Beta",  amount_cents: 2050, status: "pending")
    ]
  end

  let(:columns) do
    [
      { label: "Name",   value: ->(r) { r.name } },
      { label: "Amount", value: ->(r) { r.amount_cents }, format: :money, align: :right },
      { label: "Status", value: ->(r) { r.status }, format: :status_pill }
    ]
  end

  let(:row_path) { ->(r) { "/things/#{r.id}" } }

  it "renders a header for each column" do
    render_inline(described_class.new(records: records, columns: columns, row_path: row_path))
    %w[Name Amount Status].each { |h| expect(page).to have_css("th", text: h) }
  end

  it "renders one body row per record" do
    render_inline(described_class.new(records: records, columns: columns, row_path: row_path))
    expect(page).to have_css("tbody tr", count: 2)
    expect(page).to have_css("td", text: "Alpha")
    expect(page).to have_css("td", text: "Beta")
  end

  it "applies right alignment to columns with align: :right" do
    render_inline(described_class.new(records: records, columns: columns, row_path: row_path))
    amount_cells = page.all("td").select { |c| c.text.match?(/\$\d/) }
    expect(amount_cells).not_to be_empty
    amount_cells.each { |c| expect(c[:class]).to include("text-right") }
  end

  it "renders status_pill format as a badge" do
    render_inline(described_class.new(records: records, columns: columns, row_path: row_path))
    expect(page).to have_css("span.badge.badge-success", text: "succeeded")
    expect(page).to have_css("span.badge.badge-warning", text: "pending")
  end

  it "renders a trailing 'View' link per row to row_path.call(record)" do
    render_inline(described_class.new(records: records, columns: columns, row_path: row_path))
    expect(page).to have_link("View →", href: "/things/1")
    expect(page).to have_link("View →", href: "/things/2")
  end

  it "uses the configured row_label for the trailing link" do
    render_inline(described_class.new(records: records, columns: columns, row_path: row_path, row_label: "Open"))
    expect(page).to have_link("Open →", href: "/things/1")
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/components/member/index_table_component_spec.rb
```
Expected: red.

- [ ] **Step 3: Implement**

Create `app/components/member/index_table_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Read-only table for index pages. Columns are descriptor hashes:
  #   { label:, value: ->(r) {...}, format: :symbol, align: :left|:right|:center }
  class IndexTableComponent < ApplicationComponent
    def initialize(records:, columns:, row_path:, row_label: "View")
      @records   = records
      @columns   = columns
      @row_path  = row_path
      @row_label = row_label
    end

    attr_reader :records, :columns, :row_path, :row_label

    def header_class(col)
      ["px-5 py-3", alignment_class(col)].join(" ").strip
    end

    def cell_class(col)
      ["px-5 py-3 text-body-sm", alignment_class(col)].join(" ").strip
    end

    def render_value(record, col)
      value = col[:value].call(record)
      Member::Formatters.format(value, col[:format] || :string)
    end

    def alignment_class(col)
      case col[:align]
      when :right  then "text-right"
      when :center then "text-center"
      else              "text-left"
      end
    end
  end
end
```

- [ ] **Step 4: Implement the template**

Create `app/components/member/index_table_component.html.erb`:

```erb
<table class="min-w-full divide-y divide-border-subtle">
  <thead class="table-header">
    <tr>
      <% columns.each do |col| %>
        <th class="<%= header_class(col) %>"><%= col[:label] %></th>
      <% end %>
      <th class="px-5 py-3"></th>
    </tr>
  </thead>

  <tbody class="divide-y divide-border-subtle">
    <% records.each do |record| %>
      <tr class="table-row">
        <% columns.each do |col| %>
          <td class="<%= cell_class(col) %>"><%= render_value(record, col) %></td>
        <% end %>
        <td class="px-5 py-3 text-right">
          <%= link_to "#{row_label} →", row_path.call(record),
                class: "text-sm font-medium text-member-accent-text hover:underline" %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/components/member/index_table_component_spec.rb
```
Expected: 6 green.

- [ ] **Step 6: Commit**

```
git add app/components/member/index_table_component.rb \
        app/components/member/index_table_component.html.erb \
        spec/components/member/index_table_component_spec.rb
git commit -m "feat(member): add IndexTableComponent primitive"
```

---

### Task 8: DetailGridComponent

**Files:**
- Create: `app/components/member/detail_grid_component.rb`
- Create: `app/components/member/detail_grid_component.html.erb`
- Test: `spec/components/member/detail_grid_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::DetailGridComponent, type: :component do
  let(:record) { Struct.new(:name, :amount_cents, :paid_at).new("Alpha", 1234, nil) }

  it "renders a <dl> grid with two columns by default" do
    render_inline(described_class.new(rows: [
      { label: "Name",   value: ->(r) { r.name } },
      { label: "Amount", value: ->(r) { r.amount_cents }, format: :money }
    ], record: record))

    expect(page).to have_css("dl.grid")
    expect(page).to have_css("dt", text: "Name")
    expect(page).to have_css("dd", text: "Alpha")
    expect(page).to have_css("dd", text: "$12.34")
  end

  it "skips rows with a falsy when:" do
    render_inline(described_class.new(rows: [
      { label: "Name",     value: ->(r) { r.name } },
      { label: "Paid at",  value: ->(r) { r.paid_at }, format: :datetime, when: ->(r) { r.paid_at } }
    ], record: record))

    expect(page).to have_css("dt", text: "Name")
    expect(page).not_to have_css("dt", text: "Paid at")
  end

  it "applies sm:col-span-2 when span: 2" do
    render_inline(described_class.new(rows: [
      { label: "Notes", value: ->(r) { "long text" }, span: 2 }
    ], record: record))
    expect(page.find("dt", text: "Notes").find(:xpath, "..")[:class]).to include("sm:col-span-2")
  end

  it "renders :money_large with the hero classes" do
    render_inline(described_class.new(rows: [
      { label: "Amount", value: ->(r) { r.amount_cents }, format: :money_large }
    ], record: record))
    expect(page).to have_css("span.text-3xl.font-mono", text: "$12.34")
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/components/member/detail_grid_component_spec.rb
```
Expected: red.

- [ ] **Step 3: Implement**

Create `app/components/member/detail_grid_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # 2-column <dl> grid for detail pages. Row shape:
  #   { label:, value: ->(r) {...}, format: :symbol, span: 1|2, when: ->(r) {...} }
  class DetailGridComponent < ApplicationComponent
    def initialize(rows:, record:)
      @rows   = rows
      @record = record
    end

    attr_reader :rows, :record

    def visible_rows
      rows.reject { |r| r[:when] && !r[:when].call(record) }
    end

    def cell_class(row)
      row[:span] == 2 ? "sm:col-span-2" : ""
    end

    def render_value(row)
      value = row[:value].call(record)
      Member::Formatters.format(value, row[:format] || :string)
    end
  end
end
```

- [ ] **Step 4: Implement the template**

Create `app/components/member/detail_grid_component.html.erb`:

```erb
<dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-6">
  <% visible_rows.each do |row| %>
    <div class="<%= cell_class(row) %>">
      <dt class="text-label"><%= row[:label] %></dt>
      <dd class="text-body mt-1"><%= render_value(row) %></dd>
    </div>
  <% end %>
</dl>
```

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/components/member/detail_grid_component_spec.rb
```
Expected: 4 green.

- [ ] **Step 6: Commit**

```
git add app/components/member/detail_grid_component.rb \
        app/components/member/detail_grid_component.html.erb \
        spec/components/member/detail_grid_component_spec.rb
git commit -m "feat(member): add DetailGridComponent primitive"
```

---

### Task 9: Member::EmptyStateComponent

The admin namespace already has a top-level `EmptyStateComponent`. This is a separate namespaced component used by the member kit.

**Files:**
- Create: `app/components/member/empty_state_component.rb`
- Create: `app/components/member/empty_state_component.html.erb`
- Test: `spec/components/member/empty_state_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::EmptyStateComponent, type: :component do
  it "renders headline, body, and an icon container" do
    render_inline(described_class.new(headline: "No payments yet", body: "Will appear here.", icon: :credit_card))
    expect(page).to have_css("h2.text-heading", text: "No payments yet")
    expect(page).to have_text("Will appear here.")
    expect(page).to have_css("[data-icon='credit_card']")
  end

  it "wraps in a centered card-member-elevated container" do
    render_inline(described_class.new(headline: "X", body: "y", icon: :sparkles))
    expect(page).to have_css("section.card-member-elevated.text-center")
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/components/member/empty_state_component_spec.rb
```
Expected: red.

- [ ] **Step 3: Implement**

Create `app/components/member/empty_state_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  class EmptyStateComponent < ApplicationComponent
    def initialize(headline:, body:, icon:)
      @headline = headline
      @body     = body
      @icon     = icon
    end

    attr_reader :headline, :body, :icon
  end
end
```

- [ ] **Step 4: Implement the template**

Create `app/components/member/empty_state_component.html.erb`:

```erb
<section class="card-member-elevated text-center py-14">
  <span data-icon="<%= icon %>"
        class="inline-flex h-12 w-12 items-center justify-center rounded-full bg-member-accent-subtle text-member-accent-text mb-3">
    <svg class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round"
            d="M12 4v16m8-8H4"/>
    </svg>
  </span>
  <h2 class="text-heading mb-1"><%= headline %></h2>
  <p class="text-body-sm"><%= body %></p>
</section>
```

(The icon glyph is generic for the skeleton — acceptable, since the `icon:` symbol is already exposed via `data-icon` for tests and styling can swap glyphs later.)

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/components/member/empty_state_component_spec.rb
```
Expected: 2 green.

- [ ] **Step 6: Commit**

```
git add app/components/member/empty_state_component.rb \
        app/components/member/empty_state_component.html.erb \
        spec/components/member/empty_state_component_spec.rb
git commit -m "feat(member): add EmptyStateComponent primitive"
```

---

### Task 10: PaginationComponent

**Files:**
- Create: `app/components/member/pagination_component.rb`
- Create: `app/components/member/pagination_component.html.erb`
- Test: `spec/components/member/pagination_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PaginationComponent, type: :component do
  it "renders nothing when total_count fits on one page" do
    render_inline(described_class.new(page: 1, per_page: 20, total_count: 5, base_path: "/x"))
    expect(page.native.to_html).not_to include("Previous")
    expect(page.native.to_html).not_to include("Next")
  end

  it "renders Showing X-Y of Z and a Next link on page 1" do
    render_inline(described_class.new(page: 1, per_page: 20, total_count: 50, base_path: "/x"))
    expect(page).to have_text("Showing 1–20 of 50")
    expect(page).to have_link("Next →", href: "/x?page=2")
    expect(page.native.to_html).not_to include("Previous")
  end

  it "renders Previous on the last page" do
    render_inline(described_class.new(page: 3, per_page: 20, total_count: 50, base_path: "/x"))
    expect(page).to have_text("Showing 41–50 of 50")
    expect(page).to have_link("← Previous", href: "/x?page=2")
    expect(page.native.to_html).not_to include("Next")
  end

  it "preserves an existing query string on the base path" do
    render_inline(described_class.new(page: 1, per_page: 20, total_count: 50, base_path: "/x?foo=bar"))
    expect(page).to have_link("Next →", href: "/x?foo=bar&page=2")
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/components/member/pagination_component_spec.rb
```
Expected: red.

- [ ] **Step 3: Implement**

Create `app/components/member/pagination_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  class PaginationComponent < ApplicationComponent
    def initialize(page:, per_page:, total_count:, base_path:)
      @page        = page
      @per_page    = per_page
      @total_count = total_count
      @base_path   = base_path
    end

    attr_reader :page, :per_page, :total_count, :base_path

    def render?
      total_count > per_page
    end

    def from
      ((page - 1) * per_page) + 1
    end

    def to
      [page * per_page, total_count].min
    end

    def previous_path
      page_path(page - 1)
    end

    def next_path
      page_path(page + 1)
    end

    def show_previous?
      page > 1
    end

    def show_next?
      page * per_page < total_count
    end

    private

    def page_path(target_page)
      separator = base_path.include?("?") ? "&" : "?"
      "#{base_path}#{separator}page=#{target_page}"
    end
  end
end
```

- [ ] **Step 4: Implement the template**

Create `app/components/member/pagination_component.html.erb`:

```erb
<nav class="mt-5 flex items-center justify-between text-sm text-text-secondary">
  <span>Showing <%= from %>–<%= to %> of <%= total_count %></span>
  <div class="flex items-center gap-2">
    <% if show_previous? %>
      <%= link_to "← Previous", previous_path, class: "btn btn-ghost" %>
    <% end %>
    <% if show_next? %>
      <%= link_to "Next →", next_path, class: "btn btn-ghost" %>
    <% end %>
  </div>
</nav>
```

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/components/member/pagination_component_spec.rb
```
Expected: 4 green.

- [ ] **Step 6: Commit**

```
git add app/components/member/pagination_component.rb \
        app/components/member/pagination_component.html.erb \
        spec/components/member/pagination_component_spec.rb
git commit -m "feat(member): add PaginationComponent primitive"
```

---

## Phase 6 — Composers (Surface index/detail)

### Task 11: SurfaceIndexComponent

**Files:**
- Create: `app/components/member/surface_index_component.rb`
- Create: `app/components/member/surface_index_component.html.erb`
- Test: `spec/components/member/surface_index_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SurfaceIndexComponent, type: :component do
  Row = Struct.new(:id, :name, keyword_init: true)

  let(:surface) do
    Member::Surface.new(
      key: :widgets, label: "Widgets", icon: :sparkles,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Widgets",
        subtitle: "All widgets",
        scope: ->(_u) { [] },
        columns: [{ label: "Name", value: ->(r) { r.name } }],
        empty_state: { headline: "Nothing here", body: "Yet.", icon: :sparkles },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title: ->(r) { r.name },
        sections: [{ rows: [{ label: "Name", value: ->(r) { r.name } }] }]
      )
    )
  end

  let(:customer) { create(:customer) }

  it "renders the empty state when records are empty" do
    meta = Member::PageFilters::Meta.new(page: 1, per_page: 20, total_count: 0)
    render_inline(described_class.new(surface: surface, records: [], page_meta: meta, customer: customer))

    expect(page).to have_css("h1.text-title", text: "Widgets")
    expect(page).to have_css("h2.text-heading", text: "Nothing here")
    expect(page).not_to have_css("table")
  end

  it "renders the table when records exist" do
    rows = [Row.new(id: 1, name: "Alpha"), Row.new(id: 2, name: "Beta")]
    meta = Member::PageFilters::Meta.new(page: 1, per_page: 20, total_count: 2)
    render_inline(described_class.new(surface: surface, records: rows, page_meta: meta, customer: customer))

    expect(page).to have_css("table tbody tr", count: 2)
    expect(page).to have_link("View →", href: "/#{customer.id}/member/widgets/1")
    expect(page).to have_link("View →", href: "/#{customer.id}/member/widgets/2")
  end

  it "renders pagination when total exceeds per_page" do
    rows = (1..20).map { |i| Row.new(id: i, name: "R#{i}") }
    meta = Member::PageFilters::Meta.new(page: 1, per_page: 20, total_count: 30)
    render_inline(described_class.new(surface: surface, records: rows, page_meta: meta, customer: customer))

    expect(page).to have_link("Next →")
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/components/member/surface_index_component_spec.rb
```
Expected: red.

- [ ] **Step 3: Implement**

Create `app/components/member/surface_index_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # High-level composer: renders a surface's index page.
  class SurfaceIndexComponent < ApplicationComponent
    def initialize(surface:, records:, page_meta:, customer:)
      @surface   = surface
      @records   = records
      @page_meta = page_meta
      @customer  = customer
    end

    attr_reader :surface, :records, :page_meta, :customer

    def base_path
      "/#{customer.id}/member/#{surface.key}"
    end

    def row_path
      ->(record) { "/#{customer.id}/member/#{surface.key}/#{record.id}" }
    end
  end
end
```

- [ ] **Step 4: Implement the template**

Create `app/components/member/surface_index_component.html.erb`:

```erb
<%= render Member::PageHeaderComponent.new(
      title:    surface.index.title,
      subtitle: surface.index.subtitle,
      meta:     (page_meta.total_count.positive? ? { label: "#{page_meta.total_count} total", tone: :default } : nil)
    ) %>

<% if records.empty? %>
  <%= render Member::EmptyStateComponent.new(**surface.index.empty_state) %>
<% else %>
  <%= render Member::PageSectionComponent.new(density: :flush) do %>
    <%= render Member::IndexTableComponent.new(
          records:  records,
          columns:  surface.index.columns,
          row_path: row_path
        ) %>
  <% end %>

  <%= render Member::PaginationComponent.new(
        page:        page_meta.page,
        per_page:    page_meta.per_page,
        total_count: page_meta.total_count,
        base_path:   base_path
      ) %>
<% end %>
```

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/components/member/surface_index_component_spec.rb
```
Expected: 3 green.

- [ ] **Step 6: Commit**

```
git add app/components/member/surface_index_component.rb \
        app/components/member/surface_index_component.html.erb \
        spec/components/member/surface_index_component_spec.rb
git commit -m "feat(member): add SurfaceIndexComponent composer"
```

---

### Task 12: SurfaceDetailComponent

**Files:**
- Create: `app/components/member/surface_detail_component.rb`
- Create: `app/components/member/surface_detail_component.html.erb`
- Test: `spec/components/member/surface_detail_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SurfaceDetailComponent, type: :component do
  let(:customer) { create(:customer) }

  Row = Struct.new(:id, :name, :amount_cents, :refunds, keyword_init: true) do
    def refunds_any?
      Array(refunds).any?
    end
  end

  let(:record) do
    Row.new(id: 7, name: "Alpha", amount_cents: 4200, refunds: [{ at: "2026-01-01", amount: 100 }])
  end

  let(:surface) do
    Member::Surface.new(
      key: :widgets, label: "Widgets", icon: :sparkles,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Widgets", scope: ->(_u) { [] },
        columns: [{ label: "Name", value: ->(r) { r.name } }],
        empty_state: { headline: "x", body: "y", icon: :sparkles },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title:    ->(r) { "Widget #{r.name}" },
        subtitle: ->(_r) { "Subtitle" },
        meta:     ->(_r) { { label: "active", tone: :success } },
        sections: [
          { rows: [
              { label: "Amount", value: ->(r) { r.amount_cents }, format: :money_large },
              { label: "Name",   value: ->(r) { r.name } }
          ]},
          { title: "Refunds",
            when:  ->(r) { r.refunds_any? },
            list:  ->(r) { r.refunds.map { |x| { left: x[:at], right: x[:amount], format: :money } } } }
        ]
      )
    )
  end

  it "renders the title, subtitle, and meta from the descriptor" do
    render_inline(described_class.new(surface: surface, record: record, customer: customer))

    expect(page).to have_css("h1.text-title", text: "Widget Alpha")
    expect(page).to have_text("Subtitle")
    expect(page).to have_css("span.badge.badge-success", text: "active")
  end

  it "renders an eyebrow back-link to the index" do
    render_inline(described_class.new(surface: surface, record: record, customer: customer))
    expect(page).to have_link(/Back to Widgets/i, href: "/#{customer.id}/member/widgets")
  end

  it "renders grid sections" do
    render_inline(described_class.new(surface: surface, record: record, customer: customer))
    expect(page).to have_css("dt", text: "Amount")
    expect(page).to have_css("span.text-3xl", text: "$42.00")
    expect(page).to have_css("dt", text: "Name")
    expect(page).to have_css("dd", text: "Alpha")
  end

  it "renders list sections with title + line items" do
    render_inline(described_class.new(surface: surface, record: record, customer: customer))
    expect(page).to have_css("h2.text-heading", text: "Refunds")
    expect(page).to have_text("2026-01-01")
    expect(page).to have_text("$1.00")
  end

  it "skips a list section when its when: predicate is false" do
    no_refunds = Row.new(id: 1, name: "X", amount_cents: 0, refunds: [])
    render_inline(described_class.new(surface: surface, record: no_refunds, customer: customer))
    expect(page).not_to have_css("h2.text-heading", text: "Refunds")
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/components/member/surface_detail_component_spec.rb
```
Expected: red.

- [ ] **Step 3: Implement**

Create `app/components/member/surface_detail_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # High-level composer: renders a surface's detail page.
  class SurfaceDetailComponent < ApplicationComponent
    def initialize(surface:, record:, customer:)
      @surface  = surface
      @record   = record
      @customer = customer
    end

    attr_reader :surface, :record, :customer

    def title    = surface.detail.title.call(record)
    def subtitle = surface.detail.subtitle&.call(record)
    def meta     = surface.detail.meta&.call(record)

    def eyebrow
      { label: "← Back to #{surface.label}", path: "/#{customer.id}/member/#{surface.key}" }
    end

    def visible_sections
      surface.detail.sections.reject { |s| s[:when] && !s[:when].call(record) }
    end

    def grid_section?(section) = section[:rows].present?
    def list_section?(section) = section[:list].present?

    def list_items(section) = section[:list].call(record)

    def render_left(item)  = ERB::Util.html_escape(item[:left].to_s)
    def render_right(item) = Member::Formatters.format(item[:right], item[:format] || :string)
  end
end
```

- [ ] **Step 4: Implement the template**

Create `app/components/member/surface_detail_component.html.erb`:

```erb
<%= render Member::PageHeaderComponent.new(
      title:    title,
      subtitle: subtitle,
      eyebrow:  eyebrow,
      meta:     meta
    ) %>

<div class="space-y-4">
  <% visible_sections.each do |section| %>
    <% if grid_section?(section) %>
      <%= render Member::PageSectionComponent.new(title: section[:title]) do %>
        <%= render Member::DetailGridComponent.new(rows: section[:rows], record: record) %>
      <% end %>
    <% elsif list_section?(section) %>
      <%= render Member::PageSectionComponent.new(title: section[:title]) do %>
        <ul class="divide-y divide-border-subtle">
          <% list_items(section).each do |item| %>
            <li class="py-3 flex items-center justify-between">
              <span class="text-body-sm"><%= render_left(item) %></span>
              <span class="text-body-sm font-mono"><%= render_right(item) %></span>
            </li>
          <% end %>
        </ul>
      <% end %>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/components/member/surface_detail_component_spec.rb
```
Expected: 5 green.

- [ ] **Step 6: Commit**

```
git add app/components/member/surface_detail_component.rb \
        app/components/member/surface_detail_component.html.erb \
        spec/components/member/surface_detail_component_spec.rb
git commit -m "feat(member): add SurfaceDetailComponent composer"
```

---

## Phase 7 — Refactor Profile show

### Task 13: Recompose `app/views/member/profiles/show.html.erb` onto primitives

**Files:**
- Modify: `app/views/member/profiles/show.html.erb`
- Test: `spec/system/member/profile_spec.rb` (existing — selectors should still pass; update if any selector checks specific old markup)

- [ ] **Step 1: Run the existing system spec to record current passing baseline**

```
bundle exec rspec spec/system/member/profile_spec.rb
```
Expected: green (baseline). If red, fix before refactor.

- [ ] **Step 2: Replace the view contents**

Replace `app/views/member/profiles/show.html.erb` with:

```erb
<% content_for :title, "Profile — Anysys" %>
<% content_for :member_nav, "profile" %>

<%= render Member::PageHeaderComponent.new(
      title:    "Profile",
      subtitle: "Your account information.",
      actions:  [
        { label: "Edit profile", path: "/#{current_user.customer_id}/member/profile/edit", variant: :primary }
      ]
    ) %>

<%= render Member::PageSectionComponent.new do %>
  <div class="flex items-center gap-5 mb-8">
    <span class="inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-member-accent to-member-accent-hover text-white text-xl font-semibold">
      <%= "#{current_user.first_name[0]}#{current_user.last_name[0]}".upcase %>
    </span>
    <div>
      <h2 class="text-heading"><%= current_user.display_name %></h2>
      <p class="text-body-sm"><%= current_user.email %></p>
    </div>
  </div>

  <%= render Member::DetailGridComponent.new(
        record: current_user,
        rows: [
          { label: "First name",   value: ->(u) { u.first_name } },
          { label: "Last name",    value: ->(u) { u.last_name } },
          { label: "Email",        value: ->(u) { u.email } },
          { label: "Member since", value: ->(u) { u.created_at }, format: :date }
        ]
      ) %>

  <div class="mt-8 flex items-center gap-3">
    <%= link_to "Sign out",
          "/#{current_user.customer_id}/auth/sign_out",
          data: { turbo_method: :delete },
          class: "btn btn-ghost" %>
  </div>
<% end %>
```

(Note: the "Edit profile" CTA moves into the header `actions:` slot; "Sign out" stays inside the section as a secondary action.)

- [ ] **Step 3: Run system + request specs for profile**

```
bundle exec rspec spec/system/member/profile_spec.rb spec/requests/member/base_authorization_spec.rb
```
Expected: green. If a selector check fails because markup intentionally moved (per stale-test policy), update the spec.

- [ ] **Step 4: Commit**

```
git add app/views/member/profiles/show.html.erb
git commit -m "refactor(member): recompose Profile show through page kit"
```

---

## Phase 8 — Refactor Profile edit

### Task 14: Recompose `app/views/member/profiles/edit.html.erb`

**Files:**
- Modify: `app/views/member/profiles/edit.html.erb`

- [ ] **Step 1: Replace the view contents**

```erb
<% content_for :title, "Edit profile — Anysys" %>
<% content_for :member_nav, "profile" %>

<%= render Member::PageHeaderComponent.new(
      title:    "Edit profile",
      subtitle: "Update your name or email.",
      eyebrow:  { label: "← Back to profile", path: "/#{current_user.customer_id}/member/profile" }
    ) %>

<%= render Member::PageSectionComponent.new do %>
  <%= form_with model: @contract,
        url:    "/#{current_user.customer_id}/member/profile",
        scope:  :member_profiles_update_contract,
        method: :patch,
        class:  "space-y-5" do |f| %>

    <% if @contract.errors.any? %>
      <div class="rounded-lg bg-danger-subtle border border-danger/20 p-3">
        <ul class="text-sm text-danger list-disc pl-5 space-y-1">
          <% @contract.errors.full_messages.each do |msg| %>
            <li><%= msg %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <div>
        <%= f.label :first_name, class: "form-label form-label-required" %>
        <%= f.text_field :first_name, value: current_user.first_name, class: "input-field" %>
      </div>
      <div>
        <%= f.label :last_name, class: "form-label form-label-required" %>
        <%= f.text_field :last_name, value: current_user.last_name, class: "input-field" %>
      </div>
    </div>

    <div>
      <%= f.label :email, class: "form-label form-label-required" %>
      <%= f.email_field :email, value: current_user.email, class: "input-field" %>
    </div>

    <div class="flex items-center gap-3 pt-2">
      <%= f.submit "Save changes", class: "btn-member" %>
      <%= link_to "Cancel", "/#{current_user.customer_id}/member/profile", class: "btn btn-ghost" %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 2: Run profile system spec**

```
bundle exec rspec spec/system/member/profile_spec.rb
```
Expected: green.

- [ ] **Step 3: Commit**

```
git add app/views/member/profiles/edit.html.erb
git commit -m "refactor(member): recompose Profile edit through page kit"
```

---

## Phase 9 — Refactor Security

### Task 15: Recompose `app/views/member/securities/show.html.erb`

**Files:**
- Modify: `app/views/member/securities/show.html.erb`

- [ ] **Step 1: Replace contents**

```erb
<% content_for :title, "Security — Anysys" %>
<% content_for :member_nav, "security" %>

<%= render Member::PageHeaderComponent.new(
      title:    "Security",
      subtitle: "Manage your password and two-factor authentication."
    ) %>

<div class="space-y-4">
  <%= render Member::PageSectionComponent.new(title: "Password",
        description: "Replace your password with a new one. We'll email you a reset link.") do %>
    <div class="flex justify-end">
      <%= link_to "Change password",
            new_user_password_path(customer_id: current_user.customer_id),
            class: "btn-member" %>
    </div>
  <% end %>

  <%= render Member::PageSectionComponent.new(title: "Two-factor authentication") do %>
    <div class="flex items-start justify-between gap-6 flex-wrap">
      <div class="flex items-start gap-4">
        <span class="inline-flex h-9 w-9 items-center justify-center rounded-lg <%= @mfa_enabled ? 'bg-success-subtle text-success' : 'bg-warning-subtle text-warning' %>">
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3z"/>
          </svg>
        </span>
        <p class="text-body-sm">
          <% if @mfa_enabled %>
            2FA is on. You'll be prompted for a code on every sign-in.
          <% else %>
            2FA is off. We strongly recommend turning it on.
          <% end %>
        </p>
      </div>

      <% if @mfa_enabled %>
        <%= button_to "Disable 2FA",
              "/#{current_user.customer_id}/auth/mfa",
              method: :delete,
              class: "btn btn-ghost text-danger",
              data: { confirm: "Disable two-factor authentication for your account?" } %>
      <% else %>
        <%= link_to "Set up 2FA",
              "/#{current_user.customer_id}/auth/mfa/setup",
              class: "btn-member" %>
      <% end %>
    </div>
  <% end %>

  <%= render Member::PageSectionComponent.new(title: "Last sign-in") do %>
    <% if @last_signin[:at] %>
      <%= render Member::DetailGridComponent.new(
            record: @last_signin,
            rows: [
              { label: "When",    value: ->(s) { s[:at] }, format: :datetime },
              { label: "From IP", value: ->(s) { s[:ip] || "unknown" }, format: :mono }
            ]
          ) %>
    <% else %>
      <p class="text-body-sm">No sign-in history yet.</p>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 2: Run system spec**

```
bundle exec rspec spec/system/member/security_spec.rb
```
Expected: green; update selectors per stale-test policy if needed.

- [ ] **Step 3: Commit**

```
git add app/views/member/securities/show.html.erb
git commit -m "refactor(member): recompose Security through page kit"
```

---

## Phase 10 — Surface controller + routes + views

### Task 16: SurfacesController + views (no descriptor yet — uses a stub for the spec)

**Files:**
- Create: `app/controllers/member/surfaces_controller.rb`
- Create: `app/views/member/surfaces/index.html.erb`
- Create: `app/views/member/surfaces/show.html.erb`
- Modify: `config/routes.rb` (line ~363)
- Test: `spec/requests/member/surfaces_spec.rb`

A stub descriptor is registered in the spec; the existing `Member::PaymentsController` is still in place at this task — we're proving the controller works with a non-Payments key first. Payments swap happens in Task 18.

- [ ] **Step 1: Update routes**

In `config/routes.rb`, locate the `2c. MEMBER` block (around line 359). Edit to add the `surfaces` resource alongside the existing `payments` line:

```ruby
namespace :member do
  resource  :dashboard, only: :show, controller: "dashboards", path: ""
  resource  :profile,   only: %i[show edit update]
  resource  :security,  only: :show, controller: "securities"
  resources :payments,  only: %i[index show]   # to be deleted in Task 18
  resources :surfaces,  only: %i[index show], param: :id, path: ":key"
end
```

The two routes will coexist briefly. The `:key` glob path will not capture `payments` because Rails routes are tried in order — the explicit `:payments` route wins. After Task 18 deletes `:payments`, the `:key` route resolves it.

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/member/surfaces_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member surfaces", type: :request do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer) }

  let(:test_surface) do
    Member::Surface.new(
      key:   :test_widgets,
      label: "Widgets",
      icon:  :sparkles,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title:    "Widgets",
        subtitle: "All widgets",
        scope:    ->(u) { Payments::Payment.where(user_id: u.id, customer_id: u.customer_id).order(:id) },
        columns:  [
          { label: "Provider", value: ->(r) { r.provider } },
          { label: "Amount",   value: ->(r) { r.amount_cents }, format: :money, align: :right }
        ],
        empty_state: { headline: "No widgets", body: "yet", icon: :sparkles },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title: ->(r) { "Widget #{r.out_trade_no}" },
        sections: [
          { rows: [
              { label: "Provider", value: ->(r) { r.provider } },
              { label: "Amount",   value: ->(r) { r.amount_cents }, format: :money }
          ]}
        ]
      )
    )
  end

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: auth_module) { |a| a.status = :active }
    Member::Surfaces.register(test_surface)
    sign_in user
  end

  after { Member::Surfaces.reset! }

  def make_payment(for_user:)
    order = Payments::Order.create!(
      customer_id: customer.id, external_ref: SecureRandom.hex(4),
      subject: "S", amount_cents: 1000, currency: "CNY", status: "pending"
    )
    Payments::Payment.create!(
      customer_id: customer.id, user_id: for_user.id, payment_order_id: order.id,
      provider: "alipay", flow: "qr", out_trade_no: "X-#{SecureRandom.hex(4)}",
      amount_cents: 1000, status: "succeeded"
    )
  end

  it "returns 404 for an unknown surface key" do
    get "/#{customer.id}/member/totally_unknown"
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 when the surface's enabled_for? returns false" do
    surface = test_surface.dup
    surface.key = :gated_widgets
    surface.enabled_for = ->(_u) { false }
    Member::Surfaces.register(surface)

    get "/#{customer.id}/member/gated_widgets"
    expect(response).to have_http_status(:not_found)
  end

  it "renders the index for a registered surface" do
    make_payment(for_user: user)
    get "/#{customer.id}/member/test_widgets"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Widgets")
    expect(response.body).to include("alipay")
  end

  it "scopes records via the descriptor scope (does not show other users' rows)" do
    other = create(:user, :member, customer: customer)
    make_payment(for_user: other)

    get "/#{customer.id}/member/test_widgets"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No widgets")
  end

  it "returns 404 on show when the record is not in the descriptor scope" do
    other = create(:user, :member, customer: customer)
    theirs = make_payment(for_user: other)

    get "/#{customer.id}/member/test_widgets/#{theirs.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "renders show for a record in the user's scope" do
    mine = make_payment(for_user: user)
    get "/#{customer.id}/member/test_widgets/#{mine.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(mine.out_trade_no)
  end
end
```

- [ ] **Step 3: Run, confirm failure**

```
bundle exec rspec spec/requests/member/surfaces_spec.rb
```
Expected: red — controller/views missing.

- [ ] **Step 4: Implement the controller**

Create `app/controllers/member/surfaces_controller.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Generic index/show controller for descriptor-driven member surfaces.
  # The descriptor is fetched by params[:key]; the scope, columns, and detail
  # layout come from the registered Member::Surface.
  class SurfacesController < BaseController
    before_action :load_surface

    def index
      scope = @surface.index.scope.call(current_user)
      @records, @page_meta = Member::PageFilters.paginate(
        scope, page: params[:page], per_page: @surface.index.per_page_or_default
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
      @surface = Member::Surfaces.fetch(params[:key])
      raise ActiveRecord::RecordNotFound unless @surface.enabled_for?(current_user)
    end
  end
end
```

- [ ] **Step 5: Implement the views**

Create `app/views/member/surfaces/index.html.erb`:

```erb
<% content_for :title, "#{@surface.label} — Anysys" %>
<% content_for :member_nav, @surface.key %>

<%= render Member::SurfaceIndexComponent.new(
      surface:   @surface,
      records:   @records,
      page_meta: @page_meta,
      customer:  current_customer
    ) %>
```

Create `app/views/member/surfaces/show.html.erb`:

```erb
<% content_for :title, "#{@surface.label} — Anysys" %>
<% content_for :member_nav, @surface.key %>

<%= render Member::SurfaceDetailComponent.new(
      surface:  @surface,
      record:   @record,
      customer: current_customer
    ) %>
```

(`current_customer` is exposed by `TenantContext` and is already available in views.)

- [ ] **Step 6: Run, confirm green**

```
bundle exec rspec spec/requests/member/surfaces_spec.rb
```
Expected: 6 green.

- [ ] **Step 7: Commit**

```
git add app/controllers/member/surfaces_controller.rb \
        app/views/member/surfaces/index.html.erb \
        app/views/member/surfaces/show.html.erb \
        config/routes.rb \
        spec/requests/member/surfaces_spec.rb
git commit -m "feat(member): add SurfacesController + descriptor views"
```

---

## Phase 11 — Migrate Payments to a descriptor

### Task 17: Add `FeatureModules::Payment::MemberSurface` (descriptor only — controller still active)

**Files:**
- Create: `app/services/feature_modules/payment/member_surface.rb`

This task only adds the file. The Payments controller is still serving `/member/payments`. The descriptor coexists; the next task removes the old controller and switches navigation/routes.

- [ ] **Step 1: Write the descriptor**

Create `app/services/feature_modules/payment/member_surface.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  module Payment
    # Member-side read-only surface for the Payments module.
    # Drives /:cid/member/payments and /:cid/member/payments/:id
    # via Member::SurfacesController.
    MemberSurface = Member::Surface.new(
      key:   :payments,
      label: "Payments",
      icon:  :credit_card,
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
          { label: "Date",   value: ->(r) { r.created_at }, format: :date },
          { label: "Vendor", value: ->(r) { r.provider.titleize } },
          { label: "Amount", value: ->(r) { r.amount_cents }, format: :money, align: :right },
          { label: "Status", value: ->(r) { r.status }, format: :status_pill }
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
            rows: [
              { label: "Amount",  value: ->(r) { r.amount_cents }, format: :money_large },
              { label: "Vendor",  value: ->(r) { r.provider.titleize } },
              { label: "Flow",    value: ->(r) { r.flow.upcase } },
              { label: "Paid at", value: ->(r) { r.paid_at }, format: :datetime,
                when: ->(r) { r.paid_at } },
              { label: "PSP transaction id",
                value: ->(r) { r.psp_transaction_id }, format: :mono, span: 2,
                when: ->(r) { r.psp_transaction_id.present? } }
            ]
          },
          {
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
end
```

- [ ] **Step 2: Verify discovery picks it up**

The Payments module record exists in the DB with `key: "payment"` (singular). Verify `Member::Surfaces.all` includes the descriptor in a console-style spec — but we can also defer the verification to the next task's request specs. Quick smoke:

```
bundle exec rails runner -e test "FeatureModules::Module.find_or_create_by!(key: 'payment') { |m| m.name = 'Payments' }; Member::Surfaces.reset!; pp Member::Surfaces.all.map(&:key)"
```
Expected: includes `:payments`.

(If you skip the smoke step, the next task's specs catch a missing descriptor.)

- [ ] **Step 3: Commit**

```
git add app/services/feature_modules/payment/member_surface.rb
git commit -m "feat(payments): add MemberSurface descriptor"
```

---

### Task 18: Switch Payments to descriptor — delete old controller, views, request spec; update navigation

**Files:**
- Delete: `app/controllers/member/payments_controller.rb`
- Delete: `app/views/member/payments/index.html.erb`, `app/views/member/payments/show.html.erb`
- Delete: `spec/requests/member/payments_spec.rb`
- Modify: `config/routes.rb` (remove `resources :payments`)
- Modify: `app/services/member/navigation.rb` (derive `:payments` from descriptor)
- Test: `spec/system/member/payments_spec.rb` (existing — should still pass against the new pipeline)

- [ ] **Step 1: Confirm the existing system spec passes against the OLD path**

```
bundle exec rspec spec/system/member/payments_spec.rb
```
Expected: green (baseline before the swap).

- [ ] **Step 2: Update navigation registry**

Replace `app/services/member/navigation.rb` with:

```ruby
# frozen_string_literal: true

require_relative "navigation/item"

module Member
  # Registry of member navigation items.
  #
  # Bespoke entries (Home, Profile, Security) are hardcoded — they are not
  # descriptor-driven surfaces. Descriptor-driven entries are derived from
  # Member::Surfaces.all, so adding a new descriptor in any module
  # also surfaces it in the nav.
  module Navigation
    BESPOKE_ITEMS = [
      Item.new(
        key: :home, label: "Home", icon: :home,
        path:    ->(customer) { "/#{customer.id}/member" },
        visible: ->(_user) { true }
      ),
      Item.new(
        key: :profile, label: "Profile", icon: :user,
        path:    ->(customer) { "/#{customer.id}/member/profile" },
        visible: ->(_user) { true }
      ),
      Item.new(
        key: :security, label: "Security", icon: :shield_check,
        path:    ->(customer) { "/#{customer.id}/member/security" },
        visible: ->(_user) { true }
      )
    ].freeze

    def self.items_for(user)
      bespoke = BESPOKE_ITEMS
      surfaces = Member::Surfaces.all.map { |surface| item_from_surface(surface) }
      (bespoke + surfaces).select { |item| item.visible_to?(user) }
    end

    def self.item_from_surface(surface)
      Item.new(
        key:     surface.key,
        label:   surface.label,
        icon:    surface.icon,
        path:    ->(customer) { "/#{customer.id}/member/#{surface.key}" },
        visible: ->(user) { surface.enabled_for?(user) }
      )
    end
  end
end
```

- [ ] **Step 3: Update routes**

Open `config/routes.rb`. In the `2c. MEMBER` block, remove the `resources :payments` line so the block reads:

```ruby
namespace :member do
  resource  :dashboard, only: :show, controller: "dashboards", path: ""
  resource  :profile,   only: %i[show edit update]
  resource  :security,  only: :show, controller: "securities"
  resources :surfaces,  only: %i[index show], param: :id, path: ":key"
end
```

- [ ] **Step 4: Delete the old files**

```
git rm app/controllers/member/payments_controller.rb \
       app/views/member/payments/index.html.erb \
       app/views/member/payments/show.html.erb \
       spec/requests/member/payments_spec.rb
```

- [ ] **Step 5: Update existing top_nav component spec (uses the navigation registry)**

`spec/components/member/top_nav_component_spec.rb` constructs `Member::Navigation.items_for(user)`. After the change, that returns Home/Profile/Security/Payments only when the Payments module is enabled for the user's customer. Open the spec and update it so the example explicitly enables the Payments module for the user's customer before constructing `items`:

In the `let(:items)` block at the top, change to:

```ruby
let(:items) do
  payments_module = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
  FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: payments_module) { |a| a.status = :active }
  payments_module_record = FeatureModules::Module.find_or_create_by!(key: "payments") { |m| m.name = "Payments" }
  FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: payments_module_record) { |a| a.status = :active }
  Member::Surfaces.reset!
  Member::Navigation.items_for(user)
end
```

(Two records seeded: `"payment"` because `Member::Surfaces` discovers via `FeatureModules::Module.all` and looks up `FeatureModules::Payment` (camelize of `"payment"`); `"payments"` because the descriptor's `enabled_for` calls `FeatureModules::Module.enabled?(key: "payments")` — the existing inconsistency is preserved deliberately, see spec §4.5.)

- [ ] **Step 6: Update the existing system spec selector**

`spec/system/member/payments_spec.rb` currently signs the user in then visits `/member/payments`. The existing spec only seeds the `"payments"` (plural) module record. Update its `before` block so it also seeds the `"payment"` (singular) record so the descriptor is discovered:

```ruby
before do
  payments_module_plural  = FeatureModules::Module.find_or_create_by!(key: "payments") { |m| m.name = "Payments" }
  FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: payments_module_plural) { |a| a.status = :active }
  payments_module_singular = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
  FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: payments_module_singular) { |a| a.status = :active }
  Member::Surfaces.reset!
  sign_in user
end
```

- [ ] **Step 7: Run the full member suite**

```
bundle exec rspec spec/system/member spec/requests/member spec/components/member spec/services/member
```
Expected: all green. If any spec fails because of stale assertions (markup moved, selectors changed), update the spec per the stale-test policy.

- [ ] **Step 8: Hit the URL in dev to smoke-test**

```
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &
```

Open `http://localhost:3000/<cid>/member/payments` for a tenant with the Payments module enabled. Confirm:
- The page renders.
- A row from the user's payments appears (or the empty state).
- Clicking a row reaches `/member/payments/<id>` and renders the detail page with status badge and the Refunds section if applicable.

Stop the dev server.

- [ ] **Step 9: Commit**

```
git add -A
git commit -m "refactor(payments): drive member payments through Surface descriptor"
```

---

## Phase 12 — Smoke spec for the kit

### Task 19: Surface kit end-to-end smoke spec

**Files:**
- Create: `spec/system/member/surface_kit_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member surface kit smoke", type: :system do
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer) }

  let(:stub_surface) do
    Member::Surface.new(
      key: :smoke_widgets, label: "Smoke widgets", icon: :sparkles,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Smoke widgets",
        subtitle: "All formats",
        scope: ->(u) { Payments::Payment.where(user_id: u.id, customer_id: u.customer_id).order(:id) },
        columns: [
          { label: "Date",     value: ->(r) { r.created_at }, format: :date },
          { label: "Provider", value: ->(r) { r.provider.titleize } },
          { label: "Amount",   value: ->(r) { r.amount_cents }, format: :money, align: :right },
          { label: "Status",   value: ->(r) { r.status }, format: :status_pill },
          { label: "Out trade no", value: ->(r) { r.out_trade_no }, format: :mono }
        ],
        empty_state: { headline: "Nothing here", body: "yet", icon: :sparkles },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title:    ->(r) { "Smoke #{r.out_trade_no}" },
        subtitle: ->(r) { "At #{I18n.l(r.created_at, format: :long)}" },
        meta:     ->(r) { { label: r.status, tone: :success } },
        sections: [
          { rows: [
              { label: "Amount", value: ->(r) { r.amount_cents }, format: :money_large },
              { label: "Status", value: ->(r) { r.status }, format: :status_pill },
              { label: "Provider", value: ->(r) { r.provider.titleize } }
          ]},
          { title: "Mono",
            list: ->(r) { [{ left: "id", right: r.out_trade_no, format: :mono }] } }
        ]
      )
    )
  end

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: auth_module) { |a| a.status = :active }
    Member::Surfaces.register(stub_surface)

    order = Payments::Order.create!(customer_id: customer.id, external_ref: "T",
                                    subject: "S", amount_cents: 4200, currency: "CNY", status: "pending")
    Payments::Payment.create!(customer_id: customer.id, user_id: user.id, payment_order_id: order.id,
                              provider: "alipay", flow: "qr", out_trade_no: "OUT123",
                              amount_cents: 4200, status: "succeeded")
    sign_in user
  end

  after { Member::Surfaces.reset! }

  it "renders the index, then a detail page, exercising every advertised format" do
    visit "/#{customer.id}/member/smoke_widgets"

    expect(page).to have_text("Smoke widgets")
    expect(page).to have_text("Alipay")
    expect(page).to have_text("$42.00")
    expect(page).to have_css("span.badge.badge-success", text: "succeeded")
    expect(page).to have_css("span.font-mono", text: "OUT123")

    click_link "View →"

    expect(page).to have_css("h1.text-title", text: "Smoke OUT123")
    expect(page).to have_css("span.text-3xl.font-mono", text: "$42.00")
    expect(page).to have_css("span.badge.badge-success", text: "succeeded")
    expect(page).to have_link(/Back to Smoke widgets/i)
  end
end
```

- [ ] **Step 2: Run, confirm green**

```
bundle exec rspec spec/system/member/surface_kit_spec.rb
```
Expected: green.

- [ ] **Step 3: Commit**

```
git add spec/system/member/surface_kit_spec.rb
git commit -m "test(member): add surface kit end-to-end smoke spec"
```

---

## Final verification

### Task 20: Run the full member suite + admin sanity

- [ ] **Step 1: Member suite**

```
bundle exec rspec spec/system/member spec/requests/member spec/components/member spec/services/member
```
Expected: all green.

- [ ] **Step 2: A small admin sanity sweep**

```
bundle exec rspec spec/components/admin_table_component_spec.rb spec/components/admin_page_component_spec.rb 2>/dev/null || true
bundle exec rspec spec/system/admin -e "dashboard" 2>/dev/null || true
```

(These are spot checks; the kit changes are member-only, so admin should be untouched.)

- [ ] **Step 3: Smoke the dev server**

```
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &
```

Visit:
- `/<cid>/member` — Home renders.
- `/<cid>/member/profile` — recomposed view renders.
- `/<cid>/member/profile/edit` — recomposed form renders, save round-trips.
- `/<cid>/member/security` — three sections render.
- `/<cid>/member/payments` — descriptor-driven index renders.
- `/<cid>/member/payments/<id>` — descriptor-driven detail renders.
- `/<cid>/member/totally_unknown` — 404.

Stop the dev server.

- [ ] **Step 4: Final commit (only if anything was tweaked above)**

If any final fixes were needed, commit them with an appropriate message; otherwise skip.

---

## Plan self-review

**Spec coverage check:**

- §3 architecture — Tasks 1–12 build the primitives + composers; Task 16 builds the controller; Task 18 wires routes/navigation. ✓
- §4.1 Surface struct — Task 3. ✓
- §4.2 Index spec — Task 3 (struct), Task 7 (consumed by IndexTable). ✓
- §4.3 Detail spec — Task 3 (struct), Task 12 (consumed by SurfaceDetail). ✓
- §4.4 Format vocabulary — Task 1. ✓
- §4.5 Payments descriptor — Task 17. ✓
- §4.6 Course-scores example — illustrative only in the spec; no task implements Course models, by design (spec §2 explicit non-goal "Course models are out of scope"). ✓
- §5 Component contracts — Tasks 5, 6, 7, 8, 9, 10, 11, 12. ✓
- §6 Authorization — inherited; verified end-to-end by Task 16's request specs. ✓
- §7 Refactor table — Tasks 13 (Profile show), 14 (Profile edit), 15 (Security), 18 (Payments). Home stays bespoke per spec. ✓
- §8 Styling — no new tokens; primitives use existing utilities. ✓
- §9 Test inventory — every listed spec has a task; the deleted `payments_spec.rb` is replaced by `surfaces_spec.rb` (Task 16). ✓
- §10 Phases — this plan's 12 phases mirror the spec's 4 phases at finer granularity. ✓
- §11 Risks — module-disabled-returns-404 verified in Task 16; namespace collision with admin's EmptyStateComponent handled by Task 9 (separate `Member::EmptyStateComponent` class). ✓
- §12 Acceptance criteria — every criterion is covered by a test in this plan. ✓

**Placeholder scan:** none — every step contains the actual code.

**Type consistency check:**
- `Member::Surface::Index#per_page_or_default` (Task 3) is called by `SurfacesController` (Task 16). ✓
- `Member::Formatters.format(value, key)` signature is used identically by `IndexTable`, `DetailGrid`, `SurfaceDetail`. ✓
- `Member::PageFilters::Meta` fields (`page`, `per_page`, `total_count`) match what `PaginationComponent` (Task 10) and `SurfaceIndexComponent` (Task 11) read. ✓
- Eyebrow shape `{ label:, path: }` matches between `PageHeaderComponent` (Task 5) and `SurfaceDetailComponent#eyebrow` (Task 12). ✓
- Action shape `{ label:, path:, variant: }` matches between `PageHeaderComponent` (Task 5) and Profile show usage (Task 13). ✓
- `current_customer` helper used in surface views (Task 16) is supplied by the existing `TenantContext` concern. ✓

Plan is self-consistent.
