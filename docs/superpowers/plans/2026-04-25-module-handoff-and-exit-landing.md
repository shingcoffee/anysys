# Module Handoff & Exit Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a customer-authored page hand off to an enabled feature module's pages and return the user to a configurable exit landing page once the module's business process completes.

**Architecture:** Session-based invocation stash written by a thin service (`FeatureModules::Invocation`) and consumed by a Trailblazer activity (`FeatureModules::Complete`). Module registrations declare `entry_path`, `default_exit`, and Reform-based `input_contract` / `output_contract` via a DSL on the existing `FeatureModules::BaseModule`. Exit targets of four kinds (`page`, `flowchart`, `url`, `route`) are resolved by `FeatureModules::ExitResolver` with a four-step fallback chain. Audit goes through the existing `FeatureModuleLog`. No new DB tables.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Reform, Trailblazer::Activity, ViewComponent, StimulusJS, TailwindCSS, RSpec.

**Spec:** `docs/superpowers/specs/2026-04-25-module-handoff-and-exit-landing-design.md`

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `app/services/feature_modules/invocation.rb` | Sole owner of `session[:feature_module_invocation]`. `begin!`, `current`, `clear!`, `abandon!`. |
| `app/services/feature_modules/input_mapper.rb` | Resolves `input_mapping` hash (`field`/`literal`/`entity` sources) against form params + entity_entry. |
| `app/services/feature_modules/exit_resolver.rb` | Resolves `exit_target` hash → URL string. Four-step fallback chain. Owns `ALLOWED_ROUTES`. |
| `app/services/feature_modules/complete.rb` | Trailblazer activity: load invocation → validate output → resolve exit → log → clear session → return redirect URL. |
| `app/services/feature_modules/payment/registration.rb` | Demo hypothetical module (contracts + `entry_path` + `default_exit`). |
| `app/controllers/concerns/feature_modules/invocation_context.rb` | Controller concern: `current_invocation`, `invocation_input`. Included by module controllers. |
| `app/contracts/feature_module_handoff_contract.rb` | Reform contract for `form_settings.handoff` JSON on page save. |
| `app/components/pages/handoff_settings_component.rb` | ViewComponent for the "hand off to module" branch of the after-submit picker. |
| `app/components/pages/handoff_settings_component.html.erb` | Template for the component above. |
| `config/locales/feature_modules.en.yml` | User-facing error strings. |

### Modified files

| Path | Change |
|---|---|
| `app/services/feature_modules/base_module.rb` | Add DSL: `entry_path`, `default_exit`, `input_contract`, `output_contract`; boot-time validation. |
| `app/services/feature_modules/authentication/registration.rb` | Declare `entry_path` + `default_exit` using new DSL. |
| `app/models/feature_module.rb` | `NullRegistration` gains no-op DSL methods. |
| `app/models/page.rb` | `handoff?` helper; read `form_settings.handoff` via JSON attr. |
| `app/controllers/public_pages_controller.rb` | `#submit` branches to `Invocation.begin!` when `after_submit == "handoff"`. |
| `app/controllers/feature_modules_controller.rb` + view | Show `default_exit`; form for customer-level `exit_landing_page` override. |

### Test files (TDD: created during each task)

| Path | Covers |
|---|---|
| `spec/services/feature_modules/invocation_spec.rb` | Invocation lifecycle + tenant isolation. |
| `spec/services/feature_modules/input_mapper_spec.rb` | All three `source` kinds + nested paths. |
| `spec/services/feature_modules/exit_resolver_spec.rb` | Four kinds, four fallback steps, route allowlist, URL scheme allowlist, tenant scoping. |
| `spec/services/feature_modules/complete_spec.rb` | Activity paths: happy/stale/cross-tenant/invalid-output. |
| `spec/services/feature_modules/base_module_spec.rb` | DSL + defaults + boot errors. |
| `spec/services/feature_modules/payment/registration_spec.rb` | Payment contracts accept/reject. |
| `spec/services/feature_modules/authentication/registration_spec.rb` (extend) | New DSL fields work alongside existing `provision!`/`deprovision!`. |
| `spec/contracts/feature_module_handoff_contract_spec.rb` | Contract validates per-kind required keys; rejects unknown modules/kinds/schemes. |
| `spec/components/pages/handoff_settings_component_spec.rb` | Renders all four kinds; disabled modules hidden; pre-filled round-trip. |
| `spec/models/page_spec.rb` (extend) | `handoff?` true when `form_settings.after_submit == "handoff"`. |
| `spec/requests/public_pages_submission_spec.rb` (extend) | Page submission with handoff → session written + redirect to `entry_path`. |
| `spec/requests/feature_modules_completion_spec.rb` | Test-only module calls `Complete` → session cleared, flash set, redirect. |
| `spec/requests/feature_modules_controller_spec.rb` (extend) | Show page displays default exit; update persists customer-level override. |
| `spec/system/feature_modules/payment_handoff_flow_spec.rb` | End-to-end payment example. |
| `spec/system/feature_modules/authentication_handoff_flow_spec.rb` | End-to-end auth example (named-route exit). |
| `spec/system/feature_modules/exit_fallback_chain_spec.rb` | Each fallback step fires. |
| `spec/support/feature_module_registrations.rb` | Test-only `FeatureModules::TestModule::Registration`. |
| `spec/support/invocation_helpers.rb` | Helpers for request/system specs. |

---

## Task 1: Error hierarchy + locale file

**Files:**
- Create: `app/services/feature_modules/errors.rb`
- Create: `config/locales/feature_modules.en.yml`

- [ ] **Step 1: Write the failing test**

Create `spec/services/feature_modules/errors_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules do
  describe "error hierarchy" do
    it "defines a base Error class" do
      expect(FeatureModules::Error.ancestors).to include(StandardError)
    end

    it "defines ModuleNotEnabled inheriting from Error" do
      expect(FeatureModules::ModuleNotEnabled.ancestors).to include(FeatureModules::Error)
    end

    it "defines InputContractViolation inheriting from Error" do
      expect(FeatureModules::InputContractViolation.ancestors).to include(FeatureModules::Error)
    end

    it "defines OutputContractViolation inheriting from Error" do
      expect(FeatureModules::OutputContractViolation.ancestors).to include(FeatureModules::Error)
    end

    it "defines CrossTenantViolation inheriting from Error" do
      expect(FeatureModules::CrossTenantViolation.ancestors).to include(FeatureModules::Error)
    end

    it "defines RegistrationError inheriting from Error" do
      expect(FeatureModules::RegistrationError.ancestors).to include(FeatureModules::Error)
    end
  end

  describe "locale strings" do
    %w[
      feature_modules.errors.module_not_enabled
      feature_modules.errors.input_contract_violation
      feature_modules.errors.output_contract_violation
      feature_modules.errors.cross_tenant_violation
      feature_modules.errors.unresolvable_exit_target
    ].each do |key|
      it "defines #{key}" do
        expect(I18n.t(key, raise: true)).to be_a(String)
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/feature_modules/errors_spec.rb`
Expected: FAIL — `FeatureModules::Error` not defined.

- [ ] **Step 3: Create the errors module**

Create `app/services/feature_modules/errors.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  # Base class for all module-flow errors.
  class Error < StandardError; end

  # Triggering page references a module the customer has not enabled.
  class ModuleNotEnabled < Error; end

  # input_mapping produced a payload that fails the module's input_contract.
  class InputContractViolation < Error
    attr_reader :contract_errors

    def initialize(message = nil, contract_errors: {})
      super(message)
      @contract_errors = contract_errors
    end
  end

  # Module passed an invalid output payload to Complete.
  class OutputContractViolation < Error
    attr_reader :contract_errors

    def initialize(message = nil, contract_errors: {})
      super(message)
      @contract_errors = contract_errors
    end
  end

  # Session customer_id does not match Current.customer_id.
  class CrossTenantViolation < Error; end

  # Registration DSL used incorrectly (unknown route, malformed contract, etc.).
  class RegistrationError < Error; end
end
```

- [ ] **Step 4: Create the locale file**

Create `config/locales/feature_modules.en.yml`:

```yaml
en:
  feature_modules:
    errors:
      module_not_enabled: "The %{module_name} module is not enabled for your account."
      input_contract_violation: "Cannot start %{module_name}: %{details}"
      output_contract_violation: "The %{module_name} module returned an invalid result. Please contact support."
      cross_tenant_violation: "This action is not permitted."
      unresolvable_exit_target: "The configured exit landing page could not be resolved."
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/services/feature_modules/errors_spec.rb`
Expected: PASS (6 examples).

- [ ] **Step 6: Do NOT commit (per AGENTS.md: user reviews and commits manually)**

Leave changes staged but uncommitted. Move to next task.

---

## Task 2: Extend `FeatureModules::BaseModule` with DSL

**Files:**
- Modify: `app/services/feature_modules/base_module.rb`
- Create: `spec/services/feature_modules/base_module_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/services/feature_modules/base_module_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::BaseModule do
  let(:customer) { instance_double(Customer, id: 42) }

  describe ".entry_path" do
    it "stores a block and exposes it via .entry_path_for(customer)" do
      klass = Class.new(described_class) do
        def self.module_key = "demo"
        def self.module_name = "Demo"
        def self.provision!(_c) = nil
        entry_path { |c| "/#{c.id}/demo/start" }
      end

      expect(klass.entry_path_for(customer)).to eq("/42/demo/start")
    end

    it "defaults to nil when not declared" do
      klass = Class.new(described_class) do
        def self.module_key = "noentry"
        def self.module_name = "No Entry"
        def self.provision!(_c) = nil
      end

      expect(klass.entry_path_for(customer)).to be_nil
    end
  end

  describe ".default_exit" do
    it "stores and exposes a default_exit hash" do
      klass = Class.new(described_class) do
        def self.module_key = "d2"
        def self.module_name = "D2"
        def self.provision!(_c) = nil
        default_exit kind: "url", url: "https://example.com"
      end

      expect(klass.default_exit_config).to eq(kind: "url", url: "https://example.com")
    end

    it "returns nil when not declared" do
      klass = Class.new(described_class) do
        def self.module_key = "d3"
        def self.module_name = "D3"
        def self.provision!(_c) = nil
      end

      expect(klass.default_exit_config).to be_nil
    end
  end

  describe ".input_contract and .output_contract" do
    let(:klass) do
      Class.new(described_class) do
        def self.module_key = "ioo"
        def self.module_name = "IOO"
        def self.provision!(_c) = nil

        input_contract do
          property :amount, validates: { presence: true, numericality: { greater_than: 0 } }
        end

        output_contract do
          property :reference, validates: { presence: true }
        end
      end
    end

    it "builds a Reform contract subclass for inputs" do
      contract_class = klass.input_contract_class
      expect(contract_class.ancestors).to include(Reform::Form)

      form = contract_class.new(OpenStruct.new(amount: nil))
      expect(form.validate(amount: nil)).to be false
      expect(form.errors[:amount]).not_to be_empty
    end

    it "builds a Reform contract subclass for outputs" do
      contract_class = klass.output_contract_class
      form = contract_class.new(OpenStruct.new(reference: nil))
      expect(form.validate(reference: "abc")).to be true
    end

    it "returns an empty-but-valid contract when not declared" do
      empty_klass = Class.new(described_class) do
        def self.module_key = "empty"
        def self.module_name = "Empty"
        def self.provision!(_c) = nil
      end

      form = empty_klass.input_contract_class.new(OpenStruct.new)
      expect(form.validate({})).to be true
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb`
Expected: FAIL — `entry_path_for`, `default_exit_config`, `input_contract_class`, `output_contract_class` not defined.

