# Parameter / Configuration System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add runtime configuration resolution where step configs adapt based on user role, device type, and custom conditions via inline overrides with last-write-wins merging.

**Architecture:** A new `FlowchartRuntime::ConfigResolver` service takes a step config hash with an `"overrides"` array, evaluates each override's `"when"` clause against enriched runtime context, and deep-merges matching `"apply"` values. The `DynamicController` enriches `ctx` with `current_user_role`, `current_user_id`, and `device_type` before execution.

**Tech Stack:** Ruby on Rails 8.1, RSpec, FactoryBot

**Spec:** `docs/superpowers/specs/2026-04-06-parameter-configuration-design.md`

---

## File Map

### New Files

| File | Responsibility |
|---|---|
| `app/services/flowchart_runtime/config_resolver.rb` | Evaluate overrides against ctx, deep-merge matching applies |
| `spec/services/flowchart_runtime/config_resolver_spec.rb` | ConfigResolver unit tests |
| `spec/integration/config_overrides_integration_spec.rb` | End-to-end test |

### Modified Files

| File | Change |
|---|---|
| `app/controllers/dynamic_controller.rb` | Enrich ctx with current_user_role, device_type, current_user_id in `build_context` |

---

## Task 1: ConfigResolver Service

**Files:**
- Create: `app/services/flowchart_runtime/config_resolver.rb`
- Create: `spec/services/flowchart_runtime/config_resolver_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/flowchart_runtime/config_resolver_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ConfigResolver do
  describe ".resolve" do
    it "returns base config unchanged when no overrides" do
      config = { "pageSize" => 25, "orderBy" => "name" }
      ctx = { current_user_role: "member" }

      result = described_class.resolve(config, ctx)
      expect(result).to eq({ "pageSize" => 25, "orderBy" => "name" })
    end

    it "returns base config when overrides key is empty" do
      config = { "pageSize" => 25, "overrides" => [] }
      ctx = { current_user_role: "member" }

      result = described_class.resolve(config, ctx)
      expect(result).to eq({ "pageSize" => 25 })
    end

    it "strips overrides key from result" do
      config = { "pageSize" => 25, "overrides" => [{ "when" => { "role" => "admin" }, "apply" => { "pageSize" => 100 } }] }
      ctx = { current_user_role: "member" }

      result = described_class.resolve(config, ctx)
      expect(result).not_to have_key("overrides")
    end

    context "role matching" do
      it "applies override when role matches" do
        config = {
          "pageSize" => 25,
          "overrides" => [{ "when" => { "role" => "admin" }, "apply" => { "pageSize" => 100 } }]
        }
        ctx = { current_user_role: "admin" }

        result = described_class.resolve(config, ctx)
        expect(result["pageSize"]).to eq(100)
      end

      it "skips override when role does not match" do
        config = {
          "pageSize" => 25,
          "overrides" => [{ "when" => { "role" => "admin" }, "apply" => { "pageSize" => 100 } }]
        }
        ctx = { current_user_role: "member" }

        result = described_class.resolve(config, ctx)
        expect(result["pageSize"]).to eq(25)
      end
    end

    context "device matching" do
      it "applies override when device matches" do
        config = {
          "pageSize" => 25,
          "overrides" => [{ "when" => { "device" => "mobile" }, "apply" => { "pageSize" => 10 } }]
        }
        ctx = { device_type: "mobile" }

        result = described_class.resolve(config, ctx)
        expect(result["pageSize"]).to eq(10)
      end

      it "skips override when device does not match" do
        config = {
          "pageSize" => 25,
          "overrides" => [{ "when" => { "device" => "mobile" }, "apply" => { "pageSize" => 10 } }]
        }
        ctx = { device_type: "desktop" }

        result = described_class.resolve(config, ctx)
        expect(result["pageSize"]).to eq(25)
      end
    end

    context "condition matching" do
      it "applies override when condition evaluates to truthy" do
        config = {
          "pageSize" => 25,
          "overrides" => [{ "when" => { "condition" => "ctx.vip_customer" }, "apply" => { "pageSize" => 50 } }]
        }
        ctx = { vip_customer: true }

        result = described_class.resolve(config, ctx)
        expect(result["pageSize"]).to eq(50)
      end

      it "skips override when condition evaluates to falsy" do
        config = {
          "pageSize" => 25,
          "overrides" => [{ "when" => { "condition" => "ctx.vip_customer" }, "apply" => { "pageSize" => 50 } }]
        }
        ctx = { vip_customer: false }

        result = described_class.resolve(config, ctx)
        expect(result["pageSize"]).to eq(25)
      end

      it "skips override when condition field is nil" do
        config = {
          "pageSize" => 25,
          "overrides" => [{ "when" => { "condition" => "ctx.vip_customer" }, "apply" => { "pageSize" => 50 } }]
        }
        ctx = {}

        result = described_class.resolve(config, ctx)
        expect(result["pageSize"]).to eq(25)
      end
    end

    context "combined when clause (AND)" do
      it "applies only when all conditions match" do
        config = {
          "pageSize" => 25,
          "overrides" => [{ "when" => { "role" => "admin", "device" => "mobile" }, "apply" => { "pageSize" => 5 } }]
        }

        # Both match
        result = described_class.resolve(config, { current_user_role: "admin", device_type: "mobile" })
        expect(result["pageSize"]).to eq(5)

        # Only role matches
        result = described_class.resolve(config, { current_user_role: "admin", device_type: "desktop" })
        expect(result["pageSize"]).to eq(25)
      end
    end

    context "last-write-wins" do
      it "later overrides take precedence" do
        config = {
          "pageSize" => 25,
          "overrides" => [
            { "when" => { "role" => "admin" }, "apply" => { "pageSize" => 100 } },
            { "when" => { "device" => "mobile" }, "apply" => { "pageSize" => 10 } }
          ]
        }
        ctx = { current_user_role: "admin", device_type: "mobile" }

        result = described_class.resolve(config, ctx)
        expect(result["pageSize"]).to eq(10) # mobile override wins (last)
      end

      it "non-conflicting keys from multiple overrides merge" do
        config = {
          "pageSize" => 25,
          "orderBy" => "name",
          "overrides" => [
            { "when" => { "role" => "admin" }, "apply" => { "pageSize" => 100 } },
            { "when" => { "device" => "mobile" }, "apply" => { "orderBy" => "date" } }
          ]
        }
        ctx = { current_user_role: "admin", device_type: "mobile" }

        result = described_class.resolve(config, ctx)
        expect(result["pageSize"]).to eq(100)
        expect(result["orderBy"]).to eq("date")
      end
    end

    context "deep merge" do
      it "deep merges nested hashes" do
        config = {
          "queryConfig" => { "limit" => 100, "orderBy" => "name" },
          "overrides" => [
            { "when" => { "role" => "admin" }, "apply" => { "queryConfig" => { "limit" => 500 } } }
          ]
        }
        ctx = { current_user_role: "admin" }

        result = described_class.resolve(config, ctx)
        expect(result["queryConfig"]["limit"]).to eq(500)
        expect(result["queryConfig"]["orderBy"]).to eq("name") # preserved
      end
    end

    context "nil and missing ctx" do
      it "handles nil config gracefully" do
        expect(described_class.resolve(nil, {})).to eq({})
      end

      it "handles empty config" do
        expect(described_class.resolve({}, {})).to eq({})
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_runtime/config_resolver_spec.rb`
Expected: FAIL — `uninitialized constant FlowchartRuntime::ConfigResolver`

