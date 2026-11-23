# Part 4: Element Type Generators

## Task 8: Start, End, Decision Generators

**Files:**
- Create: `app/services/code_generators/element_types/start_generator.rb`
- Create: `app/services/code_generators/element_types/end_generator.rb`
- Create: `app/services/code_generators/element_types/decision_generator.rb`
- Test: `spec/services/code_generators/element_types/start_generator_spec.rb`
- Test: `spec/services/code_generators/element_types/end_generator_spec.rb`
- Test: `spec/services/code_generators/element_types/decision_generator_spec.rb`

- [ ] **Step 1: Create StartGenerator**

Start elements are skipped in DFS — this generator exists for metadata/CRUD completeness.

```ruby
# app/services/code_generators/element_types/start_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    class StartGenerator < BaseGenerator
      generator_metadata do
        description "Entry point of the flowchart. Skipped in DFS traversal — metadata only."
        category :flow_control
        version "1.0.0"
      end

      input_schema  :trigger_type, :http_method, :http_path, :event_name, :cron_expression
      output_schema # none

      def generate
        nil
      end

      def validate_config(cfg)
        []
      end

      def example_output
        nil
      end
    end
  end
end
```

- [ ] **Step 2: Create EndGenerator**

```ruby
# app/services/code_generators/element_types/end_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    class EndGenerator < BaseGenerator
      include Shared::OperandConverter

      generator_metadata do
        description "Generates response code for end elements based on responseType"
        category :flow_control
        version "1.0.0"
      end

      input_schema  :response_type, :return_value, :http_status, :response_body
      output_schema :response, :http_status, :http_body

      def generate
        response_type = config["responseType"] || "none"

        case response_type
        when "value"
          return_value = config["returnValue"] || "ctx.result"
          ruby_value = condition_operand_to_ruby(return_value)
          <<~RUBY.chomp
            # Return value
            ctx[:response] = #{ruby_value}
            true
          RUBY
        when "http_response"
          status = config["httpStatus"] || 200
          body = config["responseBody"] || "{ success: true }"
          <<~RUBY.chomp
            # HTTP response
            ctx[:http_status] = #{status}
            ctx[:http_body] = #{body.inspect}
            true
          RUBY
        else
          "true"
        end
      end

      def validate_config(cfg)
        errors = []
        rt = cfg["responseType"]
        if rt == "value" && cfg["returnValue"].blank?
          errors << "Return value is required for 'value' response type"
        end
        errors
      end

      def example_output
        "ctx[:response] = ctx.dig(:result)\ntrue"
      end
    end
  end
end
```

- [ ] **Step 3: Create DecisionGenerator**

```ruby
# app/services/code_generators/element_types/decision_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    class DecisionGenerator < BaseGenerator
      include Shared::ConditionBuilder

      generator_metadata do
        description "Evaluates condition for Railway routing (true=success, false=failure)"
        category :flow_control
        version "1.0.0"
      end

      input_schema  :condition
      output_schema # none — routes via true/false return

      def generate
        condition = config["condition"]

        if condition.is_a?(Hash) && (condition["leftOperand"].present? || condition["type"] == "group")
          build_structured_condition(condition)
        else
          "# Decision: no condition configured\ntrue"
        end
      end

      def validate_config(cfg)
        errors = []
        errors << "No condition configured" if cfg["condition"].blank?
        errors
      end

      def example_output
        '(ctx.dig(:status) == "active")'
      end
    end
  end
end
```

- [ ] **Step 4: Write specs for all three**

```ruby
# spec/services/code_generators/element_types/start_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::StartGenerator do
  let(:element) { { "properties" => { "triggerType" => "http" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "returns nil from generate (start is metadata-only)" do
    gen = described_class.new(element, context)
    expect(gen.generate).to be_nil
  end
end
```