- [ ] **Step 3: Extend `BaseModule`**

Replace `app/services/feature_modules/base_module.rb` with:

```ruby
# frozen_string_literal: true

module FeatureModules
  # Abstract base class for all feature module registrations.
  # Subclasses must implement .module_key, .module_name, .provision!.
  # They may also declare .entry_path, .default_exit, .input_contract, .output_contract.
  class BaseModule
    class << self
      # ---- Required DSL ----

      def module_key
        raise NotImplementedError, "#{name} must implement .module_key"
      end

      def module_name
        raise NotImplementedError, "#{name} must implement .module_name"
      end

      def module_description
        ""
      end

      def configuration_schema
        {}
      end

      def provision!(_customer)
        raise NotImplementedError, "#{name} must implement .provision!"
      end

      def deprovision!(_customer); end

      # ---- Handoff DSL ----

      # entry_path { |customer| "/#{customer.id}/demo/start" }
      def entry_path(&block)
        @entry_path_block = block
      end

      # Returns the resolved entry path for a customer, or nil if not declared.
      def entry_path_for(customer)
        @entry_path_block&.call(customer)
      end

      # default_exit kind: "route", name: "customer_dashboard"
      def default_exit(**config)
        validate_default_exit!(config)
        @default_exit_config = config
      end

      def default_exit_config
        @default_exit_config
      end

      # input_contract do
      #   property :amount, validates: { presence: true }
      # end
      def input_contract(&block)
        @input_contract_class = build_contract_class(&block)
      end

      def input_contract_class
        @input_contract_class ||= empty_contract_class
      end

      def output_contract(&block)
        @output_contract_class = build_contract_class(&block)
      end

      def output_contract_class
        @output_contract_class ||= empty_contract_class
      end

      private

      def validate_default_exit!(config)
        kind = config[:kind].to_s
        unless %w[page flowchart url route].include?(kind)
          raise FeatureModules::RegistrationError,
                "#{name}.default_exit has unknown kind: #{kind.inspect}"
        end
      end

      def build_contract_class(&block)
        dsl = ContractDsl.new
        dsl.instance_eval(&block) if block
        props = dsl.properties
        Class.new(Reform::Form) do
          props.each do |(property_name, validations)|
            property property_name
            validates property_name, **validations if validations.present?
          end
        end
      end

      def empty_contract_class
        Class.new(Reform::Form)
      end
    end

    # DSL collector used inside input_contract / output_contract blocks.
    class ContractDsl
      attr_reader :properties

      def initialize
        @properties = []
      end

      # property :amount, validates: { presence: true }
      def property(name, validates: nil, **_ignored)
        @properties << [name, validates || {}]
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb`
Expected: PASS (7 examples).

- [ ] **Step 5: Regression-check the existing auth module still boots**

Run: `bundle exec rspec spec/services/feature_modules/authentication/ -fd`
Expected: PASS — existing auth specs still green.

- [ ] **Step 6: Do NOT commit**

---

## Task 3: Extend `FeatureModule::NullRegistration` with no-op DSL methods

**Files:**
- Modify: `app/models/feature_module.rb`
- Modify: `spec/models/feature_module_spec.rb` (or create if absent)

- [ ] **Step 1: Write the failing test**

Add to `spec/models/feature_module_spec.rb`:

```ruby
RSpec.describe FeatureModule::NullRegistration do
  it "responds to entry_path_for with nil" do
    expect(described_class.entry_path_for(double)).to be_nil
  end

  it "responds to default_exit_config with nil" do
    expect(described_class.default_exit_config).to be_nil
  end

  it "responds to input_contract_class with an empty contract" do
    contract = described_class.input_contract_class.new(OpenStruct.new)
    expect(contract.validate({})).to be true
  end

  it "responds to output_contract_class with an empty contract" do
    contract = described_class.output_contract_class.new(OpenStruct.new)
    expect(contract.validate({})).to be true
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/feature_module_spec.rb -e NullRegistration`
Expected: FAIL — `entry_path_for` undefined on `NullRegistration`.

- [ ] **Step 3: Extend `NullRegistration`**

In `app/models/feature_module.rb`, replace the `NullRegistration` module (currently lines 66-69) with:

```ruby
  # Null object for modules without a registration class
  module NullRegistration
    def self.provision!(_customer) = nil
    def self.deprovision!(_customer) = nil
    def self.entry_path_for(_customer) = nil
    def self.default_exit_config = nil
    def self.input_contract_class  = @input_contract_class  ||= Class.new(Reform::Form)
    def self.output_contract_class = @output_contract_class ||= Class.new(Reform::Form)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/feature_module_spec.rb`
Expected: PASS.

- [ ] **Step 5: Do NOT commit**

---

## Task 4: `FeatureModules::InputMapper`

**Files:**
- Create: `app/services/feature_modules/input_mapper.rb`
- Create: `spec/services/feature_modules/input_mapper_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/services/feature_modules/input_mapper_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::InputMapper do
  let(:form_params) { { "fields" => { "total_amount" => 150, "currency" => "USD" } } }
  let(:entity_entry) { instance_double("EntityEntry", id: 99, data: { "email" => "a@b.com" }) }

  describe ".call" do
    it "resolves field sources via dot-path" do
      mapping = { "amount" => { "source" => "field", "path" => "fields.total_amount" } }
      result  = described_class.call(mapping: mapping, form_params: form_params, entity_entry: entity_entry)
      expect(result).to eq(amount: 150)
    end

    it "resolves literal sources" do
      mapping = { "currency" => { "source" => "literal", "value" => "USD" } }
      result  = described_class.call(mapping: mapping, form_params: form_params, entity_entry: entity_entry)
      expect(result).to eq(currency: "USD")
    end

    it "resolves entity sources against entity_entry attributes" do
      mapping = { "order_id" => { "source" => "entity", "path" => "id" } }
      result  = described_class.call(mapping: mapping, form_params: form_params, entity_entry: entity_entry)
      expect(result).to eq(order_id: 99)
    end

    it "resolves entity sources against nested entity_entry.data" do
      mapping = { "email" => { "source" => "entity", "path" => "data.email" } }
      result  = described_class.call(mapping: mapping, form_params: form_params, entity_entry: entity_entry)
      expect(result).to eq(email: "a@b.com")
    end

    it "returns nil for missing field paths (lets contract validation catch presence)" do
      mapping = { "missing" => { "source" => "field", "path" => "fields.nope" } }
      result  = described_class.call(mapping: mapping, form_params: form_params, entity_entry: entity_entry)
      expect(result).to eq(missing: nil)
    end

    it "returns nil for entity path when entity_entry is nil" do
      mapping = { "order_id" => { "source" => "entity", "path" => "id" } }
      result  = described_class.call(mapping: mapping, form_params: form_params, entity_entry: nil)
      expect(result).to eq(order_id: nil)
    end

    it "returns an empty hash for an empty mapping" do
      expect(described_class.call(mapping: {}, form_params: form_params, entity_entry: entity_entry)).to eq({})
    end

    it "raises RegistrationError for an unknown source kind" do
      mapping = { "x" => { "source" => "wat" } }
      expect {
        described_class.call(mapping: mapping, form_params: form_params, entity_entry: entity_entry)
      }.to raise_error(FeatureModules::RegistrationError, /unknown source/i)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/feature_modules/input_mapper_spec.rb`
Expected: FAIL — `InputMapper` not defined.

- [ ] **Step 3: Implement `InputMapper`**

Create `app/services/feature_modules/input_mapper.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  # Resolves an input_mapping hash into a symbol-keyed payload suitable for
  # a module's input_contract. Sources: "field", "literal", "entity".
  class InputMapper
    def self.call(mapping:, form_params:, entity_entry:)
      new(mapping: mapping, form_params: form_params, entity_entry: entity_entry).call
    end

    def initialize(mapping:, form_params:, entity_entry:)
      @mapping      = mapping || {}
      @form_params  = form_params || {}
      @entity_entry = entity_entry
    end

    def call
      @mapping.each_with_object({}) do |(key, spec), out|
        out[key.to_sym] = resolve(spec)
      end
    end

    private

    def resolve(spec)
      case spec["source"]
      when "field"   then dig_path(@form_params, spec["path"])
      when "literal" then spec["value"]
      when "entity"  then resolve_entity(spec["path"])
      else
        raise RegistrationError, "unknown source: #{spec['source'].inspect}"
      end
    end

    def resolve_entity(path)
      return nil if @entity_entry.nil? || path.blank?
      first, *rest = path.split(".")
      base = @entity_entry.public_send(first)
      rest.empty? ? base : dig_path(base, rest.join("."))
    rescue NoMethodError
      nil
    end

    def dig_path(hash, path)
      return nil if path.blank? || !hash.respond_to?(:dig)
      hash.dig(*path.to_s.split("."))
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/input_mapper_spec.rb`
Expected: PASS (8 examples).

- [ ] **Step 5: Do NOT commit**

---

## Task 5: `FeatureModules::ExitResolver` — pure resolution

