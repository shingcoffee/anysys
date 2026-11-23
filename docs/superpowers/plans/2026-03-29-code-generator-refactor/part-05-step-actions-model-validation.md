# Part 5: Step Action Generators — Model Operations + Validation

## Task 10: Model Operation Generators (6 files)

**Files:**
- Create: `app/services/code_generators/step_actions/new_model_generator.rb`
- Create: `app/services/code_generators/step_actions/find_model_generator.rb`
- Create: `app/services/code_generators/step_actions/save_model_generator.rb`
- Create: `app/services/code_generators/step_actions/destroy_model_generator.rb`
- Create: `app/services/code_generators/step_actions/update_model_generator.rb`
- Create: `app/services/code_generators/step_actions/query_models_generator.rb`
- Test: `spec/services/code_generators/step_actions/new_model_generator_spec.rb`
- Test: `spec/services/code_generators/step_actions/find_model_generator_spec.rb`
- Test: `spec/services/code_generators/step_actions/save_model_generator_spec.rb`
- Test: `spec/services/code_generators/step_actions/destroy_model_generator_spec.rb`
- Test: `spec/services/code_generators/step_actions/update_model_generator_spec.rb`
- Test: `spec/services/code_generators/step_actions/query_models_generator_spec.rb`

**Source reference:** `app/services/activity_generator/model_steps.rb`

- [ ] **Step 1: Create all 6 model operation generators**