```ruby
# spec/services/code_generators/element_types/end_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::EndGenerator do
  let(:element) { { "properties" => { "responseType" => "none" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "returns 'true' for responseType=none" do
      gen = described_class.new({ "properties" => { "responseType" => "none" } }, {})
      expect(gen.generate).to eq("true")
    end

    it "generates return value code for responseType=value" do
      gen = described_class.new({ "properties" => { "responseType" => "value", "returnValue" => "ctx.result" } }, {})
      code = gen.generate
      expect(code).to include("ctx[:response] = ctx.dig(:result)")
    end

    it "generates HTTP response code for responseType=http_response" do
      gen = described_class.new({ "properties" => { "responseType" => "http_response", "httpStatus" => 201, "responseBody" => "{ ok: true }" } }, {})
      code = gen.generate
      expect(code).to include("ctx[:http_status] = 201")
      expect(code).to include("ctx[:http_body]")
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/decision_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::DecisionGenerator do
  let(:element) { { "properties" => { "condition" => { "leftOperand" => "ctx.status", "operator" => "==", "rightOperand" => "active" } } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates condition code from structured condition" do
      gen = described_class.new(element, context)
      expect(gen.generate).to eq('ctx.dig(:status) == "active"')
    end

    it "returns comment when no condition configured" do
      gen = described_class.new({ "properties" => {} }, {})
      expect(gen.generate).to include("no condition configured")
    end

    it "handles group conditions" do
      group_element = {
        "properties" => {
          "condition" => {
            "type" => "group", "operator" => "AND",
            "conditions" => [
              { "leftOperand" => "ctx.a", "operator" => "==", "rightOperand" => "1" },
              { "leftOperand" => "ctx.b", "operator" => "is_true" }
            ]
          }
        }
      }
      gen = described_class.new(group_element, {})
      code = gen.generate
      expect(code).to include("&&")
    end
  end
end
```

- [ ] **Step 5: Run specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/ -fd`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/services/code_generators/element_types/start_generator.rb \
        app/services/code_generators/element_types/end_generator.rb \
        app/services/code_generators/element_types/decision_generator.rb \
        spec/services/code_generators/element_types/
git commit -m "feat: add Start, End, Decision element type generators"
```

---

## Task 9: Loop, Timer, ErrorHandler, Subflow Generators

**Files:**
- Create: `app/services/code_generators/element_types/loop_generator.rb`
- Create: `app/services/code_generators/element_types/timer_generator.rb`
- Create: `app/services/code_generators/element_types/error_handler_generator.rb`
- Create: `app/services/code_generators/element_types/subflow_generator.rb`
- Test: `spec/services/code_generators/element_types/loop_generator_spec.rb`
- Test: `spec/services/code_generators/element_types/timer_generator_spec.rb`
- Test: `spec/services/code_generators/element_types/error_handler_generator_spec.rb`
- Test: `spec/services/code_generators/element_types/subflow_generator_spec.rb`

- [ ] **Step 1: Create LoopGenerator**

```ruby
# app/services/code_generators/element_types/loop_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    class LoopGenerator < BaseGenerator
      include Shared::ConditionBuilder

      generator_metadata do
        description "Generates loop code (while, do_while, for_each) with safety limits"
        category :flow_control
        version "1.0.0"
      end

      input_schema  :loop_type, :condition, :iterations, :collection, :item_variable, :index_variable
      output_schema :_loop_iteration_count

      def generate
        loop_type = config["loopType"] || "while"

        case loop_type
        when "for_each"  then generate_for_each_loop
        when "do_while"  then generate_do_while_loop
        else                  generate_while_loop
        end
      end

      def validate_config(cfg)
        errors = []
        lt = cfg["loopType"] || "while"
        if lt == "for_each" && cfg["collection"].blank?
          errors << "Collection expression required for for_each loop"
        end
        errors
      end

      def example_output
        "# While loop with max iterations safety limit\nctx[:_loop_iteration_count] = (ctx[:_loop_iteration_count] || 0) + 1\nreturn false if ctx[:_loop_iteration_count] > 10\n\ntrue"
      end

      private

      def generate_while_loop
        condition = config["condition"]
        max_iterations = config["iterations"] || 10

        guard = <<~RUBY.chomp
          # While loop with max iterations safety limit
          ctx[:_loop_iteration_count] = (ctx[:_loop_iteration_count] || 0) + 1
          return false if ctx[:_loop_iteration_count] > #{max_iterations}
        RUBY

        condition_check = build_loop_condition(condition)
        "#{guard}\n\n#{condition_check}"
      end

      def generate_do_while_loop
        condition = config["condition"]
        max_iterations = config["iterations"] || 10

        guard = <<~RUBY.chomp
          # Do-while loop: body executes first, condition checked after
          ctx[:_loop_iteration_count] = (ctx[:_loop_iteration_count] || 0) + 1
          return false if ctx[:_loop_iteration_count] > #{max_iterations}
        RUBY

        condition_check = build_loop_condition(condition)

        <<~RUBY.chomp
          #{guard}

          # Skip condition check on first iteration (do-while semantics)
          unless ctx[:_loop_iteration_count] == 1
            return false unless #{condition_check}
          end
          true
        RUBY
      end

      def generate_for_each_loop
        collection_expr = config["collection"] || "ctx.items"
        item_var = config["itemVariable"].presence || "item"
        index_var = config["indexVariable"].presence || "index"
        max_iterations = config["iterations"] || 100

        collection_ruby = condition_operand_to_ruby(collection_expr)

        <<~RUBY.chomp
          # For-each loop over collection
          collection = #{collection_ruby}
          collection = collection.is_a?(Array) ? collection : [collection].compact
          collection.take(#{max_iterations}).each_with_index do |#{item_var}, #{index_var}|
            ctx[:#{item_var}] = #{item_var}
            ctx[:#{index_var}] = #{index_var}
          end
          true
        RUBY
      end

      def build_loop_condition(condition)
        if condition.is_a?(Hash) && (condition["leftOperand"].present? || condition["type"] == "group")
          build_structured_condition(condition)
        elsif condition.is_a?(String) && condition.present?
          "# Legacy condition: #{condition}\ntrue"
        else
          "true"
        end
      end
    end
  end
end
```