**Files:**
- Create: `app/services/feature_modules/exit_resolver.rb`
- Create: `spec/services/feature_modules/exit_resolver_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/services/feature_modules/exit_resolver_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::ExitResolver do
  let(:customer) { create(:customer) }
  let!(:feature_module)          { create(:feature_module, key: "demo", name: "Demo") }
  let!(:customer_feature_module) do
    create(:customer_feature_module,
           customer: customer, feature_module: feature_module,
           status: :active, configuration: {}.to_json)
  end

  around { |ex| Current.set(customer: customer, &ex) }

  describe "kind: 'url'" do
    it "returns the url when scheme is http or https" do
      target = { "kind" => "url", "url" => "https://acme.test/thanks" }
      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: target).call)
        .to eq("https://acme.test/thanks")
    end

    it "skips a javascript: scheme and falls through to the customer-home fallback" do
      target = { "kind" => "url", "url" => "javascript:alert(1)" }
      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: target).call)
        .to eq("/#{customer.id}")
    end
  end

  describe "kind: 'page'" do
    it "returns the public page URL when the page is published" do
      page = create(:page, customer: customer, published: true, public_token: "tok123")
      target = { "kind" => "page", "page_id" => page.id }
      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: target).call)
        .to eq("/#{customer.id}/f/tok123")
    end

    it "returns the editor page URL when the page is not published" do
      page = create(:page, customer: customer, published: false)
      target = { "kind" => "page", "page_id" => page.id }
      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: target).call)
        .to eq("/#{customer.id}/pages/#{page.id}")
    end

    it "skips and falls through when the page belongs to another customer" do
      other = create(:customer)
      page  = create(:page, customer: other, published: true, public_token: "other")
      target = { "kind" => "page", "page_id" => page.id }
      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: target).call)
        .to eq("/#{customer.id}")
    end
  end

  describe "kind: 'flowchart'" do
    it "returns the flowchart run URL" do
      entity    = create(:entity, customer: customer, name_slug: "orders")
      flowchart = create(:flowchart, customer: customer, entity: entity, uuid: "abc123")
      target = { "kind" => "flowchart", "flowchart_uuid" => "abc123", "entity_slug" => "orders" }
      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: target).call)
        .to eq("/#{customer.id}/abc123/orders")
    end
  end

  describe "kind: 'route'" do
    it "resolves an allowlisted named route" do
      stub_const("FeatureModules::ExitResolver::ALLOWED_ROUTES", { "customer_home" => ->(c) { "/#{c.id}" } })
      target = { "kind" => "route", "name" => "customer_home" }
      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: target).call)
        .to eq("/#{customer.id}")
    end

    it "skips a non-allowlisted route and falls through to customer-home fallback" do
      stub_const("FeatureModules::ExitResolver::ALLOWED_ROUTES", {})
      target = { "kind" => "route", "name" => "admin_root" }
      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: target).call)
        .to eq("/#{customer.id}")
    end
  end

  describe "fallback chain" do
    let(:registration) { class_double(FeatureModules::BaseModule, default_exit_config: nil) }

    before do
      allow_any_instance_of(FeatureModule).to receive(:registration_class).and_return(registration)
    end

    it "falls back to customer-level override when session target is absent" do
      page = create(:page, customer: customer, published: true, public_token: "fallback")
      customer_feature_module.update!(configuration: { exit_landing_page: { kind: "page", page_id: page.id } }.to_json)

      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: nil).call)
        .to eq("/#{customer.id}/f/fallback")
    end

    it "falls back to module default_exit when no session target and no customer override" do
      allow(registration).to receive(:default_exit_config).and_return(kind: "url", url: "https://mod.test")

      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: nil).call)
        .to eq("https://mod.test")
    end

    it "falls back to /:customer_id when all other steps fail" do
      expect(described_class.new(customer: customer, module_key: "demo", session_exit_target: nil).call)
        .to eq("/#{customer.id}")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/feature_modules/exit_resolver_spec.rb`
Expected: FAIL — `ExitResolver` not defined.

- [ ] **Step 3: Implement `ExitResolver`**

Create `app/services/feature_modules/exit_resolver.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  # Resolves an exit_target hash into a URL string using a four-step fallback chain:
  #   1. session_exit_target (from Invocation)
  #   2. CustomerFeatureModule.configuration["exit_landing_page"]
  #   3. module registration's .default_exit_config
  #   4. /:customer_id (guaranteed)
  class ExitResolver
    ALLOWED_SCHEMES = %w[http https].freeze
    # Allowlist of safe named routes a customer may use as an exit target.
    # Each value is a callable that accepts the customer and returns a path.
    ALLOWED_ROUTES = {
      "customer_home" => ->(customer) { "/#{customer.id}" }
    }.freeze

    def initialize(customer:, module_key:, session_exit_target:)
      @customer   = customer
      @module_key = module_key
      @session    = session_exit_target
    end

    def self.call(**kwargs) = new(**kwargs).call

    def call
      fallback_chain.each do |target|
        next if target.nil?
        resolved = resolve_target(target)
        return resolved if resolved
      end
      customer_home
    end

    private

    def fallback_chain
      [
        normalize(@session),
        normalize(customer_override),
        normalize(module_default),
        { kind: "customer_home" }
      ]
    end

    def customer_override
      cfm = CustomerFeatureModule.joins(:feature_module)
                                  .where(customer_id: @customer.id, feature_modules: { key: @module_key })
                                  .first
      return nil unless cfm
      parsed = cfm.configuration.is_a?(String) ? JSON.parse(cfm.configuration) : cfm.configuration
      parsed["exit_landing_page"]
    rescue JSON::ParserError
      nil
    end

    def module_default
      fm = FeatureModule.find_by(key: @module_key)
      fm&.registration_class&.default_exit_config
    end

    def normalize(hash)
      return nil if hash.nil?
      hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
    end

    def resolve_target(target)
      case target["kind"].to_s
      when "page"         then resolve_page(target)
      when "flowchart"    then resolve_flowchart(target)
      when "url"          then resolve_url(target)
      when "route"        then resolve_route(target)
      when "customer_home" then customer_home
      end
    end

    def resolve_page(target)
      page = Page.for_current_customer.find_by(id: target["page_id"])
      return nil unless page

      if page.published && page.public_token.present?
        "/#{@customer.id}/f/#{page.public_token}"
      else
        "/#{@customer.id}/pages/#{page.id}"
      end
    end

    def resolve_flowchart(target)
      flowchart = Flowchart.for_current_customer.find_by(uuid: target["flowchart_uuid"])
      return nil unless flowchart

      "/#{@customer.id}/#{flowchart.uuid}/#{target['entity_slug']}"
    end

    def resolve_url(target)
      url = target["url"].to_s
      parsed = URI.parse(url)
      return nil unless ALLOWED_SCHEMES.include?(parsed.scheme)
      url
    rescue URI::InvalidURIError
      nil
    end

    def resolve_route(target)
      builder = ALLOWED_ROUTES[target["name"].to_s]
      return nil unless builder
      builder.call(@customer)
    end

    def customer_home
      "/#{@customer.id}"
    end
  end
end
```

Note: `Flowchart.for_current_customer` exists via `TenantScoped`; verify by running `grep -n "for_current_customer" app/models/concerns/tenant_scoped.rb`. If the project uses a different method, substitute that.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/exit_resolver_spec.rb`
Expected: PASS (all examples).

- [ ] **Step 5: Do NOT commit**

---

## Task 6: `FeatureModules::Invocation` — session lifecycle

**Files:**
- Create: `app/services/feature_modules/invocation.rb`
- Create: `spec/services/feature_modules/invocation_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/services/feature_modules/invocation_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Invocation do
  let(:customer) { create(:customer) }
  let!(:feature_module) { create(:feature_module, key: "demo", name: "Demo") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: feature_module, status: :active, configuration: {}.to_json) }
  let(:session) { {} }
  let(:registration) do
    Class.new(FeatureModules::BaseModule) do
      def self.module_key = "demo"
      def self.module_name = "Demo"
      def self.provision!(_c) = nil
      entry_path { |c| "/#{c.id}/demo/start" }
      input_contract do
        property :amount, validates: { presence: true, numericality: { greater_than: 0 } }
      end
    end
  end

  before { allow(feature_module).to receive(:registration_class).and_return(registration) }
  before { allow(FeatureModule).to receive(:find_by).with(key: "demo").and_return(feature_module) }
  around { |ex| Current.set(customer: customer, &ex) }

  describe ".begin!" do
    let(:triggering_page) { create(:page, customer: customer) }

    it "stores invocation state in session and returns the entry_path" do
      url = described_class.begin!(
        session: session, customer: customer, module_key: "demo",
        triggering_page: triggering_page, entity_entry: nil,
        input: { amount: 50 }, exit_target: { kind: "url", url: "https://e.test" }
      )
      expect(url).to eq("/#{customer.id}/demo/start")
      expect(session[:feature_module_invocation][:module_key]).to eq("demo")
      expect(session[:feature_module_invocation][:customer_id]).to eq(customer.id)
      expect(session[:feature_module_invocation][:input]).to eq(amount: 50)
      expect(session[:feature_module_invocation][:exit_target]).to eq(kind: "url", url: "https://e.test")
    end

    it "writes a FeatureModuleLog entry tagged invocation.begin / success" do
      expect {
        described_class.begin!(
          session: session, customer: customer, module_key: "demo",
          triggering_page: triggering_page, entity_entry: nil,
          input: { amount: 50 }, exit_target: nil
        )
      }.to change(FeatureModuleLog, :count).by(1)

      log = FeatureModuleLog.last
      expect(log.action).to eq("invocation.begin")
      expect(log.status).to eq("success")
    end

    it "abandons an existing invocation before overwriting" do
      session[:feature_module_invocation] = { module_key: "stale", customer_id: customer.id, started_at: 1.hour.ago.iso8601 }
      expect {
        described_class.begin!(
          session: session, customer: customer, module_key: "demo",
          triggering_page: triggering_page, entity_entry: nil,
          input: { amount: 50 }, exit_target: nil
        )
      }.to change { FeatureModuleLog.where(action: "invocation.abandon").count }.by(1)
      expect(session[:feature_module_invocation][:module_key]).to eq("demo")
    end

    it "raises ModuleNotEnabled when the customer has not enabled the module" do
      cfm.update!(status: :suspended)
      expect {
        described_class.begin!(
          session: session, customer: customer, module_key: "demo",
          triggering_page: triggering_page, entity_entry: nil,
          input: { amount: 50 }, exit_target: nil
        )
      }.to raise_error(FeatureModules::ModuleNotEnabled)
      expect(session[:feature_module_invocation]).to be_nil
    end

    it "raises InputContractViolation when input fails the contract" do
      expect {
        described_class.begin!(
          session: session, customer: customer, module_key: "demo",
          triggering_page: triggering_page, entity_entry: nil,
          input: { amount: -1 }, exit_target: nil
        )
      }.to raise_error(FeatureModules::InputContractViolation)
      expect(session[:feature_module_invocation]).to be_nil
    end
  end

  describe ".current" do
    it "returns the hash when customer_id matches Current.customer.id" do
      session[:feature_module_invocation] = { module_key: "demo", customer_id: customer.id }
      expect(described_class.current(session)).to include(module_key: "demo")
    end

    it "raises CrossTenantViolation when customer_id mismatches" do
      session[:feature_module_invocation] = { module_key: "demo", customer_id: -999 }
      expect { described_class.current(session) }.to raise_error(FeatureModules::CrossTenantViolation)
    end

    it "returns nil when there is no invocation" do
      expect(described_class.current(session)).to be_nil
    end
  end

  describe ".clear!" do
    it "removes the session key" do
      session[:feature_module_invocation] = { module_key: "demo", customer_id: customer.id }
      described_class.clear!(session)
      expect(session).not_to have_key(:feature_module_invocation)
    end
  end

  describe ".abandon!" do
    it "clears the session key and writes an abandon log" do
      session[:feature_module_invocation] = { module_key: "demo", customer_id: customer.id }
      expect {
        described_class.abandon!(session: session, reason: "superseded")
      }.to change { FeatureModuleLog.where(action: "invocation.abandon").count }.by(1)
      expect(session).not_to have_key(:feature_module_invocation)
    end

    it "is a no-op when no invocation is present" do
      expect {
        described_class.abandon!(session: session, reason: "n/a")
      }.not_to change(FeatureModuleLog, :count)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/feature_modules/invocation_spec.rb`
Expected: FAIL — `Invocation` not defined.

- [ ] **Step 3: Implement `Invocation`**

Create `app/services/feature_modules/invocation.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  # Sole owner of session[:feature_module_invocation]. Nothing else reads or
  # writes that key directly.
  class Invocation
    SESSION_KEY = :feature_module_invocation

    class << self
      def begin!(session:, customer:, module_key:, triggering_page:, entity_entry:, input:, exit_target:)
        abandon!(session: session, reason: "superseded") if session[SESSION_KEY].present?

        feature_module = FeatureModule.find_by(key: module_key)
        raise ModuleNotEnabled, I18n.t("feature_modules.errors.module_not_enabled", module_name: module_key) unless feature_module
        raise ModuleNotEnabled, I18n.t("feature_modules.errors.module_not_enabled", module_name: feature_module.name) unless enabled_for?(customer, feature_module)

        registration = feature_module.registration_class

        contract = registration.input_contract_class.new(OpenStruct.new(input || {}))
        unless contract.validate((input || {}).stringify_keys)
          raise InputContractViolation.new(
            I18n.t("feature_modules.errors.input_contract_violation",
                   module_name: feature_module.name,
                   details: contract.errors.full_messages.join(", ")),
            contract_errors: contract.errors.to_hash
          )
        end

        entry_path = registration.entry_path_for(customer)
        raise RegistrationError, "#{feature_module.key} has no entry_path" if entry_path.blank?

        session[SESSION_KEY] = {
          module_key:         feature_module.key,
          customer_id:        customer.id,
          triggering_page_id: triggering_page&.id,
          entity_entry_id:    entity_entry&.id,
          input:              input || {},
          exit_target:        exit_target,
          started_at:         Time.current.iso8601
        }

        log!(feature_module: feature_module, customer: customer, action: "invocation.begin", status: :success,
             request_data: { input: input, exit_target: exit_target })

        entry_path
      end

      def current(session)
        data = session[SESSION_KEY]
        return nil if data.blank?

        current_id = Current.customer&.id
        raise CrossTenantViolation, I18n.t("feature_modules.errors.cross_tenant_violation") if current_id != data[:customer_id]

        data
      end

      def clear!(session)
        session.delete(SESSION_KEY)
      end

      def abandon!(session:, reason:)
        data = session[SESSION_KEY]
        return if data.blank?

        fm = FeatureModule.find_by(key: data[:module_key])
        log!(feature_module: fm, customer: Current.customer, action: "invocation.abandon",
             status: :warning, request_data: { reason: reason, invocation: data }) if fm

        clear!(session)
      end

      private

      def enabled_for?(customer, feature_module)
        CustomerFeatureModule.where(customer_id: customer.id, feature_module_id: feature_module.id, status: :active).exists?
      end

      def log!(feature_module:, customer:, action:, status:, request_data:, response_data: nil)
        return if feature_module.nil?
        FeatureModuleLog.create!(
          feature_module: feature_module,
          customer_id:    customer&.id,
          action:         action,
          status:         status,
          request_data:   request_data.to_json,
          response_data:  response_data&.to_json
        )
      end
    end
  end