```ruby
# app/services/code_generators/step_actions/new_model_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class NewModelGenerator < BaseGenerator
      generator_metadata do
        description "Creates a new entity model instance"
        category :model_operations
        version "1.0.0"
      end

      input_schema  :bound_entity, :customer_id
      output_schema :model

      def generate
        <<~RUBY.chomp
          ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])
          true
        RUBY
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])\ntrue"
      end

      def dependencies
        [:build_contract]
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/find_model_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class FindModelGenerator < BaseGenerator
      include Shared::OperandConverter

      generator_metadata do
        description "Finds an existing model by id, field, or query"
        category :model_operations
        version "1.0.0"
      end

      input_schema  :bound_entity, :id
      output_schema :model

      def generate
        strategy = config["findStrategy"] || "find"
        result_var = config["resultVar"] || "model"

        case strategy
        when "findBy"
          field = config["findField"]
          value = config["findValue"]
          <<~RUBY.chomp
            ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).find_by!(#{field}: #{value})
            true
          RUBY
        when "where"
          field = config["findField"]
          value = config["findValue"]
          <<~RUBY.chomp
            ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).where(#{field}: #{value})
            true
          RUBY
        else
          <<~RUBY.chomp
            ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).find(ctx[:id])
            true
          RUBY
        end
      end

      def validate_config(cfg)
        errors = []
        strategy = cfg["findStrategy"]
        if %w[findBy where].include?(strategy) && cfg["findField"].blank?
          errors << "Find field is required for #{strategy} strategy"
        end
        errors
      end

      def example_output
        "ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).find(ctx[:id])\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/save_model_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class SaveModelGenerator < BaseGenerator
      generator_metadata do
        description "Transactional save of primary entity and associated entries"
        category :model_operations
        version "1.0.0"
      end

      input_schema  :model, :contract
      output_schema :model

      def generate
        strategy = config["saveStrategy"] || "saveAll"

        case strategy
        when "saveOnly"
          <<~RUBY.chomp
            ctx[:model].save!
            true
          RUBY
        else
          "ActivitySteps::SaveAll.call(ctx)"
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ActivitySteps::SaveAll.call(ctx)"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/destroy_model_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class DestroyModelGenerator < BaseGenerator
      generator_metadata do
        description "Destroys or soft-deletes the primary entity model"
        category :model_operations
        version "1.0.0"
      end

      input_schema  :model
      output_schema # model is destroyed

      def generate
        strategy = config["destroyStrategy"] || "destroy"

        case strategy
        when "softDelete"
          <<~RUBY.chomp
            ctx[:model].update!(status: :deleted)
            true
          RUBY
        else
          <<~RUBY.chomp
            ctx[:model].destroy
            true
          RUBY
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ctx[:model].destroy\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/update_model_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class UpdateModelGenerator < BaseGenerator
      generator_metadata do
        description "Updates specific fields on an existing model"
        category :model_operations
        version "1.0.0"
      end

      input_schema  :model
      output_schema :model

      def generate
        field_mappings = config["fieldMappings"] || []

        if field_mappings.any?
          assignments = field_mappings.map { |m| "#{m['key']}: #{m['value']}" }.join(", ")
          <<~RUBY.chomp
            ctx[:model].update!(#{assignments})
            true
          RUBY
        else
          <<~RUBY.chomp
            ctx[:model].update!
            true
          RUBY
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ctx[:model].update!(name: ctx[:name])\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/query_models_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class QueryModelsGenerator < BaseGenerator
      generator_metadata do
        description "Runs complex queries (where, scope, sql) against the entity model"
        category :model_operations
        version "1.0.0"
      end

      input_schema  :bound_entity
      output_schema :models

      def generate
        query_type = config["queryType"] || "where"
        result_var = config["resultVar"] || "models"
        order_by = config["orderBy"]
        limit = config["limit"]

        base_query = case query_type
                     when "scope" then build_scope_query
                     when "sql"   then build_sql_query
                     else              build_where_query
                     end

        unless query_type == "sql"
          base_query += ".order(#{order_by.inspect})" if order_by.present?
          base_query += ".limit(#{limit})" if limit.present?
        end

        <<~RUBY.chomp
          ctx[:#{result_var}] = #{base_query}
          true
        RUBY
      end

      def validate_config(cfg)
        errors = []
        if cfg["queryType"] == "sql" && cfg["sqlExpression"].blank?
          errors << "SQL expression is required for sql query type"
        end
        errors
      end

      def example_output
        "ctx[:models] = EntityEntry.build_for(ctx[:bound_entity]).where(nil)\ntrue"
      end

      private

      def build_where_query
        conditions = config["conditions"] || []
        if conditions.any?
          pairs = conditions.map { |c| "#{c['key']}: #{c['value']}" }.join(", ")
          "EntityEntry.build_for(ctx[:bound_entity]).where(#{pairs})"
        else
          "EntityEntry.build_for(ctx[:bound_entity]).where(nil)"
        end
      end

      def build_scope_query
        scope_name = config["scopeName"]
        scope_args = config["scopeArgs"]
        if scope_args.present?
          "EntityEntry.build_for(ctx[:bound_entity]).send(:#{scope_name}, #{scope_args})"
        else
          "EntityEntry.build_for(ctx[:bound_entity]).send(:#{scope_name})"
        end
      end

      def build_sql_query
        sql = config["sqlExpression"] || ""
        "ActiveRecord::Base.connection.execute(#{sql.inspect})"
      end
    end
  end
end
```

- [ ] **Step 2: Write specs for all 6 model generators**

