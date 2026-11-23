# User-Completable Module Handoff Inputs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **NO COMMITS.** Per the user's directive, all work happens **directly on `master` with no git commits**. Every task ends with a targeted-spec checkpoint instead of a commit. Do NOT run `git commit`, `git add`, or create branches.

**Goal:** Let a feature module declare inputs the end user completes on a module-owned entry page (pre-filled from the author's mapping), demonstrated by making Payment's optional `body` (note) user-fillable — without weakening the author-controlled money trust model.

**Architecture:** A per-field `source:` DSL (`:author_only` default, `:user_fillable` opt-in) flows into `HandoffField`. The page-save contract only requires *author-only* required inputs to be mapped. A pure `FeatureModules::HandoffCompletion` service filters user params to fillable-only (mass-assignment guard), casts, merges over the invocation input, and re-validates. Payment gains a separate `#collect`/`#complete` entry step that renders a `HandoffEntryComponent` and materializes the order from the merged input; modules with no fillable fields keep the current immediate path byte-for-byte.

**Tech Stack:** Rails 8.1, Reform contracts, ViewComponent, Tailwind, RSpec. No new gems. No Stimulus expected.

---

## File Structure

- `app/services/feature_modules/base_module.rb` — add `source:` to the contract DSL.
- `app/services/feature_modules/handoff_field.rb` — carry `source`, add `user_fillable?` / `author_only?`, include `source` in `to_h`.
- `app/contracts/feature_module_handoff_contract.rb` — relax required-mapping to author-only fields.
- `app/services/feature_modules/invocation.rb` — add `update_input!` writer (tenant-checked, sole session-key owner).
- `app/services/feature_modules/handoff_completion.rb` — **new** service (fillable-only guard → cast → merge → re-validate).
- `app/services/feature_modules/payment/registration.rb` — mark `body` `user_fillable`.
- `app/components/payments/handoff_entry_component.rb` + `.html.erb` — **new** module-owned entry form.
- `config/locales/comp_payments.en.yml` / `comp_payments.zh-CN.yml` — `handoff_entry` keys (en/zh parity).
- `config/routes.rb` — `checkout/collect` (GET) + `checkout/complete` (POST).
- `app/controllers/payments/checkouts_controller.rb` — `#start` branch + `#collect` + `#complete` + params helper.
- Specs alongside each task.

---

### Task 1: `source:` field DSL + `HandoffField` predicates

**Files:**
- Modify: `app/services/feature_modules/base_module.rb`
- Modify: `app/services/feature_modules/handoff_field.rb`
- Test: `spec/services/feature_modules/base_module_spec.rb`

- [ ] **Step 1: Write the failing tests** — append inside the top-level `RSpec.describe FeatureModules::BaseModule` block in `spec/services/feature_modules/base_module_spec.rb`:

```ruby
describe "input_contract source: policy" do
  let(:mod) do
    Class.new(FeatureModules::BaseModule) do
      input_contract do
        property :amount, type: :integer, validates: { presence: true }
        property :note,   type: :string, source: :user_fillable
      end
    end
  end

  it "defaults an undeclared source to author_only" do
    amount = mod.input_contract_fields.find { |f| f.name == "amount" }
    expect(amount.author_only?).to be(true)
    expect(amount.user_fillable?).to be(false)
    expect(amount.source).to eq("author_only")
  end

  it "honors an explicit source: :user_fillable" do
    note = mod.input_contract_fields.find { |f| f.name == "note" }
    expect(note.user_fillable?).to be(true)
    expect(note.author_only?).to be(false)
  end

  it "exposes source in to_h" do
    note = mod.input_contract_fields.find { |f| f.name == "note" }
    expect(note.to_h).to include(source: "user_fillable")
  end
end
```

- [ ] **Step 2: Run and verify failure**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb -e "source"`
Expected: FAIL (`unknown keyword: :source` or `undefined method 'user_fillable?'`).

- [ ] **Step 3: Add `source:` to the DSL.** In `app/services/feature_modules/base_module.rb`, replace the `ContractDsl#property` method:

```ruby
      # `source:` declares WHO may supply this input at runtime:
      #   :author_only   (default) — must be author-mapped; never user-entered.
      #   :user_fillable — the end user may complete/override it on the module's
      #                    entry page (see FeatureModules::HandoffCompletion).
      # Defaulting to :author_only is fail-safe: a forgotten annotation keeps the
      # strict "must be mapped" behavior rather than silently exposing a field.
      def property(name, type: nil, source: nil, validates: nil, **_ignored)
        @properties << { name: name.to_s, type: type&.to_s,
                         source: (source || :author_only).to_s, validates: validates || {} }
      end
```

- [ ] **Step 4: Carry `source` on `HandoffField`.** In `app/services/feature_modules/handoff_field.rb`:

Update `.from` to pass source:

```ruby
    def self.from(definition)
      new(name: definition.fetch(:name),
          type: definition[:type],
          source: definition[:source],
          validates: definition[:validates] || {})
    end
```

Update `initialize` signature and body (add `source:` param, set `@source`):

```ruby
    def initialize(name:, validates:, type: nil, source: nil)
      @name           = name.to_s
      @validates      = validates || {}
      @required       = @validates.key?(:presence) && !!@validates[:presence]
      @allowed_values = @validates.dig(:inclusion, :in)
      @type           = type.to_s.presence || derive_type
      @source         = (source || "author_only").to_s
      @constraint     = derive_constraint
    end
```

Add `source` to the reader line and add predicates + `to_h`:

```ruby
    attr_reader :name, :required, :type, :allowed_values, :constraint, :source

    def required? = required
    def user_fillable? = @source == "user_fillable"
    def author_only?   = !user_fillable?

    def to_h
      { name: name, required: required, type: type, source: source,
        allowed_values: allowed_values, constraint: constraint }
    end
```

(Remove the old `attr_reader` / `required?` / `to_h` lines they replace.)

- [ ] **Step 5: Run and verify pass**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb`
Expected: PASS (all examples, including the new `source` ones).

- [ ] **Step 6: Checkpoint (NO COMMIT)** — leave changes in the working tree on `master`.

---

### Task 2: Relax author-time contract to author-only required inputs

**Files:**
- Modify: `app/contracts/feature_module_handoff_contract.rb`
- Test: `spec/contracts/feature_module_handoff_contract_spec.rb`

- [ ] **Step 1: Write the failing tests** — append inside the describe block in `spec/contracts/feature_module_handoff_contract_spec.rb`. This uses a stub module registration so it does not depend on Payment:

```ruby
describe "user_fillable required inputs are exempt from mapping" do
  let(:fields) do
    [
      FeatureModules::HandoffField.new(name: "amount", validates: { presence: true }, type: "integer", source: "author_only"),
      FeatureModules::HandoffField.new(name: "note",   validates: { presence: true }, type: "string",  source: "user_fillable")
    ]
  end

  before do
    fm = instance_double(FeatureModules::Module, registration_class: double(input_contract_fields: fields))
    allow(FeatureModules::Module).to receive(:find_by).and_call_original
    allow(FeatureModules::Module).to receive(:find_by).with(key: "stub").and_return(fm)
    # bypass the module-enabled check for this unit
    allow_any_instance_of(FeatureModuleHandoffContract).to receive(:module_enabled_for_current_customer)
  end

  it "does not require a user_fillable field to be mapped" do
    form = FeatureModuleHandoffContract.new(OpenStruct.new)
    ok = form.validate(
      "module_key"    => "stub",
      "exit_target"   => { "kind" => "route", "name" => "customer_home" },
      "input_mapping" => { "amount" => { "source" => "literal", "value" => "100" } } # note left unmapped
    )
    expect(form.errors[:input_mapping].join).not_to include("note")
  end

  it "still requires an author_only required field to be mapped" do
    form = FeatureModuleHandoffContract.new(OpenStruct.new)
    form.validate(
      "module_key"    => "stub",
      "exit_target"   => { "kind" => "route", "name" => "customer_home" },
      "input_mapping" => { "note" => { "source" => "literal", "value" => "hi" } } # amount left unmapped
    )
    expect(form.errors[:input_mapping].join).to include("amount")
  end
end
```

- [ ] **Step 2: Run and verify failure**

Run: `bundle exec rspec spec/contracts/feature_module_handoff_contract_spec.rb -e "user_fillable required"`
Expected: FAIL (the first example fails — `note` is currently reported as unmapped).

- [ ] **Step 3: Relax the rule.** In `app/contracts/feature_module_handoff_contract.rb`, change the `required_inputs_are_mapped` selector line from:

```ruby
    module_input_fields.select(&:required?).each do |field|
```

to:

```ruby
    # user_fillable inputs are completed by the end user on the module's entry
    # page, so they need not be author-mapped — only author_only required inputs
    # must be satisfiable at page-save time.
    module_input_fields.select { |f| f.required? && f.author_only? }.each do |field|
```

- [ ] **Step 4: Run and verify pass**

Run: `bundle exec rspec spec/contracts/feature_module_handoff_contract_spec.rb`
Expected: PASS (new + all pre-existing examples).

- [ ] **Step 5: Checkpoint (NO COMMIT).**

---

### Task 3: `Invocation.update_input!` writer

**Files:**
- Modify: `app/services/feature_modules/invocation.rb`
- Test: `spec/services/feature_modules/invocation_spec.rb`

- [ ] **Step 1: Write the failing tests** — append inside the describe block in `spec/services/feature_modules/invocation_spec.rb`:

```ruby
describe ".update_input!" do
  let(:customer) { create(:customer) }
  before { Current.customer = customer }

  def seeded_session(input)
    { FeatureModules::Invocation::SESSION_KEY =>
        { module_key: "payment", customer_id: customer.id, input: input } }
  end

  it "overwrites the invocation input for the live invocation" do
    session = seeded_session(amount_cents: 100)
    FeatureModules::Invocation.update_input!(session: session, input: { amount_cents: 100, body: "hi" })
    stored = session[FeatureModules::Invocation::SESSION_KEY]
    expect(stored[:input] || stored["input"]).to include("body" => "hi").or include(body: "hi")
  end

  it "no-ops when no invocation is present" do
    session = {}
    expect(FeatureModules::Invocation.update_input!(session: session, input: { a: 1 })).to be_nil
    expect(session).to be_empty
  end

  it "raises CrossTenantViolation when the session belongs to another tenant" do
    session = seeded_session(amount_cents: 100)
    session[FeatureModules::Invocation::SESSION_KEY][:customer_id] = customer.id + 999
    expect {
      FeatureModules::Invocation.update_input!(session: session, input: { amount_cents: 1 })
    }.to raise_error(FeatureModules::CrossTenantViolation)
  end
end
```

- [ ] **Step 2: Run and verify failure**

Run: `bundle exec rspec spec/services/feature_modules/invocation_spec.rb -e "update_input"`
Expected: FAIL (`undefined method 'update_input!'`).

- [ ] **Step 3: Implement the writer.** In `app/services/feature_modules/invocation.rb`, add this method to the `class << self` block, right after `clear!`:

```ruby
      # Overwrite the live invocation's resolved input (e.g. after the end user
      # completes user_fillable fields on the module entry page). No-ops when no
      # invocation is present; tenant-checked like #current. Keeps Invocation the
      # sole owner of SESSION_KEY.
      def update_input!(session:, input:)
        data = session[SESSION_KEY]
        return if data.blank?

        data = data.with_indifferent_access
        if Current.customer&.id != data[:customer_id]
          raise CrossTenantViolation,
                I18n.t("feature_modules.errors.cross_tenant_violation")
        end

        data[:input] = input.transform_keys(&:to_sym)
        session[SESSION_KEY] = data
        data
      end
```

- [ ] **Step 4: Run and verify pass**

Run: `bundle exec rspec spec/services/feature_modules/invocation_spec.rb`
Expected: PASS.

- [ ] **Step 5: Checkpoint (NO COMMIT).**

---

### Task 4: `FeatureModules::HandoffCompletion` service

**Files:**
- Create: `app/services/feature_modules/handoff_completion.rb`
- Test: `spec/services/feature_modules/handoff_completion_spec.rb`

- [ ] **Step 1: Write the failing tests** — create `spec/services/feature_modules/handoff_completion_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe FeatureModules::HandoffCompletion do
  # A self-contained stub registration: amount is author_only+required, body is
  # optional user_fillable, tier is a user_fillable enum (to exercise casting).
  let(:fields) do
    [
      FeatureModules::HandoffField.new(name: "amount_cents", validates: { presence: true, numericality: { only_integer: true } }, type: "integer", source: "author_only"),
      FeatureModules::HandoffField.new(name: "body", validates: {}, type: "string", source: "user_fillable"),
      FeatureModules::HandoffField.new(name: "tier", validates: { inclusion: { in: %w[BASIC PRO] } }, type: "string", source: "user_fillable")
    ]
  end

  let(:contract_class) do
    Class.new(Reform::Form) do
      property :amount_cents
      property :body
      property :tier
      validates :amount_cents, presence: true, numericality: { only_integer: true }
      validates :tier, inclusion: { in: %w[BASIC PRO] }, allow_nil: true
    end
  end

  let(:registration) { double(input_contract_fields: fields, input_contract_class: contract_class) }
  let(:invocation)   { { module_key: "stub", input: { amount_cents: 2500 } }.with_indifferent_access }

  describe ".needs_completion?" do
    it "is true when any field is user_fillable" do
      expect(described_class.needs_completion?(registration)).to be(true)
    end

    it "is false when every field is author_only" do
      only_author = double(input_contract_fields: [fields.first], input_contract_class: contract_class)
      expect(described_class.needs_completion?(only_author)).to be(false)
    end
  end

  describe ".complete!" do
    it "merges casted user_fillable values over the invocation input" do
      result = described_class.complete!(session: {}, invocation: invocation,
                                         user_params: { "body" => "thanks", "tier" => "pro" }, registration: registration)
      expect(result).to be_ok
      expect(result.input).to include(amount_cents: 2500, body: "thanks", tier: "PRO") # enum case-normalized
    end

    it "drops author_only and unknown keys (mass-assignment guard)" do
      result = described_class.complete!(session: {}, invocation: invocation,
                                         user_params: { "amount_cents" => "1", "evil" => "x", "body" => "ok" }, registration: registration)
      expect(result).to be_ok
      expect(result.input[:amount_cents]).to eq(2500) # NOT 1
      expect(result.input).not_to have_key(:evil)
    end

    it "returns errors and no input when the merged result is invalid" do
      result = described_class.complete!(session: {}, invocation: invocation,
                                         user_params: { "tier" => "GOLD" }, registration: registration)
      expect(result).not_to be_ok
      expect(result.input).to be_nil
      expect(result.errors[:tier]).to be_present
    end
  end
end
```

- [ ] **Step 2: Run and verify failure**

Run: `bundle exec rspec spec/services/feature_modules/handoff_completion_spec.rb`
Expected: FAIL (`uninitialized constant FeatureModules::HandoffCompletion`).

- [ ] **Step 3: Implement the service.** Create `app/services/feature_modules/handoff_completion.rb`:

```ruby
# frozen_string_literal: true

require "ostruct"

module FeatureModules
  # Completes a page → module handoff whose contract declares user_fillable
  # inputs: the end user fills the gaps on the module's entry page, pre-filled
  # from whatever the author mapped. The security boundary lives here — only
  # user_fillable field names are accepted from the submitted params, so a
  # crafted request can never overwrite an author_only value (e.g. amount).
  class HandoffCompletion
    Result = Struct.new(:ok, :input, :errors, keyword_init: true) do
      def ok? = ok
    end

    class << self
      # The user_fillable fields to render on the entry page.
      def user_fillable_fields(registration)
        Array(registration.input_contract_fields).select(&:user_fillable?)
      end

      # Should the module show an entry step at all? False → no fillable fields,
      # so the module keeps its immediate (legacy) path.
      def needs_completion?(registration)
        user_fillable_fields(registration).any?
      end

      # Filter → cast → merge over the invocation input → re-validate.
      # `invocation` is the already-resolved invocation (its [:input] is the
      # author-mapped, casted payload). Persists the merged input back to the
      # live invocation via Invocation.update_input!. Pure w.r.t. its return
      # value — the merged input is returned so the caller can materialize
      # without a session round-trip.
      def complete!(session:, invocation:, user_params:, registration:)
        fields         = Array(registration.input_contract_fields)
        fillable_names = user_fillable_fields(registration).map(&:name)

        permitted = (user_params || {}).to_h.stringify_keys.slice(*fillable_names)
        casted    = FeatureModules::InputCaster.call(input: permitted, fields: fields)

        existing = ((invocation && invocation[:input]) || {}).to_h.symbolize_keys
        merged   = existing.merge(casted.symbolize_keys)

        contract = registration.input_contract_class.new(OpenStruct.new)
        unless contract.validate(merged.stringify_keys)
          return Result.new(ok: false, input: nil, errors: contract.errors)
        end

        FeatureModules::Invocation.update_input!(session: session, input: merged)
        Result.new(ok: true, input: merged, errors: nil)
      end
    end
  end
end
```

- [ ] **Step 4: Run and verify pass**

Run: `bundle exec rspec spec/services/feature_modules/handoff_completion_spec.rb`
Expected: PASS (all 6 examples).

- [ ] **Step 5: Checkpoint (NO COMMIT).**

---

### Task 5: Mark Payment's `body` user_fillable

**Files:**
- Modify: `app/services/feature_modules/payment/registration.rb`
- Test: `spec/services/feature_modules/payment/registration_spec.rb` (create if absent)

- [ ] **Step 1: Write the failing test.** If `spec/services/feature_modules/payment/registration_spec.rb` does not exist, create it; otherwise append:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Payment::Registration do
  def field(name)
    described_class.input_contract_fields.find { |f| f.name == name }
  end

  it "exposes body as the only user_fillable input" do
    fillable = described_class.input_contract_fields.select(&:user_fillable?).map(&:name)
    expect(fillable).to eq(%w[body])
  end

  it "keeps money + identity fields author_only" do
    expect(field("amount_cents").author_only?).to be(true)
    expect(field("currency").author_only?).to be(true)
    expect(field("subject").author_only?).to be(true)
  end
end
```

- [ ] **Step 2: Run and verify failure**

Run: `bundle exec rspec spec/services/feature_modules/payment/registration_spec.rb`
Expected: FAIL (`body` currently author_only → `fillable` is empty).

- [ ] **Step 3: Implement.** In `app/services/feature_modules/payment/registration.rb`, change the `body` line in `input_contract` from:

```ruby
        property :body,         type: :string
```

to:

```ruby
        # Optional payer note — safe to let the end user supply/edit on the
        # checkout entry step (non-monetary, not identity). All money + identity
        # fields stay author_only so the price can never be user-supplied.
        property :body,         type: :string,   source: :user_fillable
```

- [ ] **Step 4: Run and verify pass**

Run: `bundle exec rspec spec/services/feature_modules/payment/registration_spec.rb`
Expected: PASS.

- [ ] **Step 5: Checkpoint (NO COMMIT).**

---

### Task 6: `Payments::HandoffEntryComponent` + locales

**Files:**
- Create: `app/components/payments/handoff_entry_component.rb`
- Create: `app/components/payments/handoff_entry_component.html.erb`
- Modify: `config/locales/comp_payments.en.yml`, `config/locales/comp_payments.zh-CN.yml`
- Test: `spec/components/payments/handoff_entry_component_spec.rb`

- [ ] **Step 1: Add locale keys FIRST (component references them).** In `config/locales/comp_payments.en.yml`, under `comp_payments:` (e.g. right after the `checkout:` block), add:

```yaml
    handoff_entry:
      title: "Add a note"
      subtitle: "Add an optional note to your payment before you continue."
      continue: "Continue to payment"
      fields:
        body:
          label: "Note (optional)"
          placeholder: "Add a note for this payment"
```

In `config/locales/comp_payments.zh-CN.yml`, under `comp_payments:` in the matching position, add:

```yaml
    handoff_entry:
      title: "添加备注"
      subtitle: "在继续付款前，可为本次付款添加备注（选填）。"
      continue: "继续付款"
      fields:
        body:
          label: "备注（选填）"
          placeholder: "为本次付款填写备注"
```

- [ ] **Step 2: Write the failing component test** — create `spec/components/payments/handoff_entry_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::HandoffEntryComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:fields) do
    [FeatureModules::HandoffField.new(name: "body", validates: {}, type: "string", source: "user_fillable")]
  end

  def render_component(values: {}, errors: nil)
    render_inline(described_class.new(fields: fields, values: values, customer: customer, errors: errors))
  end

  it "renders a labelled input for each user_fillable field, posting to complete" do
    render_component
    expect(page).to have_css("form[action='/#{customer.id}/payments/checkout/complete']")
    expect(page).to have_css("textarea[name='handoff[body]']")
    expect(page).to have_text(I18n.t("comp_payments.handoff_entry.fields.body.label"))
    expect(page).to have_button(I18n.t("comp_payments.handoff_entry.continue"))
  end

  it "prefills the field from values" do
    render_component(values: { "body" => "existing note" })
    expect(page).to have_css("textarea[name='handoff[body]']", text: "existing note")
  end

  it "renders errors when present" do
    errors = double(any?: true, full_messages: ["Body is too long"])
    render_component(errors: errors)
    expect(page).to have_text("Body is too long")
  end

  it "resolves all copy in zh-CN" do
    I18n.with_locale(:"zh-CN") { render_component }
    expect(page).to have_text("添加备注")
  end
end
```

- [ ] **Step 3: Run and verify failure**

Run: `bundle exec rspec spec/components/payments/handoff_entry_component_spec.rb`
Expected: FAIL (`uninitialized constant Payments::HandoffEntryComponent`).

- [ ] **Step 4: Implement the component class.** Create `app/components/payments/handoff_entry_component.rb`:

```ruby
# frozen_string_literal: true

module Payments
  # Module-owned entry step for a page → payment handoff that carries
  # user_fillable inputs (currently the optional `body` note). Renders one field
  # per user_fillable input, pre-filled from the invocation, posting to
  # Payments::CheckoutsController#complete. No gateway/DB access here.
  class HandoffEntryComponent < ApplicationComponent
    def initialize(fields:, customer:, values: {}, errors: nil)
      @fields   = Array(fields)
      @customer = customer
      @values   = (values || {}).to_h.with_indifferent_access
      @errors   = errors
    end

    attr_reader :fields, :customer, :values, :errors

    def value_for(field) = values[field.name]

    def label_for(field)
      t("comp_payments.handoff_entry.fields.#{field.name}.label", default: field.name.humanize)
    end

    def placeholder_for(field)
      t("comp_payments.handoff_entry.fields.#{field.name}.placeholder", default: "")
    end
  end
end
```

- [ ] **Step 5: Implement the template.** Create `app/components/payments/handoff_entry_component.html.erb`:

```erb
<section class="mx-auto w-full max-w-md bg-white border border-gray-200 rounded-md p-6">
  <h1 class="text-lg font-semibold text-gray-900"><%= t("comp_payments.handoff_entry.title") %></h1>
  <p class="mt-1 text-sm text-gray-500"><%= t("comp_payments.handoff_entry.subtitle") %></p>

  <% if errors&.any? %>
    <div class="mt-3 border-l-4 border-red-400 bg-red-50 px-3 py-2 text-sm text-red-800">
      <%= errors.full_messages.to_sentence %>
    </div>
  <% end %>

  <%= form_with url: "/#{customer.id}/payments/checkout/complete", method: :post, class: "mt-6 space-y-4" do %>
    <% fields.each do |field| %>
      <div>
        <label for="handoff_<%= field.name %>" class="block text-sm font-medium text-gray-700">
          <%= label_for(field) %>
        </label>
        <textarea id="handoff_<%= field.name %>" name="handoff[<%= field.name %>]" rows="3"
                  placeholder="<%= placeholder_for(field) %>"
                  class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400"><%= value_for(field) %></textarea>
      </div>
    <% end %>

    <button type="submit"
            class="w-full rounded-md bg-gray-900 px-4 py-2.5 text-sm font-medium text-white hover:bg-gray-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400">
      <%= t("comp_payments.handoff_entry.continue") %>
    </button>
  <% end %>
</section>
```

- [ ] **Step 6: Run and verify pass**

Run: `bundle exec rspec spec/components/payments/handoff_entry_component_spec.rb`
Expected: PASS (all 4 examples).

- [ ] **Step 7: Checkpoint (NO COMMIT).**

---

### Task 7: Routes + controller `#start` branch / `#collect` / `#complete`

**Files:**
- Modify: `config/routes.rb:110-115` (the `scope "payments"` block)
- Modify: `app/controllers/payments/checkouts_controller.rb`
- Test: `spec/requests/payments/checkout_collect_spec.rb` (create)

- [ ] **Step 1: Add the routes.** In `config/routes.rb`, inside the `scope "payments" do` block, add the two routes right after the `checkout/start` line:

```ruby
      get  "checkout/collect",    to: "payments/checkouts#collect",  as: :payment_checkout_collect
      post "checkout/complete",   to: "payments/checkouts#complete", as: :payment_checkout_complete
```

- [ ] **Step 2: Write the failing request tests** — create `spec/requests/payments/checkout_collect_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
require "digest"

# The collect/complete entry step for a page → payment handoff that carries a
# user_fillable field (body). #start now diverts to #collect when the module has
# user_fillable inputs; #complete merges the payer's note and materializes the
# order — money stays author-controlled.
RSpec.describe "Payments::Checkouts collect/complete", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:token)        { "tok-fill01" }
  let(:expected_ref) { "ORD-#{Digest::SHA256.hexdigest(token)[0, 12].upcase}" }
  let(:input)        { { amount_cents: 2_500, currency: "cny", subject: "Donation" } }

  before { Current.customer = customer }

  def stub_invocation(inp: input, module_key: "payment", tok: token)
    allow_any_instance_of(Payments::CheckoutsController)
      .to receive(:current_invocation)
      .and_return({ module_key: module_key, token: tok, input: inp }.with_indifferent_access)
  end

  it "diverts #start to #collect because payment has a user_fillable field" do
    stub_invocation
    get "/#{customer.id}/payments/checkout/start"
    expect(response).to redirect_to("/#{customer.id}/payments/checkout/collect")
    expect(Payments::Order.count).to eq(0)
  end

  it "#collect renders the entry form" do
    stub_invocation
    get "/#{customer.id}/payments/checkout/collect"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="handoff[body]"')
  end

  it "#complete merges the payer note into the materialized order" do
    stub_invocation
    expect {
      post "/#{customer.id}/payments/checkout/complete", params: { handoff: { body: "Happy birthday" } }
    }.to change(Payments::Order, :count).by(1)

    order = Payments::Order.for_current_customer.find_by(external_ref: expected_ref)
    expect(order).to have_attributes(amount_cents: 2_500, subject: "Donation", body: "Happy birthday")
    expect(response).to redirect_to("/#{customer.id}/payments/checkout?ref=#{expected_ref}")
  end

  it "ignores an injected author_only param on #complete (no price tampering)" do
    stub_invocation
    post "/#{customer.id}/payments/checkout/complete",
         params: { handoff: { body: "note", amount_cents: "1" } }

    order = Payments::Order.for_current_customer.find_by(external_ref: expected_ref)
    expect(order.amount_cents).to eq(2_500) # author value, NOT 1
  end

  it "bounces #collect to the customer home without an active payment invocation" do
    stub_invocation(module_key: "sms")
    get "/#{customer.id}/payments/checkout/collect"
    expect(response).to redirect_to("/#{customer.id}")
  end

  it "refuses a cross-tenant invocation on #complete" do
    allow_any_instance_of(Payments::CheckoutsController)
      .to receive(:current_invocation).and_raise(FeatureModules::CrossTenantViolation)
    post "/#{customer.id}/payments/checkout/complete", params: { handoff: { body: "x" } }
    expect(response).to have_http_status(:forbidden)
  end
end
```

- [ ] **Step 3: Run and verify failure**

Run: `bundle exec rspec spec/requests/payments/checkout_collect_spec.rb`
Expected: FAIL (no `#collect`/`#complete` actions / routing error).

- [ ] **Step 4: Implement the controller changes.** In `app/controllers/payments/checkouts_controller.rb`:

(a) Add a module-registration constant near the top of the class (after `FLOW_COMPONENTS`):

```ruby
    REGISTRATION = FeatureModules::Payment::Registration
```

(b) Replace the body of `#start` so it diverts when completion is needed:

```ruby
    def start
      invocation = require_payment_invocation or return

      if FeatureModules::HandoffCompletion.needs_completion?(REGISTRATION)
        return redirect_to payment_checkout_collect_path(@customer.id)
      end

      order = build_order_from(invocation)
      redirect_to payment_checkout_path(@customer.id, ref: order.external_ref)
    rescue FeatureModules::CrossTenantViolation
      head :forbidden
    end
```

(c) Add the two new public actions right after `#start`:

```ruby
    # GET — render the module-owned entry form for the user_fillable inputs,
    # pre-filled from the invocation.
    def collect
      invocation = require_payment_invocation or return

      render Payments::HandoffEntryComponent.new(
        fields:   FeatureModules::HandoffCompletion.user_fillable_fields(REGISTRATION),
        values:   invocation[:input],
        customer: @customer
      )
    rescue FeatureModules::CrossTenantViolation
      head :forbidden
    end

    # POST — merge the payer-supplied fields (fillable-only, guarded in the
    # service) into the invocation input, then materialize the order.
    def complete
      invocation = require_payment_invocation or return

      result = FeatureModules::HandoffCompletion.complete!(
        session:      session,
        invocation:   invocation,
        user_params:  handoff_entry_params,
        registration: REGISTRATION
      )

      if result.ok?
        order = build_order_from(invocation.merge(input: result.input))
        redirect_to payment_checkout_path(@customer.id, ref: order.external_ref)
      else
        render Payments::HandoffEntryComponent.new(
          fields:   FeatureModules::HandoffCompletion.user_fillable_fields(REGISTRATION),
          values:   handoff_entry_params,
          customer: @customer,
          errors:   result.errors
        ), status: :unprocessable_entity
      end
    rescue FeatureModules::CrossTenantViolation
      head :forbidden
    end
```

(d) Add the two private helpers (put them in the `private` section, e.g. next to `handoff_token_for_charge`):

```ruby
    # The active payment invocation, or nil after redirecting home. Mirrors the
    # guard #start used inline before collect/complete shared it.
    def require_payment_invocation
      invocation = current_invocation
      if invocation.nil? || invocation[:module_key] != "payment"
        redirect_to "/#{@customer.id}", alert: t("comp_payments.flash.no_active_request")
        return nil
      end
      invocation
    end

    # Strong-params the entry-form submission to the module's user_fillable field
    # names only — a first guard on top of HandoffCompletion's own fillable-only
    # filter (author_only keys can never reach the invocation input).
    def handoff_entry_params
      names = FeatureModules::HandoffCompletion.user_fillable_fields(REGISTRATION).map(&:name)
      params.fetch(:handoff, {}).permit(*names).to_h
    end
```

- [ ] **Step 5: Run and verify pass**

Run: `bundle exec rspec spec/requests/payments/checkout_collect_spec.rb spec/requests/payments/checkout_start_spec.rb`
Expected: PASS. (Note: `checkout_start_spec` currently asserts `#start` materializes immediately with an input that has NO fillable value — but Payment now always diverts to `#collect`. **This is an intentional behavior change; the stale start-spec examples must be updated,** per the stale-test policy — see Step 6.)

- [ ] **Step 6: Update the now-stale `checkout_start_spec`.** Payment always diverts to `#collect` now, so the three `#start` examples that assert immediate order materialization are stale. Rewrite them to assert the divert, OR move the materialization assertions to `checkout_collect_spec` via `#complete`. Concretely, in `spec/requests/payments/checkout_start_spec.rb` replace the first example ("materializes an order …") body with:

```ruby
  it "diverts to the collect step (payment has a user_fillable field)" do
    stub_invocation(input: input)
    get start_path
    expect(response).to redirect_to("/#{customer.id}/payments/checkout/collect")
    expect(Payments::Order.count).to eq(0)
  end
```

Delete the two idempotency/pre-existing-order `#start` examples (idempotency is now exercised through `#complete`; add an equivalent idempotency example to `checkout_collect_spec` if desired). Keep the "no active invocation" and "cross-tenant" examples as-is (still valid). Re-run:

Run: `bundle exec rspec spec/requests/payments/checkout_start_spec.rb spec/requests/payments/checkout_collect_spec.rb`
Expected: PASS.

- [ ] **Step 7: Checkpoint (NO COMMIT).**

---

### Task 8: Full targeted verification + i18n parity

**Files:** none (verification only).

- [ ] **Step 1: Run every touched spec together**

Run:
```bash
bundle exec rspec \
  spec/services/feature_modules/base_module_spec.rb \
  spec/services/feature_modules/handoff_field_spec.rb \
  spec/services/feature_modules/invocation_spec.rb \
  spec/services/feature_modules/handoff_completion_spec.rb \
  spec/services/feature_modules/payment/registration_spec.rb \
  spec/contracts/feature_module_handoff_contract_spec.rb \
  spec/components/payments/handoff_entry_component_spec.rb \
  spec/requests/payments/checkout_start_spec.rb \
  spec/requests/payments/checkout_collect_spec.rb \
  spec/requests/payments/checkouts_spec.rb
```
Expected: all PASS (0 failures). (Omit `handoff_field_spec.rb` from the list if it was not created — Task 1 folds those assertions into `base_module_spec`.)

- [ ] **Step 2: Verify en/zh locale parity for the new keys.** Confirm both files carry the identical `comp_payments.handoff_entry` key set:

Run: `bundle exec ruby -ryaml -e 'en=YAML.load_file("config/locales/comp_payments.en.yml").dig("en","comp_payments","handoff_entry"); zh=YAML.load_file("config/locales/comp_payments.zh-CN.yml").dig("zh-CN","comp_payments","handoff_entry"); require "set"; def leaves(h,p="") ; h.flat_map{|k,v| v.is_a?(Hash) ? leaves(v,"#{p}#{k}.") : ["#{p}#{k}"]}; end; a=leaves(en).sort; b=leaves(zh).sort; puts(a==b ? "PARITY OK: #{a.join(", ")}" : "MISMATCH\nen=#{a}\nzh=#{b}")'`
Expected: `PARITY OK: continue, fields.body.label, fields.body.placeholder, subtitle, title`

- [ ] **Step 3: Sanity-check no hard-coded strings were introduced.** Confirm the new component/controller code routes all user-facing text through `t(...)`:

Run: `grep -nE '"[A-Z][a-z].*"' app/components/payments/handoff_entry_component.html.erb app/components/payments/handoff_entry_component.rb`
Expected: no user-facing English literals (only Tailwind class strings / `t(...)` keys).

- [ ] **Step 4: Final checkpoint (NO COMMIT).** Report PASS with the spec summary. Leave all changes uncommitted in the working tree on `master`.

---

## Self-Review Notes

- **Spec coverage:** DSL `source:` (T1) · HandoffField predicates/to_h (T1) · author-time relaxation both directions (T2) · `update_input!` write/no-op/cross-tenant (T3) · completion guard/cast/merge/validate (T4) · Payment field policy (T5) · component render/prefill/errors/zh (T6) · start-divert/collect/complete/tamper-guard/no-invocation/cross-tenant (T7) · integrated run + i18n parity (T8). Every spec section in the design maps to a task.
- **Trust model:** money/identity stay `author_only`; injected `amount_cents` dropped at two layers (controller `permit(*fillable)` + service `slice(fillable_names)`) and asserted in T7.
- **No new JS** → no Vitest obligation; if that changes during build, add the suite to hit 100% lines/branches.
- **Legacy path:** a module with no user_fillable fields → `needs_completion?` false → `#start` unchanged. Only Payment changes, and its change is the intentional divert covered by the T7 stale-spec rewrite.