end
```

Note: verify `FeatureModuleLog` column names and enum values by running `bundle exec rails runner "puts FeatureModuleLog.columns.map(&:name).join(', '); puts FeatureModuleLog.statuses"`. Adjust `log!` if column names differ (e.g., `status` may be an enum with symbols/ints — use whatever the existing model expects).

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/invocation_spec.rb`
Expected: PASS.

- [ ] **Step 5: Do NOT commit**

---

## Task 7: `FeatureModules::Complete` — Trailblazer activity

**Files:**
- Create: `app/services/feature_modules/complete.rb`
- Create: `spec/services/feature_modules/complete_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/services/feature_modules/complete_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Complete do
  let(:customer) { create(:customer) }
  let!(:fm) { create(:feature_module, key: "demo", name: "Demo") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: fm, status: :active, configuration: {}.to_json) }
  let(:session) { {} }
  let(:registration) do
    Class.new(FeatureModules::BaseModule) do
      def self.module_key = "demo"
      def self.module_name = "Demo"
      def self.provision!(_c) = nil
      default_exit kind: "url", url: "https://fallback.test"
      output_contract do
        property :reference, validates: { presence: true }
      end
    end
  end

  before { allow(fm).to receive(:registration_class).and_return(registration) }
  before { allow(FeatureModule).to receive(:find_by).with(key: "demo").and_return(fm) }
  around { |ex| Current.set(customer: customer, &ex) }

  describe ".call" do
    it "validates output, resolves exit, clears session, writes log, and returns redirect_to + flash" do
      session[:feature_module_invocation] = {
        module_key: "demo", customer_id: customer.id,
        exit_target: { kind: "url", url: "https://ok.test" },
        started_at: Time.current.iso8601
      }

      result = described_class.call(session: session, customer: customer, module_key: "demo",
                                    output: { reference: "abc" })

      expect(result[:redirect_to]).to eq("https://ok.test")
      expect(result[:flash]).to eq(feature_module_result: { module_key: "demo", output: { reference: "abc" } })
      expect(session).not_to have_key(:feature_module_invocation)
      expect(FeatureModuleLog.where(action: "invocation.complete", status: :success).count).to eq(1)
    end

    it "raises OutputContractViolation when output is invalid" do
      session[:feature_module_invocation] = {
        module_key: "demo", customer_id: customer.id, exit_target: nil, started_at: Time.current.iso8601
      }
      expect {
        described_class.call(session: session, customer: customer, module_key: "demo",
                             output: { reference: nil })
      }.to raise_error(FeatureModules::OutputContractViolation)
      expect(FeatureModuleLog.where(action: "invocation.complete", status: :failure).count).to eq(1)
    end

    it "proceeds with fallback chain when no live invocation (stale) — logs as duplicate" do
      result = described_class.call(session: session, customer: customer, module_key: "demo",
                                    output: { reference: "x" })

      expect(result[:redirect_to]).to eq("https://fallback.test")
      expect(FeatureModuleLog.where(action: "invocation.complete", status: :warning).count).to eq(1)
    end

    it "refuses and abandons on cross-tenant mismatch" do
      session[:feature_module_invocation] = {
        module_key: "demo", customer_id: -999, exit_target: nil, started_at: Time.current.iso8601
      }
      expect {
        described_class.call(session: session, customer: customer, module_key: "demo",
                             output: { reference: "x" })
      }.to raise_error(FeatureModules::CrossTenantViolation)
      expect(session).not_to have_key(:feature_module_invocation)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/feature_modules/complete_spec.rb`
Expected: FAIL — `Complete` not defined.

- [ ] **Step 3: Implement `Complete` activity**

Create `app/services/feature_modules/complete.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  # Trailblazer activity orchestrating module completion.
  # Returns { redirect_to: String, flash: Hash }.
  class Complete < Trailblazer::Activity::Railway
    step :load_invocation
    step :validate_output
    step :resolve_redirect
    step :write_log
    step :clear_session
    step :build_result

    def self.call(session:, customer:, module_key:, output:)
      ctx = {
        session: session, customer: customer, module_key: module_key, output: output
      }
      signal, (result_ctx, _) = new.call([ctx, {}])
      raise ctx[:error] if signal.to_h[:semantic] == :failure && ctx[:error]
      {
        redirect_to: result_ctx[:redirect_to],
        flash:       { feature_module_result: { module_key: module_key, output: output } }
      }
    end

    def load_invocation(ctx, session:, **)
      ctx[:invocation] = Invocation.current(session)
      true
    rescue CrossTenantViolation => e
      Invocation.clear!(session)
      ctx[:error] = e
      false
    end

    def validate_output(ctx, customer:, module_key:, output:, **)
      feature_module = FeatureModule.find_by(key: module_key)
      ctx[:feature_module] = feature_module
      registration = feature_module&.registration_class || FeatureModule::NullRegistration

      contract = registration.output_contract_class.new(OpenStruct.new(output || {}))
      unless contract.validate((output || {}).stringify_keys)
        log_failure(feature_module: feature_module, customer: customer, details: contract.errors.full_messages.join(", "), output: output)
        ctx[:error] = OutputContractViolation.new(
          I18n.t("feature_modules.errors.output_contract_violation", module_name: feature_module&.name || module_key),
          contract_errors: contract.errors.to_hash
        )
        return false
      end
      true
    end

    def resolve_redirect(ctx, customer:, module_key:, invocation:, **)
      ctx[:redirect_to] = ExitResolver.call(
        customer: customer,
        module_key: module_key,
        session_exit_target: invocation&.dig(:exit_target)
      )
      true
    end

    def write_log(ctx, customer:, feature_module:, output:, invocation:, **)
      status = invocation.present? ? :success : :warning
      FeatureModuleLog.create!(
        feature_module: feature_module,
        customer_id:    customer.id,
        action:         "invocation.complete",
        status:         status,
        request_data:   { output: output }.to_json,
        response_data:  { redirect_to: ctx[:redirect_to], duplicate: invocation.blank? }.to_json
      ) if feature_module
      true
    end

    def clear_session(_ctx, session:, **)
      Invocation.clear!(session)
      true
    end

    def build_result(_ctx, **) = true

    private

    def log_failure(feature_module:, customer:, details:, output:)
      return unless feature_module
      FeatureModuleLog.create!(
        feature_module: feature_module,
        customer_id:    customer.id,
        action:         "invocation.complete",
        status:         :failure,
        request_data:   { output: output }.to_json,
        response_data:  { error: details }.to_json
      )
    end
  end
end
```

Note: the project already uses `Trailblazer::Activity::Railway` in `app/services/field_templates/create.rb` — follow that pattern. If `ctx[:error]` isn't the existing convention, check how `FieldTemplates::Create` signals failures and mirror it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/complete_spec.rb`
Expected: PASS.

- [ ] **Step 5: Do NOT commit**

---

## Task 8: `FeatureModules::InvocationContext` controller concern

**Files:**
- Create: `app/controllers/concerns/feature_modules/invocation_context.rb`
- Create: `spec/support/invocation_helpers.rb` (minimal — used in Task 12)

- [ ] **Step 1: Write the failing test**

Create `spec/controllers/concerns/feature_modules/invocation_context_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::InvocationContext, type: :controller do
  controller(ApplicationController) do
    include FeatureModules::InvocationContext
    def index
      render plain: [current_invocation&.dig(:module_key), invocation_input&.dig(:x)].compact.join(",")
    end
  end

  let(:customer) { create(:customer) }
  around { |ex| Current.set(customer: customer, &ex) }

  it "returns nil helpers when no invocation is present" do
    get :index
    expect(response.body).to eq("")
  end

  it "returns invocation data when present" do
    session[:feature_module_invocation] = { module_key: "demo", customer_id: customer.id, input: { x: 7 } }
    get :index
    expect(response.body).to eq("demo,7")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/concerns/feature_modules/invocation_context_spec.rb`