```ruby
# spec/services/code_generators/step_actions/new_model_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::NewModelGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates EntityEntry.build_for call" do
    expect(described_class.new(element, context).generate).to include("EntityEntry.build_for")
  end

  it "assigns to ctx[:model]" do
    expect(described_class.new(element, context).generate).to include("ctx[:model] =")
  end

  it "includes customer_id" do
    expect(described_class.new(element, context).generate).to include("customer_id: ctx[:customer_id]")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/find_model_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::FindModelGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "defaults to find by id" do
    expect(described_class.new(element, context).generate).to include(".find(ctx[:id])")
  end

  it "supports findBy strategy" do
    el = { "config" => { "findStrategy" => "findBy", "findField" => "email", "findValue" => "ctx[:email]" } }
    expect(described_class.new(el, {}).generate).to include("find_by!(email: ctx[:email])")
  end

  it "supports where strategy" do
    el = { "config" => { "findStrategy" => "where", "findField" => "status", "findValue" => "ctx[:status]" } }
    expect(described_class.new(el, {}).generate).to include(".where(status: ctx[:status])")
  end

  it "supports custom result variable" do
    el = { "config" => { "resultVar" => "user" } }
    expect(described_class.new(el, {}).generate).to include("ctx[:user]")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/save_model_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::SaveModelGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "defaults to SaveAll" do
    expect(described_class.new(element, context).generate).to include("ActivitySteps::SaveAll")
  end

  it "supports saveOnly strategy" do
    el = { "config" => { "saveStrategy" => "saveOnly" } }
    expect(described_class.new(el, {}).generate).to include("ctx[:model].save!")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/destroy_model_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::DestroyModelGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "defaults to destroy" do
    expect(described_class.new(element, context).generate).to include("ctx[:model].destroy")
  end

  it "supports softDelete strategy" do
    el = { "config" => { "destroyStrategy" => "softDelete" } }
    expect(described_class.new(el, {}).generate).to include("update!(status: :deleted)")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/update_model_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::UpdateModelGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates update! with field mappings" do
    el = { "config" => { "fieldMappings" => [{ "key" => "name", "value" => "ctx[:name]" }] } }
    expect(described_class.new(el, {}).generate).to include("update!(name: ctx[:name])")
  end

  it "generates update! without mappings" do
    expect(described_class.new(element, context).generate).to include("ctx[:model].update!")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/query_models_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::QueryModelsGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "defaults to where query" do
    expect(described_class.new(element, context).generate).to include(".where(nil)")
  end

  it "supports where with conditions" do
    el = { "config" => { "conditions" => [{ "key" => "status", "value" => '"active"' }] } }
    expect(described_class.new(el, {}).generate).to include('.where(status: "active")')
  end

  it "supports scope query" do
    el = { "config" => { "queryType" => "scope", "scopeName" => "recent" } }
    expect(described_class.new(el, {}).generate).to include("send(:recent)")
  end

  it "appends order and limit" do
    el = { "config" => { "orderBy" => "created_at DESC", "limit" => "10" } }
    code = described_class.new(el, {}).generate
    expect(code).to include(".order(")
    expect(code).to include(".limit(10)")
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/services/code_generators/step_actions/ -fd`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/step_actions/new_model_generator.rb \
        app/services/code_generators/step_actions/find_model_generator.rb \
        app/services/code_generators/step_actions/save_model_generator.rb \
        app/services/code_generators/step_actions/destroy_model_generator.rb \
        app/services/code_generators/step_actions/update_model_generator.rb \
        app/services/code_generators/step_actions/query_models_generator.rb \
        spec/services/code_generators/step_actions/