- [ ] **Step 3: Write implementation**

```ruby
# app/services/flowchart_runtime/config_resolver.rb
# frozen_string_literal: true

module FlowchartRuntime
  # ConfigResolver
  #
  # Resolves step configuration overrides at runtime. Takes a step config hash
  # with an optional "overrides" array, evaluates each override's "when" clause
  # against the runtime context, and deep-merges matching "apply" values.
  #
  # Resolution: last-write-wins for conflicting keys, AND logic for combined when clauses.
  #
  # @example
  #   config = {
  #     "pageSize" => 25,
  #     "overrides" => [
  #       { "when" => { "role" => "admin" }, "apply" => { "pageSize" => 100 } }
  #     ]
  #   }
  #   FlowchartRuntime::ConfigResolver.resolve(config, { current_user_role: "admin" })
  #   #=> { "pageSize" => 100 }
  #
  module ConfigResolver
    module_function

    # Resolve a step config against runtime context.
    #
    # @param config [Hash, nil] step configuration with optional "overrides" key
    # @param ctx [Hash] runtime context with :current_user_role, :device_type, etc.
    # @return [Hash] resolved configuration (overrides key removed)
    def resolve(config, ctx)
      return {} if config.nil? || !config.is_a?(Hash)

      overrides = config["overrides"]
      base = config.except("overrides")

      return base if overrides.blank?

      result = base.deep_dup

      overrides.each do |override|
        next unless override.is_a?(Hash)
        next unless matches?(override["when"], ctx)

        apply = override["apply"]
        next unless apply.is_a?(Hash)

        result = deep_merge(result, apply)
      end

      result
    end

    # Check if all conditions in a "when" clause match the runtime context.
    #
    # @param when_clause [Hash, nil] conditions to check
    # @param ctx [Hash] runtime context
    # @return [Boolean]
    def matches?(when_clause, ctx)
      return false if when_clause.blank? || !when_clause.is_a?(Hash)

      when_clause.all? do |key, expected|
        case key
        when "role"
          ctx[:current_user_role].to_s == expected.to_s
        when "device"
          ctx[:device_type].to_s == expected.to_s
        when "condition"
          value = ContextResolver.resolve(expected, ctx)
          !!value
        else
          false
        end
      end
    end

    # Deep merge two hashes. Values from `override` take precedence.
    # Nested hashes are merged recursively. Non-hash values are replaced.
    #
    # @param base [Hash]
    # @param override [Hash]
    # @return [Hash]
    def deep_merge(base, override)
      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_runtime/config_resolver_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_runtime/config_resolver.rb spec/services/flowchart_runtime/config_resolver_spec.rb
git commit -m "feat: add ConfigResolver for runtime step config overrides"
```