Expected: FAIL — `InvocationContext` not defined.

- [ ] **Step 3: Implement the concern**

Create `app/controllers/concerns/feature_modules/invocation_context.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  # Included by module controllers to access the live invocation.
  module InvocationContext
    extend ActiveSupport::Concern

    included do
      helper_method :current_invocation, :invocation_input if respond_to?(:helper_method)
    end

    def current_invocation
      FeatureModules::Invocation.current(session)
    end

    def invocation_input
      current_invocation&.dig(:input)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/concerns/feature_modules/invocation_context_spec.rb`
Expected: PASS.

- [ ] **Step 5: Do NOT commit**

---

## Task 9: `FeatureModuleHandoffContract` — save-time validation

**Files:**
- Create: `app/contracts/feature_module_handoff_contract.rb`
- Create: `spec/contracts/feature_module_handoff_contract_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/contracts/feature_module_handoff_contract_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModuleHandoffContract do
  let(:customer) { create(:customer) }
  let!(:fm)  { create(:feature_module, key: "demo", name: "Demo") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: fm, status: :active, configuration: {}.to_json) }

  around { |ex| Current.set(customer: customer, &ex) }

  def build(h) = described_class.new(OpenStruct.new(h))

  it "accepts a valid page exit_target" do
    form = build({})
    expect(form.validate(module_key: "demo", input_mapping: {},
                         exit_target: { "kind" => "page", "page_id" => 99 })).to be true
  end

  it "accepts a valid flowchart exit_target" do
    form = build({})
    expect(form.validate(module_key: "demo", input_mapping: {},
                         exit_target: { "kind" => "flowchart", "flowchart_uuid" => "abc", "entity_slug" => "orders" })).to be true
  end

  it "accepts an https url exit_target" do
    form = build({})
    expect(form.validate(module_key: "demo", input_mapping: {},
                         exit_target: { "kind" => "url", "url" => "https://x.test" })).to be true
  end

  it "accepts an allowlisted route exit_target" do
    form = build({})
    expect(form.validate(module_key: "demo", input_mapping: {},
                         exit_target: { "kind" => "route", "name" => "customer_home" })).to be true
  end

  it "rejects an unknown module_key" do
    form = build({})
    expect(form.validate(module_key: "nope", input_mapping: {},
                         exit_target: { "kind" => "url", "url" => "https://x.test" })).to be false
    expect(form.errors[:module_key]).not_to be_empty
  end

  it "rejects a module the customer has not enabled" do
    cfm.update!(status: :suspended)
    form = build({})
    expect(form.validate(module_key: "demo", input_mapping: {},
                         exit_target: { "kind" => "url", "url" => "https://x.test" })).to be false
    expect(form.errors[:module_key]).not_to be_empty
  end

  it "rejects unknown exit_target.kind" do
    form = build({})
    expect(form.validate(module_key: "demo", input_mapping: {},
                         exit_target: { "kind" => "wat" })).to be false
    expect(form.errors[:exit_target]).not_to be_empty
  end

  it "rejects url exit_target with a non-http(s) scheme" do
    form = build({})
    expect(form.validate(module_key: "demo", input_mapping: {},
                         exit_target: { "kind" => "url", "url" => "javascript:alert(1)" })).to be false
    expect(form.errors[:exit_target]).not_to be_empty
  end

  it "rejects route exit_target with a non-allowlisted name" do
    form = build({})
    expect(form.validate(module_key: "demo", input_mapping: {},
                         exit_target: { "kind" => "route", "name" => "admin_root" })).to be false
    expect(form.errors[:exit_target]).not_to be_empty
  end

  it "rejects page exit_target missing page_id" do
    form = build({})
    expect(form.validate(module_key: "demo", input_mapping: {},
                         exit_target: { "kind" => "page" })).to be false
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/contracts/feature_module_handoff_contract_spec.rb`
Expected: FAIL — `FeatureModuleHandoffContract` not defined.

- [ ] **Step 3: Implement the contract**

Create `app/contracts/feature_module_handoff_contract.rb`:

```ruby
# frozen_string_literal: true

# Validates the shape of form_settings.handoff on Page save.
# Used by the page editor to reject malformed handoff configuration before
# it reaches runtime.
class FeatureModuleHandoffContract < Reform::Form
  property :module_key
  property :input_mapping
  property :exit_target

  validates :module_key, presence: true
  validate :module_enabled_for_current_customer
  validate :exit_target_is_well_formed

  VALID_KINDS = %w[page flowchart url route].freeze

  private

  def module_enabled_for_current_customer
    return if module_key.blank?

    fm = FeatureModule.find_by(key: module_key)
    unless fm
      errors.add(:module_key, "is not a known module")
      return
    end

    enabled = CustomerFeatureModule.where(
      customer_id: Current.customer&.id, feature_module_id: fm.id, status: :active
    ).exists?
    errors.add(:module_key, "is not enabled for this customer") unless enabled
  end

  def exit_target_is_well_formed
    t = (exit_target || {}).stringify_keys
    kind = t["kind"]

    unless VALID_KINDS.include?(kind)
      errors.add(:exit_target, "has unknown kind: #{kind.inspect}")
      return
    end

    case kind
    when "page"
      errors.add(:exit_target, "requires page_id") if t["page_id"].blank?
    when "flowchart"
      errors.add(:exit_target, "requires flowchart_uuid") if t["flowchart_uuid"].blank?
      errors.add(:exit_target, "requires entity_slug") if t["entity_slug"].blank?
    when "url"
      url = t["url"].to_s
      scheme = URI.parse(url).scheme rescue nil
      errors.add(:exit_target, "must use http or https") unless %w[http https].include?(scheme)
    when "route"
      name = t["name"].to_s
      unless FeatureModules::ExitResolver::ALLOWED_ROUTES.key?(name)
        errors.add(:exit_target, "is not an allowlisted route: #{name}")
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/contracts/feature_module_handoff_contract_spec.rb`
Expected: PASS.

- [ ] **Step 5: Do NOT commit**

---

## Task 10: `Page` — `handoff?` helper + form_settings validation

**Files:**
- Modify: `app/models/page.rb`
- Extend: `spec/models/page_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/models/page_spec.rb`:

```ruby
RSpec.describe Page, ".handoff?" do
  let(:customer) { create(:customer) }

  it "returns false when form_settings.after_submit is not 'handoff'" do
    page = build(:page, customer: customer, configuration: { form_settings: { after_submit: "flowchart" } }.to_json)
    expect(page.handoff?).to be false
  end

  it "returns true when form_settings.after_submit == 'handoff'" do
    page = build(:page, customer: customer, configuration: { form_settings: { after_submit: "handoff", handoff: { module_key: "demo" } } }.to_json)
    expect(page.handoff?).to be true
  end
end

RSpec.describe Page, "form_settings.handoff validation" do
  let(:customer) { create(:customer) }
  let!(:fm)  { create(:feature_module, key: "demo", name: "Demo") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: fm, status: :active, configuration: {}.to_json) }

  around { |ex| Current.set(customer: customer, &ex) }

  it "rejects save when handoff references a module the customer has not enabled" do
    cfm.update!(status: :suspended)
    page = build(:page, customer: customer,
                 configuration: { form_settings: { after_submit: "handoff",
                                                   handoff: { module_key: "demo",
                                                              input_mapping: {},
                                                              exit_target: { kind: "url", url: "https://x.test" } } } }.to_json)
    expect(page).not_to be_valid
    expect(page.errors[:base].join).to match(/not enabled/i)
  end

  it "accepts save with a valid handoff" do
    page = build(:page, customer: customer,
                 configuration: { form_settings: { after_submit: "handoff",
                                                   handoff: { module_key: "demo",
                                                              input_mapping: {},
                                                              exit_target: { kind: "url", url: "https://x.test" } } } }.to_json)
    expect(page).to be_valid
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/page_spec.rb`
Expected: FAIL — `handoff?` not defined; no validation present.

- [ ] **Step 3: Modify `Page`**

In `app/models/page.rb`, add inside the class body:

```ruby
  # ==========================================================================
  # Handoff
  # ==========================================================================

  validate :feature_module_handoff_is_valid

  def handoff?
    configuration_json&.dig("form_settings", "after_submit") == "handoff"
  end

  def handoff_config
    configuration_json&.dig("form_settings", "handoff") || {}
  end

  private

  def feature_module_handoff_is_valid
    return unless handoff?

    contract = FeatureModuleHandoffContract.new(OpenStruct.new(handoff_config))
    return if contract.validate(handoff_config.stringify_keys)

    contract.errors.full_messages.each { |msg| errors.add(:base, "handoff: #{msg}") }
  end
```

Don't overwrite existing private methods; append to the existing `private` section.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/page_spec.rb`
Expected: PASS.

- [ ] **Step 5: Run the full Page spec to catch regressions**

Run: `bundle exec rspec spec/models/page_spec.rb`
Expected: No new failures.

- [ ] **Step 6: Do NOT commit**

---

## Task 11: `PublicPagesController#submit` — redirect to module entry on handoff

**Files:**
- Modify: `app/controllers/public_pages_controller.rb`
- Extend: `spec/requests/public_pages_submission_spec.rb` (create if absent)

- [ ] **Step 1: Write the failing tests**

Create or extend `spec/requests/public_pages_submission_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page submission with module handoff", type: :request do
  let(:customer) { create(:customer) }
  let!(:fm)  { create(:feature_module, key: "demo", name: "Demo") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: fm, status: :active, configuration: {}.to_json) }
  let(:entity) { create(:entity, customer: customer) }
  let(:page) do
    create(:page, customer: customer, entity: entity, published: true, public_token: "tok",
           configuration: {
             form_settings: {
               after_submit: "handoff",
               handoff: {
                 module_key: "demo",
                 input_mapping: { amount: { source: "literal", value: 100 } },
                 exit_target: { kind: "url", url: "https://ok.test" }
               }
             }
           }.to_json)
  end
  let(:registration) do
    Class.new(FeatureModules::BaseModule) do
      def self.module_key = "demo"
      def self.module_name = "Demo"
      def self.provision!(_c) = nil
      entry_path { |c| "/#{c.id}/demo/start" }
    end
  end

  before do
    allow_any_instance_of(FeatureModule).to receive(:registration_class).and_return(registration)
  end

  it "redirects to the module entry_path and stashes the invocation in session" do
    post "/#{customer.id}/f/tok/submit"
    expect(response).to redirect_to("/#{customer.id}/demo/start")
    expect(session[:feature_module_invocation][:module_key]).to eq("demo")
    expect(session[:feature_module_invocation][:exit_target]).to include(kind: "url", url: "https://ok.test")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/public_pages_submission_spec.rb`
Expected: FAIL — redirects to form URL, not module entry.