- [ ] **Step 2: Create TimerGenerator**

```ruby
# app/services/code_generators/element_types/timer_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    class TimerGenerator < BaseGenerator
      include Shared::OperandConverter

      generator_metadata do
        description "Generates delay code (fixed duration or wait-until-condition)"
        category :flow_control
        version "1.0.0"
      end

      input_schema  :delay_type, :duration, :duration_unit, :wait_condition
      output_schema # none

      def generate
        delay_type = config["delayType"] || "fixed"

        case delay_type
        when "fixed"      then generate_fixed_delay
        when "until_condition" then generate_condition_wait
        else "# Unknown timer delay type: #{delay_type}\ntrue"
        end
      end

      def validate_config(cfg)
        errors = []
        if cfg["delayType"] == "fixed" && cfg["duration"].to_i <= 0
          errors << "Duration must be greater than 0 for fixed delay"
        end
        errors
      end

      def example_output
        "# Timer: Wait for 30 seconds\nsleep(30)\ntrue"
      end

      private

      def generate_fixed_delay
        duration = config["duration"].to_i
        duration_unit = config["durationUnit"] || "seconds"

        seconds = case duration_unit
                  when "minutes" then duration * 60
                  when "hours"   then duration * 3600
                  else duration
                  end

        <<~RUBY.chomp
          # Timer: Wait for #{duration} #{duration_unit}
          sleep(#{seconds})
          true
        RUBY
      end

      def generate_condition_wait
        wait_condition = config["waitCondition"]
        if wait_condition.blank?
          <<~RUBY.chomp
            # Timer: Wait until condition (no condition specified)
            true
          RUBY
        else
          condition_ruby = condition_operand_to_ruby(wait_condition)
          <<~RUBY.chomp
            # Timer: Wait until condition is met
            loop do
              break if #{condition_ruby}
              sleep(1)
            end
            true
          RUBY
        end
      end
    end
  end
end
```

- [ ] **Step 3: Create ErrorHandlerGenerator**

```ruby
# app/services/code_generators/element_types/error_handler_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    class ErrorHandlerGenerator < BaseGenerator
      generator_metadata do
        description "Generates fail-track code based on fallback action (log, retry, halt)"
        category :flow_control
        version "1.0.0"
      end

      input_schema  :error_types, :fallback_action
      output_schema :retry_requested

      def generate
        error_types = config["errorTypes"].presence || "all errors"
        fallback = config["fallbackAction"] || "log_and_continue"

        case fallback
        when "retry_parent"
          <<~RUBY.chomp
            # Error handler (#{error_types}): retry parent
            Rails.logger.error("Activity error: \#{ctx['contract.default']&.errors&.full_messages}")
            ctx[:retry_requested] = true
            true
          RUBY
        when "halt"
          <<~RUBY.chomp
            # Error handler (#{error_types}): halt execution
            Rails.logger.error("Activity error: \#{ctx['contract.default']&.errors&.full_messages}")
            false
          RUBY
        else
          <<~RUBY.chomp
            # Error handler (#{error_types}): log and continue
            Rails.logger.error("Activity error: \#{ctx['contract.default']&.errors&.full_messages}")
            true
          RUBY
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "# Error handler (all errors): log and continue\nRails.logger.error(\"Activity error: \#{ctx['contract.default']&.errors&.full_messages}\")\ntrue"
      end
    end
  end
end
```