---

## Task 2: DynamicController — Enrich ctx

**Files:**
- Modify: `app/controllers/dynamic_controller.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/controllers/dynamic_controller_context_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe DynamicController, type: :controller do
  describe "#detect_device_type" do
    let(:controller_instance) { described_class.new }

    it "detects mobile from user agent" do
      expect(controller_instance.send(:detect_device_type, "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) Mobile/15A5341f")).to eq("mobile")
    end

    it "detects tablet from user agent" do
      expect(controller_instance.send(:detect_device_type, "Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X)")).to eq("tablet")
    end

    it "defaults to desktop" do
      expect(controller_instance.send(:detect_device_type, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")).to eq("desktop")
    end

    it "handles nil user agent" do
      expect(controller_instance.send(:detect_device_type, nil)).to eq("desktop")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/dynamic_controller_context_spec.rb`
Expected: FAIL — `undefined method 'detect_device_type'`

- [ ] **Step 3: Update DynamicController**

In `app/controllers/dynamic_controller.rb`, update the `build_context` method and add `detect_device_type`:

Replace:
```ruby
  def build_context
    {
      params:       activity_params,
      bound_entity: @entity,
      id:           @entity_entry_id,
      model:        @entity_entry,
      customer_id:  current_customer_id
    }.compact
  end
```

With:
```ruby
  def build_context
    {
      params:             activity_params,
      bound_entity:       @entity,
      id:                 @entity_entry_id,
      model:              @entity_entry,
      customer_id:        current_customer_id,
      current_user_id:    current_user&.id,
      current_user_role:  current_user&.role,
      device_type:        detect_device_type(request.user_agent)
    }.compact
  end
```

Add the private method:
```ruby
  def detect_device_type(user_agent)
    return "desktop" if user_agent.blank?

    ua = user_agent.to_s
    if ua.match?(/Tablet|iPad/i)
      "tablet"
    elsif ua.match?(/Mobile|Android|iPhone/i)
      "mobile"
    else
      "desktop"
    end
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/dynamic_controller_context_spec.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dynamic_controller.rb spec/controllers/dynamic_controller_context_spec.rb
git commit -m "feat: enrich DynamicController ctx with user role and device type"
```