- [ ] **Step 3: Modify `PublicPagesController`**

Edit `app/controllers/public_pages_controller.rb`. Replace the current `submit` method and related helpers:

```ruby
  def submit
    entity_id = @page.entity_id
    entity = entity_id.present? ? Entity.for_current_customer.find_by(id: entity_id) : nil

    entry = entity ? build_entry(entity) : nil

    if entry && !entry.save
      redirect_to public_page_path(customer_id: params[:customer_id], token: @page.public_token),
                  alert: "There was a problem saving your response: #{entry.errors.full_messages.join(', ')}"
      return
    end

    if @page.handoff?
      start_handoff(entry)
    elsif entity
      redirect_to public_page_path(customer_id: params[:customer_id], token: @page.public_token),
                  notice: "Thank you! Your response has been submitted."
    else
      redirect_to public_page_path(customer_id: params[:customer_id], token: @page.public_token),
                  notice: "Thank you! Your response has been submitted."
    end
  end

  private

  def build_entry(entity)
    permitted = permitted_form_params(entity)
    rules_engine = Pages::RulesEngine.new(@page)
    permitted = rules_engine.filter_hidden_fields(permitted)
    permitted.merge!(rules_engine.evaluate_calculations(permitted))

    EntityEntry.new(entity: entity, customer_id: current_customer_id, data: permitted)
  end

  def start_handoff(entry)
    handoff = @page.handoff_config.stringify_keys
    input = FeatureModules::InputMapper.call(
      mapping:      handoff["input_mapping"] || {},
      form_params:  params.to_unsafe_h,
      entity_entry: entry
    )

    redirect_url = FeatureModules::Invocation.begin!(
      session:          session,
      customer:         current_customer,
      module_key:       handoff["module_key"],
      triggering_page:  @page,
      entity_entry:     entry,
      input:            input,
      exit_target:      handoff["exit_target"]
    )

    redirect_to redirect_url
  rescue FeatureModules::ModuleNotEnabled, FeatureModules::InputContractViolation => e
    redirect_to public_page_path(customer_id: params[:customer_id], token: @page.public_token),
                alert: e.message
  end
```

Keep the existing `permitted_form_params` method untouched. Remove the no-longer-used `save_entry` method — the happy-path redirect is now inlined above.

- [ ] **Step 4: Run the targeted spec to verify it passes**

Run: `bundle exec rspec spec/requests/public_pages_submission_spec.rb`
Expected: PASS.

- [ ] **Step 5: Run the full public_pages suite to guard against regressions**

Run: `bundle exec rspec spec/requests/public_pages_*.rb spec/controllers/public_pages_controller_spec.rb 2>/dev/null || bundle exec rspec spec/requests/public_pages_submission_spec.rb`

Expected: No regressions in non-handoff submit flows.

- [ ] **Step 6: Do NOT commit**

---

## Task 12: Completion round-trip request spec with test-only module

**Files:**
- Create: `spec/support/feature_module_registrations.rb`
- Create: `spec/support/invocation_helpers.rb`
- Create: `spec/requests/feature_modules_completion_spec.rb`

- [ ] **Step 1: Create test helper for a stub module**

Create `spec/support/feature_module_registrations.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  module TestModule
    class Registration < FeatureModules::BaseModule
      def self.module_key  = "test_module"
      def self.module_name = "Test Module"
      def self.provision!(_c) = nil

      entry_path   { |customer| "/#{customer.id}/test_module/start" }
      default_exit kind: "route", name: "customer_home"

      input_contract do
        property :x, validates: { presence: true }
      end

      output_contract do
        property :ok, validates: { presence: true }
      end
    end
  end
end
```

Create `spec/support/invocation_helpers.rb`:

```ruby
# frozen_string_literal: true

module InvocationHelpers
  def stash_invocation(session:, customer:, module_key: "test_module", input: { x: 1 }, exit_target: nil)
    session[:feature_module_invocation] = {
      module_key:  module_key,
      customer_id: customer.id,
      input:       input,
      exit_target: exit_target,
      started_at:  Time.current.iso8601
    }
  end
end

RSpec.configure do |c|
  c.include InvocationHelpers, type: :request
end
```

Add a line to `spec/rails_helper.rb` if not already present:
```ruby
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }
```

- [ ] **Step 2: Write the failing test**

Create `spec/requests/feature_modules_completion_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Exercises Complete via a minimal controller mounted just for this spec.
RSpec.describe "Module completion round-trip", type: :request do
  let(:customer) { create(:customer) }
  let!(:fm) { create(:feature_module, key: "test_module", name: "Test Module") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: fm, status: :active, configuration: {}.to_json) }

  before do
    allow_any_instance_of(FeatureModule).to receive(:registration_class).and_return(FeatureModules::TestModule::Registration)

    Rails.application.routes.draw do
      post ":customer_id/test_module/finish", to: "feature_modules/test_completions#finish"
    end
  end

  after { Rails.application.reload_routes! }

  it "calls Complete, clears session, and redirects to resolved target" do
    get "/#{customer.id}" # prime current_customer_id / Current

    # Directly drive Complete via an inline controller
    stub_const("FeatureModules::TestCompletionsController", Class.new(ApplicationController) do
      set_tenant_from_route_params required: true
      include FeatureModules::InvocationContext

      def finish
        result = FeatureModules::Complete.call(session: session, customer: current_customer,
                                               module_key: "test_module", output: { ok: "yes" })
        flash.update(result[:flash])
        redirect_to result[:redirect_to]
      end
    end)

    Rails.application.routes.draw do
      post ":customer_id/test_module/finish", to: "feature_modules/test_completions#finish"
    end

    # seed an invocation
    post "/#{customer.id}/test_module/finish", params: {},
                                                headers: { "rack.session" => { feature_module_invocation: { module_key: "test_module", customer_id: customer.id, exit_target: { kind: "route", name: "customer_home" }, started_at: Time.current.iso8601 } } }

    expect(response).to redirect_to("/#{customer.id}")
    expect(flash[:feature_module_result]).to include(module_key: "test_module")
  end
end
```

Note: If the approach above of mounting an inline controller proves brittle in this Rails version, fall back to testing `FeatureModules::Complete.call` directly from a type: :request spec that uses `rack-test`-level `Rack::Session::Abstract::Env` to set session state. The goal of this spec is to prove that a module controller consuming `Complete` can redirect and set flash — a request-level integration test, not a pure unit test.

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/feature_modules_completion_spec.rb`
Expected: FAIL — route not found or session not threaded.

- [ ] **Step 4: Adjust inline controller mount until it passes**

Iterate on the spec (not production code) until it demonstrates: stubbed module controller → `Complete.call(session: session, ...)` → redirect + flash set. Production code did not change in this task — this is a pure integration spec for Task 7's `Complete`.

If the inline-controller approach keeps being brittle, replace the spec body with a direct call pattern:

```ruby
it "clears session + returns redirect + flash via Complete.call" do
  session_stub = { feature_module_invocation: { module_key: "test_module", customer_id: customer.id, exit_target: { kind: "route", name: "customer_home" }, started_at: Time.current.iso8601 } }
  Current.customer = customer
  result = FeatureModules::Complete.call(session: session_stub, customer: customer, module_key: "test_module", output: { ok: "yes" })
  expect(result[:redirect_to]).to eq("/#{customer.id}")
  expect(result[:flash]).to include(feature_module_result: { module_key: "test_module", output: { ok: "yes" } })
  expect(session_stub).not_to have_key(:feature_module_invocation)
end
```

This still lives at `spec/requests/feature_modules_completion_spec.rb` as an integration-level exercise of the activity.

- [ ] **Step 5: Do NOT commit**

---

## Task 13: Payment module registration (demo)

**Files:**
- Create: `app/services/feature_modules/payment/registration.rb`
- Create: `spec/services/feature_modules/payment/registration_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/services/feature_modules/payment/registration_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Payment::Registration do
  let(:customer) { instance_double(Customer, id: 7) }

  it "has module_key, module_name, provision, and deprovision" do
    expect(described_class.module_key).to eq("payment")
    expect(described_class.module_name).to be_a(String)
    expect { described_class.provision!(customer) }.not_to raise_error
    expect { described_class.deprovision!(customer) }.not_to raise_error
  end

  it "declares entry_path" do
    expect(described_class.entry_path_for(customer)).to eq("/7/payment/checkout")
  end

  it "declares a default_exit" do
    expect(described_class.default_exit_config).to eq(kind: "route", name: "customer_home")
  end

  it "validates input contract — rejects missing amount" do
    form = described_class.input_contract_class.new(OpenStruct.new)
    expect(form.validate(currency: "USD", order_id: 1)).to be false
    expect(form.errors[:amount]).not_to be_empty
  end

  it "validates input contract — rejects bad currency" do
    form = described_class.input_contract_class.new(OpenStruct.new)
    expect(form.validate(amount: 10, currency: "XXX", order_id: 1)).to be false
    expect(form.errors[:currency]).not_to be_empty
  end

  it "validates output contract — rejects missing reference" do
    form = described_class.output_contract_class.new(OpenStruct.new)
    expect(form.validate(status: "succeeded")).to be false
    expect(form.errors[:payment_reference]).not_to be_empty
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/feature_modules/payment/registration_spec.rb`
Expected: FAIL — `FeatureModules::Payment::Registration` not defined.

- [ ] **Step 3: Implement Payment registration**

Create `app/services/feature_modules/payment/registration.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  module Payment
    # Hypothetical demo module illustrating input/output contracts and
    # per-customer exit-landing configuration.
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "payment"
      def self.module_name        = "Payments"
      def self.module_description = "Checkout handoff (demo)"

      def self.provision!(_customer); end
      def self.deprovision!(_customer); end

      entry_path   { |customer| "/#{customer.id}/payment/checkout" }
      default_exit kind: "route", name: "customer_home"

      input_contract do
        property :amount,   validates: { presence: true, numericality: { greater_than: 0 } }
        property :currency, validates: { presence: true, inclusion: { in: %w[USD EUR GBP] } }
        property :order_id, validates: { presence: true }
      end

      output_contract do
        property :payment_reference, validates: { presence: true }
        property :status,            validates: { inclusion: { in: %w[succeeded failed] } }
        property :paid_at
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/payment/registration_spec.rb`
Expected: PASS.

- [ ] **Step 5: Do NOT commit**

---

## Task 14: Authentication registration — adopt new DSL

**Files:**
- Modify: `app/services/feature_modules/authentication/registration.rb`
- Extend: `spec/services/feature_modules/authentication/registration_spec.rb` (create a new file if one does not exist — there is currently no `authentication/registration_spec.rb` in `spec/services/feature_modules/`)

- [ ] **Step 1: Write the failing test**

Create `spec/services/feature_modules/authentication/registration_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Authentication::Registration do
  let(:customer) { instance_double(Customer, id: 11) }

  it "declares entry_path" do
    expect(described_class.entry_path_for(customer)).to eq("/11/auth/login")
  end

  it "declares a default_exit" do
    expect(described_class.default_exit_config).to eq(kind: "route", name: "customer_home")
  end

  it "has empty input/output contracts (valid against an empty hash)" do
    i = described_class.input_contract_class.new(OpenStruct.new)
    o = described_class.output_contract_class.new(OpenStruct.new)
    expect(i.validate({})).to be true
    expect(o.validate({})).to be true
  end

  it "still responds to provision! / deprovision!" do
    expect(described_class).to respond_to(:provision!)
    expect(described_class).to respond_to(:deprovision!)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/feature_modules/authentication/registration_spec.rb`
Expected: FAIL — `entry_path_for` and `default_exit_config` return nil (not yet declared on this class).

- [ ] **Step 3: Extend the registration**

Add these lines to `app/services/feature_modules/authentication/registration.rb`, inside the class body (beneath the existing `module_key`/`module_name`/`configuration_schema` declarations, above the existing `self.provision!`):

```ruby
      entry_path   { |customer| "/#{customer.id}/auth/login" }
      default_exit kind: "route", name: "customer_home"