git commit -m "feat: add 6 model operation step action generators"
```

---

## Task 11: Validation Generators (2 files)

**Files:**
- Create: `app/services/code_generators/step_actions/build_contract_generator.rb`
- Create: `app/services/code_generators/step_actions/validate_contract_generator.rb`
- Test: `spec/services/code_generators/step_actions/build_contract_generator_spec.rb`
- Test: `spec/services/code_generators/step_actions/validate_contract_generator_spec.rb`

**Source reference:** `app/services/activity_generator/validation_steps.rb`

- [ ] **Step 1: Create both validation generators**

```ruby
# app/services/code_generators/step_actions/build_contract_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class BuildContractGenerator < BaseGenerator
      generator_metadata do
        description "Builds a Reform validation contract for the primary entity"
        category :validation
        version "1.0.0"
      end

      input_schema  :bound_entity, :model
      output_schema :contract

      def generate
        <<~RUBY.chomp
          ctx[:contract] = EntityEntryContract.build_for(ctx[:bound_entity]).new(ctx[:model])
          true
        RUBY
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ctx[:contract] = EntityEntryContract.build_for(ctx[:bound_entity]).new(ctx[:model])\ntrue"
      end

      def dependencies
        [:new_model]
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/validate_contract_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class ValidateContractGenerator < BaseGenerator
      generator_metadata do
        description "Validates entity params through contract, with param routing and association population"
        category :validation
        version "1.0.0"
      end

      # Register under both "validate_contract" and "validate" action names
      def self.registered_names
        ["validate_contract", "validate"]
      end

      input_schema  :contract, :model, :params
      output_schema :result, :routed_params

      def generate
        sub_option = element.dig("subOption") || element.dig("suboption") || element.dig("selectionLabels", 0)

        case sub_option
        when "permission" then generate_permission_check
        else                   generate_contract_validation
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ActivitySteps::DetectAndRouteParams.call(ctx)\n..."
      end

      def dependencies
        [:build_contract]
      end

      private

      def generate_contract_validation
        <<~RUBY.chomp
          ActivitySteps::DetectAndRouteParams.call(ctx)
          ActivitySteps::PopulatePrimary.call(ctx, model: ctx[:model], routed_params: ctx[:routed_params])
          entity_params = ctx[:routed_params][:primary][:entity] || {}
          ctx[:result] = ctx[:contract].validate(entity_params)
          return false unless ctx[:result]
          ActivitySteps::PopulateAssociations.call(ctx, routed_params: ctx[:routed_params], customer_id: ctx[:customer_id])
          true
        RUBY
      end

      def generate_permission_check
        permission_type = config["permissionType"]

        case permission_type
        when "role_check"
          role_expression = config["roleExpression"] || "ctx[:current_user].role"
          required_role = config["requiredRole"] || "admin"
          <<~RUBY.chomp
            raise "Unauthorized" unless #{role_expression} == "#{required_role}"
            true
          RUBY
        when "policy_check"
          policy_class = config["policyClass"] || "ApplicationPolicy"
          policy_action = config["policyAction"] || "show?"
          user_expression = config["userExpression"] || "ctx[:current_user]"
          record_expression = config["recordExpression"] || "ctx[:model]"
          <<~RUBY.chomp
            Pundit.authorize(#{user_expression}, #{record_expression}, :#{policy_action})
            true
          RUBY
        else
          <<~RUBY.chomp
            # Permission check: no permission type configured
            ctx[:result] = true
          RUBY
        end
      end
    end
  end
end
```

- [ ] **Step 2: Write specs**

```ruby
# spec/services/code_generators/step_actions/build_contract_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::BuildContractGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates EntityEntryContract.build_for call" do
    expect(described_class.new(element, context).generate).to include("EntityEntryContract.build_for")
  end

  it "assigns to ctx[:contract]" do
    expect(described_class.new(element, context).generate).to include("ctx[:contract] =")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/validate_contract_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::ValidateContractGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "registers under both 'validate_contract' and 'validate'" do
    expect(described_class.registered_names).to eq(["validate_contract", "validate"])
  end

  it "generates contract validation flow by default" do
    code = described_class.new(element, context).generate
    expect(code).to include("DetectAndRouteParams")
    expect(code).to include("PopulatePrimary")
    expect(code).to include("PopulateAssociations")
  end

  it "generates permission check when sub_option is 'permission'" do
    el = { "config" => { "permissionType" => "role_check", "requiredRole" => "admin" }, "subOption" => "permission" }
    code = described_class.new(el, {}).generate
    expect(code).to include("Unauthorized")
    expect(code).to include('"admin"')
  end

  it "generates policy check" do
    el = {
      "config" => { "permissionType" => "policy_check", "policyClass" => "UserPolicy", "policyAction" => "update?" },
      "subOption" => "permission"
    }
    code = described_class.new(el, {}).generate
    expect(code).to include("Pundit.authorize")
    expect(code).to include("UserPolicy")
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/services/code_generators/step_actions/build_contract_generator_spec.rb spec/services/code_generators/step_actions/validate_contract_generator_spec.rb -fd`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/step_actions/build_contract_generator.rb \
        app/services/code_generators/step_actions/validate_contract_generator.rb \
        spec/services/code_generators/step_actions/build_contract_generator_spec.rb \
        spec/services/code_generators/step_actions/validate_contract_generator_spec.rb
git commit -m "feat: add validation step action generators (build_contract, validate_contract)"
```