---

## Task 3: Integration test — Config overrides end-to-end

**Files:**
- Create: `spec/integration/config_overrides_integration_spec.rb`

- [ ] **Step 1: Write the integration test**

```ruby
# spec/integration/config_overrides_integration_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Config overrides integration", type: :model do
  describe "ConfigResolver with enriched context" do
    it "resolves role-based override" do
      config = {
        "pageSize" => 25,
        "queryType" => "where",
        "overrides" => [
          { "when" => { "role" => "admin" }, "apply" => { "pageSize" => 100 } },
          { "when" => { "role" => "member" }, "apply" => { "pageSize" => 10 } }
        ]
      }

      admin_ctx = { current_user_role: "admin", device_type: "desktop" }
      member_ctx = { current_user_role: "member", device_type: "desktop" }

      admin_result = FlowchartRuntime::ConfigResolver.resolve(config, admin_ctx)
      member_result = FlowchartRuntime::ConfigResolver.resolve(config, member_ctx)

      expect(admin_result["pageSize"]).to eq(100)
      expect(member_result["pageSize"]).to eq(10)
      # queryType unchanged
      expect(admin_result["queryType"]).to eq("where")
    end

    it "resolves device-based override" do
      config = {
        "columns" => 4,
        "overrides" => [
          { "when" => { "device" => "mobile" }, "apply" => { "columns" => 1 } },
          { "when" => { "device" => "tablet" }, "apply" => { "columns" => 2 } }
        ]
      }

      mobile_result = FlowchartRuntime::ConfigResolver.resolve(config, { device_type: "mobile" })
      tablet_result = FlowchartRuntime::ConfigResolver.resolve(config, { device_type: "tablet" })
      desktop_result = FlowchartRuntime::ConfigResolver.resolve(config, { device_type: "desktop" })

      expect(mobile_result["columns"]).to eq(1)
      expect(tablet_result["columns"]).to eq(2)
      expect(desktop_result["columns"]).to eq(4) # no override matches
    end

    it "resolves condition-based override with ctx values" do
      config = {
        "showDetails" => false,
        "overrides" => [
          { "when" => { "condition" => "ctx.premium_account" }, "apply" => { "showDetails" => true } }
        ]
      }

      premium_ctx = { premium_account: true }
      free_ctx = { premium_account: false }

      expect(FlowchartRuntime::ConfigResolver.resolve(config, premium_ctx)["showDetails"]).to be true
      expect(FlowchartRuntime::ConfigResolver.resolve(config, free_ctx)["showDetails"]).to be false
    end

    it "applies last-write-wins for conflicting overrides" do
      config = {
        "limit" => 50,
        "overrides" => [
          { "when" => { "role" => "admin" }, "apply" => { "limit" => 200 } },
          { "when" => { "device" => "mobile" }, "apply" => { "limit" => 20 } }
        ]
      }

      # Admin on mobile: both match, mobile wins (last)
      ctx = { current_user_role: "admin", device_type: "mobile" }
      result = FlowchartRuntime::ConfigResolver.resolve(config, ctx)
      expect(result["limit"]).to eq(20)
    end

    it "deep merges nested configuration" do
      config = {
        "queryConfig" => { "limit" => 100, "orderBy" => "name", "filter" => { "status" => "all" } },
        "overrides" => [
          { "when" => { "role" => "admin" }, "apply" => { "queryConfig" => { "limit" => 1000, "filter" => { "status" => "active" } } } }
        ]
      }

      ctx = { current_user_role: "admin" }
      result = FlowchartRuntime::ConfigResolver.resolve(config, ctx)

      expect(result["queryConfig"]["limit"]).to eq(1000)
      expect(result["queryConfig"]["orderBy"]).to eq("name") # preserved from base
      expect(result["queryConfig"]["filter"]["status"]).to eq("active") # overridden
    end
  end
end
```

- [ ] **Step 2: Run the integration test**

Run: `bundle exec rspec spec/integration/config_overrides_integration_spec.rb`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add spec/integration/config_overrides_integration_spec.rb
git commit -m "test: add integration tests for config overrides"
```