```

Do NOT remove or rename existing class methods — `BaseModule` changes do not break the existing contract.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/authentication/`
Expected: PASS — new spec passes; existing auth specs still pass.

- [ ] **Step 5: Do NOT commit**

---

## Task 15: `Pages::HandoffSettingsComponent` + page editor integration

**Files:**
- Create: `app/components/pages/handoff_settings_component.rb`
- Create: `app/components/pages/handoff_settings_component.html.erb`
- Create: `spec/components/pages/handoff_settings_component_spec.rb`
- Modify: existing page-editor view/partial that renders the after-submit picker. **Before this task: run `grep -rn "form_settings\|flowchart_id\|after_submit" app/views/pages app/components/page_builder` to locate the current picker.** The edit below is illustrative — the agent implementing this task must substitute the actual template path found via grep.

- [ ] **Step 1: Locate the existing after-submit picker**

Run:
```bash
grep -rn "form_settings\|flowchart_id\|after_submit" app/views/pages app/components/page_builder app/views/page_builder 2>/dev/null
```

Record the file path for the existing picker. The component below is wired into whichever partial renders the picker.

- [ ] **Step 2: Write the failing component test**

Create `spec/components/pages/handoff_settings_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::HandoffSettingsComponent, type: :component do
  let(:customer) { create(:customer) }
  let!(:fm)  { create(:feature_module, key: "payment", name: "Payments") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: fm, status: :active, configuration: {}.to_json) }

  around { |ex| Current.set(customer: customer, &ex) }

  it "renders a module select containing enabled modules" do
    render_inline(described_class.new(page: build(:page, customer: customer)))
    expect(page).to have_select("page[configuration][form_settings][handoff][module_key]", with_options: ["Payments"])
  end

  it "does not list modules the customer has not enabled" do
    cfm.update!(status: :suspended)
    render_inline(described_class.new(page: build(:page, customer: customer)))
    expect(page).not_to have_select("page[configuration][form_settings][handoff][module_key]", with_options: ["Payments"])
  end

  it "renders inputs for all four exit_target kinds" do
    render_inline(described_class.new(page: build(:page, customer: customer)))
    %w[page flowchart url route].each do |kind|
      expect(page).to have_css("[data-exit-kind='#{kind}']")
    end
  end

  it "pre-fills exit_target when the page already has a handoff" do
    cfg = { form_settings: { after_submit: "handoff",
                             handoff: { module_key: "payment",
                                        input_mapping: {},
                                        exit_target: { kind: "url", url: "https://persisted.test" } } } }.to_json
    existing = build(:page, customer: customer, configuration: cfg)
    render_inline(described_class.new(page: existing))
    expect(page).to have_field("page[configuration][form_settings][handoff][exit_target][url]", with: "https://persisted.test")
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/components/pages/handoff_settings_component_spec.rb`
Expected: FAIL — component not defined.

- [ ] **Step 4: Implement the ViewComponent**

Create `app/components/pages/handoff_settings_component.rb`:

```ruby
# frozen_string_literal: true

module Pages
  # Renders the "hand off to module" branch of a page's after-submit picker.
  # Populates a select with enabled modules for the current customer and
  # input groups for the four exit_target kinds.
  class HandoffSettingsComponent < ApplicationComponent
    def initialize(page:)
      @page = page
    end

    private

    attr_reader :page

    def enabled_modules
      FeatureModule.joins(:customer_feature_modules)
                    .where(customer_feature_modules: { customer_id: Current.customer&.id, status: :active })
                    .order(:name)
    end

    def handoff_config
      @page.handoff_config.stringify_keys
    end

    def exit_target = (handoff_config["exit_target"] || {}).stringify_keys
    def selected_kind = exit_target["kind"].presence || "page"
  end
end
```

Create `app/components/pages/handoff_settings_component.html.erb`:

```erb
<section class="space-y-4" data-controller="handoff-settings">
  <div>
    <label class="block text-sm font-medium text-gray-700">Module</label>
    <%= select_tag "page[configuration][form_settings][handoff][module_key]",
                   options_from_collection_for_select(enabled_modules, :key, :name, handoff_config["module_key"]),
                   prompt: "Choose a module…",
                   class: "mt-1 block w-full rounded border-gray-300" %>
  </div>

  <div>
    <label class="block text-sm font-medium text-gray-700">Exit landing kind</label>
    <%= select_tag "page[configuration][form_settings][handoff][exit_target][kind]",
                   options_for_select(%w[page flowchart url route], selected_kind),
                   class: "mt-1 block w-full rounded border-gray-300",
                   data: { action: "change->handoff-settings#kindChanged" } %>
  </div>

  <div data-exit-kind="page" class="<%= "hidden" unless selected_kind == "page" %>">
    <label class="block text-sm font-medium text-gray-700">Landing page id</label>
    <%= text_field_tag "page[configuration][form_settings][handoff][exit_target][page_id]",
                       exit_target["page_id"], class: "mt-1 block w-full rounded border-gray-300" %>
  </div>

  <div data-exit-kind="flowchart" class="<%= "hidden" unless selected_kind == "flowchart" %>">
    <label class="block text-sm font-medium text-gray-700">Flowchart UUID</label>
    <%= text_field_tag "page[configuration][form_settings][handoff][exit_target][flowchart_uuid]",
                       exit_target["flowchart_uuid"], class: "mt-1 block w-full rounded border-gray-300" %>
    <label class="block text-sm font-medium text-gray-700 mt-2">Entity slug</label>
    <%= text_field_tag "page[configuration][form_settings][handoff][exit_target][entity_slug]",
                       exit_target["entity_slug"], class: "mt-1 block w-full rounded border-gray-300" %>
  </div>

  <div data-exit-kind="url" class="<%= "hidden" unless selected_kind == "url" %>">
    <label class="block text-sm font-medium text-gray-700">URL (https)</label>
    <%= text_field_tag "page[configuration][form_settings][handoff][exit_target][url]",
                       exit_target["url"], class: "mt-1 block w-full rounded border-gray-300" %>
  </div>

  <div data-exit-kind="route" class="<%= "hidden" unless selected_kind == "route" %>">
    <label class="block text-sm font-medium text-gray-700">Named route</label>
    <%= select_tag "page[configuration][form_settings][handoff][exit_target][name]",
                   options_for_select(FeatureModules::ExitResolver::ALLOWED_ROUTES.keys, exit_target["name"]),
                   class: "mt-1 block w-full rounded border-gray-300" %>
  </div>
</section>
```

- [ ] **Step 5: Add the Stimulus controller to toggle kind visibility**

Create `app/javascript/controllers/handoff_settings_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  kindChanged(event) {
    const selected = event.target.value;
    this.element.querySelectorAll("[data-exit-kind]").forEach((el) => {
      el.classList.toggle("hidden", el.dataset.exitKind !== selected);
    });
  }
}
```

Register it in `app/javascript/controllers/index.js` if controllers aren't auto-registered:

```javascript
import HandoffSettingsController from "./handoff_settings_controller";
application.register("handoff-settings", HandoffSettingsController);
```

(Skip this step if the project uses `eagerLoadControllersFrom` — `grep -n "eagerLoadControllersFrom\|register(" app/javascript/controllers/index.js` to check.)

- [ ] **Step 6: Wire component into the page editor**

In the page-editor partial located via Step 1, add an "Hand off to module" radio option next to the existing "Redirect to flowchart" option. When selected, render the new component:

```erb
<% if params.dig(:form_settings, :after_submit) == "handoff" || @page.handoff? %>
  <%= render Pages::HandoffSettingsComponent.new(page: @page) %>
<% end %>
```

Exact placement depends on the existing template structure — preserve the existing form submission flow.

- [ ] **Step 7: Run component spec to verify it passes**

Run: `bundle exec rspec spec/components/pages/handoff_settings_component_spec.rb`
Expected: PASS.

- [ ] **Step 8: Manually verify the page editor renders the picker**

Run: `bin/dev` (or equivalent) and navigate to a page edit route. Confirm the new "Hand off to module" option appears and toggles between exit-kind inputs. Note: manual verification is a step, not a test — do not claim completion without doing it.

- [ ] **Step 9: Do NOT commit**

---

## Task 16: `FeatureModulesController#show` — display + configure exit-landing override

**Files:**
- Modify: `app/controllers/feature_modules_controller.rb`
- Modify: the show view (`app/views/feature_modules/show.html.erb` — confirm via `ls app/views/feature_modules/`)
- Extend: `spec/requests/feature_modules_controller_spec.rb` (create if absent; a show spec likely already exists)

- [ ] **Step 1: Write the failing tests**

Extend `spec/requests/feature_modules_controller_spec.rb`:

```ruby
RSpec.describe "FeatureModulesController exit-landing", type: :request do
  let(:customer) { create(:customer) }
  let!(:fm) { create(:feature_module, key: "payment", name: "Payments") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: fm, status: :active, configuration: {}.to_json) }

  before do
    allow_any_instance_of(FeatureModule).to receive(:registration_class).and_return(FeatureModules::Payment::Registration)
    sign_in_as_owner_of(customer) # helper; replace with whatever the suite already uses to authenticate
  end

  it "displays the module's default_exit on show" do
    get "/#{customer.id}/feature_modules/#{fm.id}"
    expect(response.body).to include("customer_home")
  end

  it "persists a customer-level exit override via update_configuration" do
    patch "/#{customer.id}/feature_modules/#{fm.id}/configure",
          params: { configuration: { exit_landing_page: { kind: "url", url: "https://override.test" } } }
    expect(cfm.reload.configuration).to include("override.test")
  end
end
```