- [ ] **Step 4: Create SubflowGenerator**

Note: Subflow elements are handled specially in step_declarations (Subprocess DSL), not in method_body. This generator exists for registry completeness and metadata. The actual subprocess declaration logic stays in the orchestrator.

```ruby
# app/services/code_generators/element_types/subflow_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    class SubflowGenerator < BaseGenerator
      generator_metadata do
        description "References a sub-flowchart as a Trailblazer Subprocess. Declaration handled by orchestrator."
        category :flow_control
        version "1.0.0"
      end

      input_schema  :flowchart_id, :var_mappings
      output_schema # depends on subflow

      def generate
        # Subflow step declarations are built by the orchestrator
        # (build_subprocess_declaration) because they need Subprocess() DSL.
        # This generator exists for registry metadata/CRUD UI.
        nil
      end

      def validate_config(cfg)
        errors = []
        errors << "No flowchartId specified" if cfg["flowchartId"].blank?
        errors
      end

      def example_output
        "step Subprocess(SubflowActivity),\n  In() => ->(ctx, **) { ctx.to_h }"
      end
    end
  end
end
```

- [ ] **Step 5: Write specs for all four**

```ruby
# spec/services/code_generators/element_types/loop_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::LoopGenerator do
  let(:element) { { "properties" => { "loopType" => "while", "iterations" => 10 } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates while loop with safety limit" do
      gen = described_class.new(element, context)
      code = gen.generate
      expect(code).to include("_loop_iteration_count")
      expect(code).to include("> 10")
    end

    it "generates for_each loop" do
      el = { "properties" => { "loopType" => "for_each", "collection" => "ctx.items", "itemVariable" => "item" } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("each_with_index")
      expect(code).to include("ctx.dig(:items)")
    end

    it "generates do_while loop" do
      el = { "properties" => { "loopType" => "do_while", "iterations" => 5 } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("do-while")
      expect(code).to include("> 5")
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/timer_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::TimerGenerator do
  let(:element) { { "properties" => { "delayType" => "fixed", "duration" => 30, "durationUnit" => "seconds" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates fixed delay with sleep" do
      gen = described_class.new(element, context)
      expect(gen.generate).to include("sleep(30)")
    end

    it "converts minutes to seconds" do
      el = { "properties" => { "delayType" => "fixed", "duration" => 2, "durationUnit" => "minutes" } }
      gen = described_class.new(el, {})
      expect(gen.generate).to include("sleep(120)")
    end

    it "generates condition wait loop" do
      el = { "properties" => { "delayType" => "until_condition", "waitCondition" => "ctx.ready" } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("loop do")
      expect(code).to include("ctx.dig(:ready)")
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/error_handler_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::ErrorHandlerGenerator do
  let(:element) { { "properties" => { "fallbackAction" => "log_and_continue" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates log_and_continue handler" do
      gen = described_class.new(element, context)
      code = gen.generate
      expect(code).to include("Rails.logger.error")
      expect(code.strip).to end_with("true")
    end

    it "generates halt handler" do
      el = { "properties" => { "fallbackAction" => "halt" } }
      gen = described_class.new(el, {})
      expect(gen.generate).to include("false")
    end

    it "generates retry_parent handler" do
      el = { "properties" => { "fallbackAction" => "retry_parent" } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("retry_requested")
    end
  end
end
```

```ruby
# spec/services/code_generators/element_types/subflow_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::SubflowGenerator do
  let(:element) { { "properties" => { "flowchartId" => 1, "varMappings" => [] } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "returns nil from generate (handled by orchestrator)" do
    gen = described_class.new(element, context)
    expect(gen.generate).to be_nil
  end

  it "validates flowchartId presence" do
    gen = described_class.new({ "properties" => {} }, {})
    errors = gen.validate_config({})
    expect(errors).to include("No flowchartId specified")
  end
end
```

- [ ] **Step 6: Run specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/ -fd`
Expected: All PASS (7 element type generators)

- [ ] **Step 7: Verify registry discovers element types**

Run: `bundle exec rspec spec/services/code_generators/generator_registry_spec.rb -fd`
Expected: PASS — registry now discovers 7 element type generators

- [ ] **Step 8: Commit**

```bash
git add app/services/code_generators/element_types/ \
        spec/services/code_generators/element_types/
git commit -m "feat: add all 7 element type generators (start, end, decision, loop, timer, error_handler, subflow)"
```