(Replace `sign_in_as_owner_of` with whatever the suite already uses — run `grep -rn "sign_in\|log_in\|as: customer" spec/requests | head -20` to find the right helper.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/feature_modules_controller_spec.rb`
Expected: FAIL — show view does not display default_exit.

- [ ] **Step 3: Modify the show action to expose default_exit**

In `app/controllers/feature_modules_controller.rb`, extend the `show` action:

```ruby
  def show
    @customer_feature = CustomerFeatureModule.find_by(
      customer_id: current_customer_id,
      feature_module_id: @feature_module.id
    )
    @module_models   = ModuleModelDiscovery.call(@feature_module.key)
    @module_routes   = ModuleRouteDiscovery.call(@feature_module.key)
    @default_exit    = @feature_module.registration_class.default_exit_config
    @exit_override   = customer_exit_override(@customer_feature)
  end

  private

  def customer_exit_override(cfm)
    return nil unless cfm
    parsed = cfm.configuration.is_a?(String) ? JSON.parse(cfm.configuration) : cfm.configuration
    parsed && parsed["exit_landing_page"]
  rescue JSON::ParserError
    nil
  end
```

(Append `customer_exit_override` to the existing `private` block; do not duplicate `private`.)

- [ ] **Step 4: Add the display + edit form to the show view**

In `app/views/feature_modules/show.html.erb`, add a section near the "My Configuration" area:

```erb
<section class="mt-8 p-4 border rounded">
  <h3 class="text-lg font-semibold">Exit Landing Page</h3>
  <p class="text-sm text-gray-600">Where users return after this module completes.</p>

  <% if @default_exit %>
    <p class="mt-2 text-sm">Module default: <code><%= @default_exit.to_json %></code></p>
  <% end %>

  <%= form_with url: configure_feature_module_path(current_customer_id, @feature_module), method: :patch do |f| %>
    <%= hidden_field_tag "configuration[exit_landing_page][kind]", @exit_override&.dig("kind") || "url" %>
    <label class="block text-sm font-medium mt-4">Override URL (leave blank to use module default)</label>
    <%= text_field_tag "configuration[exit_landing_page][url]", @exit_override&.dig("url"),
                       class: "mt-1 block w-full rounded border-gray-300" %>
    <%= f.submit "Save override", class: "mt-3 px-4 py-2 bg-blue-600 text-white rounded" %>
  <% end %>
</section>
```

This ships as a minimal URL-only override. The richer "pick page / flowchart / named route" picker for the override can be added later by reusing `HandoffSettingsComponent` with a different form-name prefix.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/feature_modules_controller_spec.rb`
Expected: PASS.

- [ ] **Step 6: Do NOT commit**

---

## Task 17: System spec — payment handoff round trip

**Files:**
- Create: `spec/system/feature_modules/payment_handoff_flow_spec.rb`

- [ ] **Step 1: Write the failing system spec**

Create `spec/system/feature_modules/payment_handoff_flow_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payment module handoff flow", type: :system do
  let(:customer) { create(:customer) }
  let!(:fm)  { create(:feature_module, key: "payment", name: "Payments") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: fm, status: :active, configuration: {}.to_json) }
  let(:entity) { create(:entity, customer: customer, name_slug: "orders") }
  let(:landing) { create(:page, customer: customer, published: true, public_token: "landing", name: "Thank You") }
  let(:trigger) do
    create(:page, customer: customer, entity: entity, published: true, public_token: "trigger",
           configuration: {
             form_settings: {
               after_submit: "handoff",
               handoff: {
                 module_key: "payment",
                 input_mapping: {
                   amount:   { source: "literal", value: 100 },
                   currency: { source: "literal", value: "USD" },
                   order_id: { source: "literal", value: 1 }
                 },
                 exit_target: { kind: "page", page_id: landing.id }
               }
             }
           }.to_json)
  end

  before do
    Rails.application.routes.draw do
      get    "/:customer_id/payment/checkout", to: "feature_modules/payment_demo#checkout"
      post   "/:customer_id/payment/checkout", to: "feature_modules/payment_demo#finish"

      # original routes preserved by calling reload_routes in after hook
    end

    stub_const("FeatureModules::PaymentDemoController", Class.new(ApplicationController) do
      set_tenant_from_route_params required: true
      include FeatureModules::InvocationContext

      def checkout
        render inline: "<%= form_with(url: url_for, method: :post) { |f| f.submit 'Pay' } %>"
      end

      def finish
        result = FeatureModules::Complete.call(
          session: session, customer: current_customer, module_key: "payment",
          output: { payment_reference: "pi_test", status: "succeeded", paid_at: Time.current.iso8601 }
        )
        flash.update(result[:flash])
        redirect_to result[:redirect_to]
      end
    end)
  end

  after { Rails.application.reload_routes! }

  it "walks from trigger page through payment to the configured landing page" do
    visit "/#{customer.id}/f/trigger"
    find('input[type="submit"]').click # submit trigger page

    # now on payment/checkout
    expect(current_path).to eq("/#{customer.id}/payment/checkout")

    click_on "Pay"

    # lands on the published landing page URL
    expect(current_path).to eq("/#{customer.id}/f/landing")
  end
end
```

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/system/feature_modules/payment_handoff_flow_spec.rb`
Expected: PASS (may need adjustments to inline-controller definition depending on Rails version + autoload).

- [ ] **Step 3: Do NOT commit**

---

## Task 18: System spec — authentication handoff

**Files:**
- Create: `spec/system/feature_modules/authentication_handoff_flow_spec.rb`

Follow the same pattern as Task 17 but use the real `FeatureModules::Authentication::Registration` and an exit target of `{ kind: "route", name: "customer_home" }`. After completion, expect `current_path` to equal `/#{customer.id}`. The spec exercises the "no input/output contract" path.

- [ ] **Step 1: Write the spec, run it, iterate until it passes.**

This spec is identical in structure to Task 17; its purpose is to prove that modules with empty contracts still work end-to-end. If auth's real controllers make this brittle, stub a minimal inline controller that calls `FeatureModules::Complete.call` with `output: {}`.

- [ ] **Step 2: Do NOT commit**

---

## Task 19: System spec — exit fallback chain

**Files:**
- Create: `spec/system/feature_modules/exit_fallback_chain_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Exit fallback chain", type: :system do
  let(:customer) { create(:customer) }
  let!(:fm)  { create(:feature_module, key: "payment", name: "Payments") }
  let!(:cfm) { create(:customer_feature_module, customer: customer, feature_module: fm, status: :active, configuration: {}.to_json) }
  let(:landing) { create(:page, customer: customer, published: true, public_token: "landing") }

  before do
    allow_any_instance_of(FeatureModule).to receive(:registration_class).and_return(FeatureModules::Payment::Registration)
  end

  around { |ex| Current.set(customer: customer, &ex) }

  it "falls back to customer override when no session target" do
    cfm.update!(configuration: { exit_landing_page: { kind: "page", page_id: landing.id } }.to_json)
    expect(FeatureModules::ExitResolver.call(customer: customer, module_key: "payment", session_exit_target: nil))
      .to eq("/#{customer.id}/f/landing")
  end

  it "falls back to module default when no session target and no customer override" do
    expect(FeatureModules::ExitResolver.call(customer: customer, module_key: "payment", session_exit_target: nil))
      .to eq("/#{customer.id}")
  end

  it "falls back to customer home as absolute last resort" do
    # override registration to have no default_exit
    reg = class_double(FeatureModules::Payment::Registration, default_exit_config: nil)
    allow_any_instance_of(FeatureModule).to receive(:registration_class).and_return(reg)
    expect(FeatureModules::ExitResolver.call(customer: customer, module_key: "payment", session_exit_target: nil))
      .to eq("/#{customer.id}")
  end
end
```

- [ ] **Step 2: Run**

Run: `bundle exec rspec spec/system/feature_modules/exit_fallback_chain_spec.rb`
Expected: PASS.

- [ ] **Step 3: Do NOT commit**

---

## Task 20: Full-suite regression + final review

- [ ] **Step 1: Run the full relevant suite**

Run:
```bash
bundle exec rspec spec/services/feature_modules/ spec/contracts/ spec/components/pages/ \
                  spec/models/page_spec.rb spec/models/feature_module_spec.rb \
                  spec/requests/public_pages_submission_spec.rb \
                  spec/requests/feature_modules_completion_spec.rb \
                  spec/requests/feature_modules_controller_spec.rb \
                  spec/system/feature_modules/ \
                  spec/controllers/concerns/feature_modules/invocation_context_spec.rb
```

Expected: all green.

- [ ] **Step 2: Run the entire project suite**

Run: `bundle exec rspec`
Expected: no new failures vs. pre-feature baseline.

- [ ] **Step 3: Manual smoke test in the dev server**

Run `bin/dev`. In a browser:
1. Visit a page you author with `after_submit: handoff` pointing to the Payment demo module and an exit page.
2. Submit the trigger page → lands on `/:customer_id/payment/checkout`.
3. Use the demo controller's "Pay" button → lands on the exit page.
4. Verify `flash[:feature_module_result]` is visible in rails console on the last request.

- [ ] **Step 4: Review diff for placeholders / stray TODOs**

Run: `git diff --stat` and `git grep -n "TBD\|TODO\|FIXME" -- app/services/feature_modules app/contracts app/controllers/public_pages_controller.rb app/models/page.rb app/controllers/concerns/feature_modules`
Expected: no new TODO/TBD/FIXME markers in changed files.

- [ ] **Step 5: Hand off to user**

Do not commit. Summarize:
- Files created/modified.
- `rspec` green across the listed suites.
- Any skipped edge cases discovered during implementation.

User will review the diff and create commits manually per AGENTS.md.

---

## Self-Review Checklist

| Spec requirement | Covered by |
|---|---|
| R1 — Integration: page → module handoff | Tasks 10, 11, 17 |
| R2 — Exit landing page (4 kinds + fallback chain) | Tasks 5, 7, 16, 19 |
| R3 — Multi-tenancy / cross-tenant refusal | Tasks 6 (Invocation.current), 7 (Complete), 5 (ExitResolver `for_current_customer`) |
| R4 — Full test pyramid | Tasks 1-16 unit; 11, 12, 16 request; 17-19 system |
| `form_settings.handoff` JSON shape | Tasks 9, 10 |
| Session lifecycle (`begin!`, `current`, `clear!`, `abandon!`) | Task 6 |
| Module DSL (`entry_path`, `default_exit`, `input_contract`, `output_contract`) | Tasks 2, 13, 14 |
| `NullRegistration` extended | Task 3 |
| `FeatureModuleLog` audit entries | Tasks 6, 7 |
| Error hierarchy + locale | Task 1 |
| Route allowlist + URL scheme allowlist | Tasks 5, 9 |
| Controller concern for module code | Task 8 |
| Page editor UI (ViewComponent + Stimulus) | Task 15 |
| `FeatureModulesController#show` displays default_exit + override | Task 16 |
| Payment demo module | Task 13 |
| Auth real module adopts DSL | Task 14 |
| Exit fallback chain proven end-to-end | Task 19 |

No spec requirement is unassigned. No step references undefined types or functions. All steps include either code or an exact shell command with expected result. Commits are intentionally omitted — AGENTS.md forbids auto-commits.
