# Part 8: Refactor ActivityGenerator + Delete Old Files

## Task 16: Refactor ActivityGenerator to Delegate

**Files:**
- Modify: `app/services/activity_generator.rb` (rewrite from ~780 to ~200 lines)

This is the critical migration step. The ActivityGenerator keeps orchestration logic but delegates all code generation to the registry.

- [ ] **Step 1: Rewrite ActivityGenerator**

Replace the entire content of `app/services/activity_generator.rb` with:

```ruby
# frozen_string_literal: true

# ActivityGenerator
#
# Generates Trailblazer::Activity code for a Flowchart by traversing
# the configuration tree using depth-first algorithm.
#
# Delegates code generation to individual generators discovered by
# CodeGenerators::GeneratorRegistry. Each element type and step action
# has a dedicated generator class.
#
# @example
#   ActivityGenerator.new(flowchart).generate
#   # => "# frozen_string_literal: true\n\nclass CreateUserActivity < Trailblazer::Activity::Railway\n  ..."
#
class ActivityGenerator
  delegate :model_class_name, :contract_class_name, to: :class_loader

  attr_reader :flowchart, :elements, :connections, :bound_entity, :class_loader, :element_map, :adjacency

  def initialize(flowchart)
    @flowchart = flowchart
    @elements = flowchart.elements || []
    @connections = flowchart.connections || []
    @bound_entity = flowchart.entity
    @class_loader = DynamicClassLoader.new(bound_entity)
    @registry = CodeGenerators::GeneratorRegistry.instance
  end

  def generate
    return nil if flowchart.name.blank? || elements.empty?

    validation_errors = validate_structure
    if validation_errors.any?
      Rails.logger.warn("Flowchart validation failed for #{flowchart.id}: #{validation_errors.join(', ')}")
      return nil
    end

    steps = dfs_collect_steps
    class_def = class_definition_with_steps(steps)
    [header(steps), class_def].compact.join("\n")
  end

  private

  # === Validation ===

  def validate_structure
    errors = []
    start_elements = elements.select { |el| el["type"] == "start" }
    end_elements = elements.select { |el| el["type"] == "end" }
    conns = flowchart.connections || []

    errors << "Missing Start element" if start_elements.empty?
    errors << "Multiple Start elements" if start_elements.length > 1
    errors << "Missing End element" if end_elements.empty?

    elements.each do |el|
      next if el["type"] == "start"
      has_incoming = conns.any? { |c| c["to"] == el["id"] }
      errors << "Element '#{el['label']}' has no incoming connections" unless has_incoming
    end

    errors
  end

  def shared_flowchart?
    flowchart.type_shared?
  end

  # === Header ===

  def header(steps = [])
    subprocess_info = steps.select { |s| s[:subprocess] }
                           .map { |s| "#   - #{s[:subprocess][:activity_class_name]} (#{s[:subprocess][:subflow_name]})" }
                           .join("\n")

    model_info = if bound_entity
      build_bound_entity_header
    elsif shared_flowchart?
      build_shared_header
    else
      "# Blueprint (Template) - no entity bound"
    end

    trigger_info = build_trigger_info

    base_header = <<~RUBY.chomp
      # frozen_string_literal: true
      #
      # Generated Activity for: #{flowchart.name}
      #{trigger_info}
      #{model_info}
    RUBY

    if subprocess_info.present?
      base_header + "\n# Subprocesses:\n" + subprocess_info
    else
      base_header
    end
  end

  def build_trigger_info
    start_element = elements.find { |el| el["type"] == "start" }
    return "# Trigger: Manual" unless start_element

    trigger_type = start_element.dig("properties", "triggerType") || "manual"

    case trigger_type
    when "http"
      method = start_element.dig("properties", "httpMethod") || "POST"
      path = start_element.dig("properties", "httpPath") || "/api/resource"
      "# Trigger: HTTP #{method} #{path}"
    when "event"
      event_name = start_element.dig("properties", "eventName") || "event.name"
      "# Trigger: Event (#{event_name})"
    when "schedule"
      cron = start_element.dig("properties", "cronExpression") || "0 0 * * *"
      "# Trigger: Schedule (#{cron})"
    else
      "# Trigger: Manual"
    end
  end

  def build_bound_entity_header
    [
      "# Bound entity: #{bound_entity.name}",
      "# Model class: #{model_class_name}",
      "# Contract class: #{contract_class_name}",
      "# Multi-source: params detected and routed automatically at runtime"
    ].join("\n")
  end

  def build_shared_header
    [
      "# Shared flowchart - entity resolved at runtime via ctx[:bound_entity]",
      "# Multi-source: params detected and routed automatically at runtime"
    ].join("\n")
  end

  # === Class definition ===

  def class_definition_with_steps(steps)
    <<~RUBY

      class #{activity_class_name} < Trailblazer::Activity::Railway
      #{step_declarations(steps).indent(2)}

      #{step_methods(steps).indent(2)}
      end
    RUBY
  end

  def activity_class_name
    derive_activity_class_name(flowchart.name)
  end

  # === DFS Traversal ===

  def build_graph
    @element_map = elements.index_by { |el| el["id"] }
    @adjacency = Hash.new { |h, k| h[k] = [] }
    connections.each { |c| @adjacency[c["from"]] << c["to"] }
  end

  def start_node_id
    elements.find { |el| el["type"] == "start" }&.dig("id")
  end

  def dfs_collect_steps
    build_graph
    return [] unless start_node_id

    visited = Set.new
    steps = []
    used_names = {}
    ctx = { bound_entity: bound_entity }

    dfs_visit(start_node_id, visited, ctx) do |element, context|
      next if element["type"] == "start"

      subprocess_info = detect_subprocess(element)
      method_name = derive_method_name(element, used_names)
      steps << {
        element: element,
        method_name: method_name,
        ctx: context,
        subprocess: subprocess_info
      }
    end

    steps
  end

  def dfs_visit(node_id, visited, ctx, &block)
    return if visited.include?(node_id)

    visited.add(node_id)
    element = element_map[node_id]
    yield(element, ctx) if element

    adjacency[node_id].each do |child_id|
      dfs_visit(child_id, visited, ctx, &block)
    end
  end

  def detect_subprocess(element)
    return nil unless element["type"] == "subflow"

    flowchart_id = element.dig("properties", "flowchartId")
    return nil unless flowchart_id

    subflow_flowchart = Flowchart.find_by(id: flowchart_id)
    return nil unless subflow_flowchart

    var_mappings = element.dig("properties", "varMappings") || []

    {
      flowchart_id: flowchart_id,
      activity_class_name: derive_activity_class_name(subflow_flowchart.name),
      subflow_name: subflow_flowchart.name,
      var_mappings: var_mappings
    }
  end

  # === Name Derivation ===

  def derive_activity_class_name(name)
    name.to_s
        .gsub(/[^a-zA-Z0-9\s]/, "")
        .split
        .map(&:capitalize)
        .join << "Activity"
  end

  def derive_method_name(element, used_names)
    base_name = extract_base_name(element)
    ensure_unique_name(base_name, used_names)
  end

  def extract_base_name(element)
    name = element["label"].presence || element["type"]
    normalize_method_name(name)
  end

  def normalize_method_name(name)
    name.to_s
        .downcase
        .gsub(/[^a-z0-9]+/, "_")
        .gsub(/^_|_$/, "")
        .then { |n| n.empty? ? "step" : n }
  end

  def ensure_unique_name(base_name, used_names)
    if used_names.key?(base_name)
      used_names[base_name] += 1
      "#{base_name}_#{used_names[base_name]}"
    else
      used_names[base_name] = 0
      base_name
    end
  end

  # === Step Declarations ===

  def step_declarations(steps)
    return "# No steps defined" if steps.empty?

    steps.map { |s|
      if s[:subprocess]
        build_subprocess_declaration(s)
      else
        step_type = derive_step_type(s[:element])
        declaration = "#{step_type} :#{s[:method_name]}"

        error_handling = s[:element].dig("properties", "errorHandling")
        if error_handling && error_handling["mode"] == "route_to_error_end"
          declaration += "\nfail :handle_error_in_#{s[:method_name]}"
        end

        declaration
      end
    }.join("\n")
  end

  def derive_step_type(element)
    case element["type"]
    when "error_handler" then "fail"
    else "step"
    end
  end

  def build_subprocess_declaration(step_info)
    subprocess = step_info[:subprocess]
    var_mappings = subprocess[:var_mappings] || []

    if var_mappings.empty?
      <<~RUBY.chomp
        step Subprocess(#{subprocess[:activity_class_name]}),
          In() => ->(ctx, **) { ctx.to_h }
      RUBY
    else
      merge_entries = var_mappings.map { |m| "#{m['keyword']}: ctx[:#{m['value']}]" }
      except_entries = var_mappings.map { |m| ":#{m['value']}" }

      <<~RUBY.chomp
        step Subprocess(#{subprocess[:activity_class_name]}),
          In() => ->(ctx, **) do
            ctx.to_h.merge(
              #{merge_entries.join(",\n        ")}
            ).except(
              #{except_entries.join(",\n        ")}
            )
          end
      RUBY
    end
  end

  # === Step Methods ===

  def step_methods(steps)
    return "" if steps.empty?

    regular_steps = steps.reject { |s| s[:subprocess] }
    methods = regular_steps.map { |s| build_method(s) }

    error_handlers = regular_steps
      .select { |s| s[:element].dig("properties", "errorHandling", "mode") == "route_to_error_end" }
      .map { |s| build_error_handler_method(s) }

    (methods + error_handlers).join("\n\n")
  end

  def build_method(step_info)
    element = step_info[:element]
    method_name = step_info[:method_name]
    ctx = step_info[:ctx]
    label = element["label"]
    steps = element.dig("properties", "steps") || []

    <<~RUBY.chomp
      # #{label}
      def #{method_name}(ctx, **)
      #{method_body(element, steps, ctx).indent(2)}
      end
    RUBY
  end

  def build_error_handler_method(step_info)
    method_name = step_info[:method_name]
    error_field = step_info[:element].dig("properties", "errorHandling", "errorOutputField") || "ctx.error"
    field_key = error_field.sub(/^ctx\./, "")

    <<~RUBY.chomp
      # Error handler for #{step_info[:element]['label']}
      def handle_error_in_#{method_name}(ctx, **)
        ctx[:#{field_key}] = ctx["contract.default"]&.errors&.full_messages || ["An error occurred"]
      end
    RUBY
  end

  # === Code Generation (delegated to registry) ===

  def method_body(element, steps, ctx)
    type = element["type"]

    # Delegate to element type generator via registry
    generator_class = @registry.find_element_type(type)
    if generator_class
      generator = generator_class.new(element, ctx)
      result = generator.generate
      return result if result
    end

    # Fall through to process body (step actions within a process element)
    generate_process_body(element, steps, ctx)
  end

  def generate_process_body(_element, steps, ctx)
    return "true" if steps.empty?

    step_codes = steps.map { |step| generate_step_code(step, ctx) }

    if step_codes.all?(&:nil?)
      comments = steps.map { |s|
        action = s["action"] || "operation"
        detail = s["selectionLabels"]&.join(" > ") || s["description"] || ""
        detail.present? ? "# #{action}: #{detail}" : "# #{action}"
      }.join("\n")
      "#{comments}\n\ntrue"
    else
      step_codes.compact.join("\n")
    end
  end

  def generate_step_code(step, ctx)
    action = step["action"]
    return nil if action.blank?

    # Normalize action name for registry lookup (handles "API_call" -> "api_call")
    generator_class = @registry.find_step_action(action) || @registry.find_step_action(action.downcase)
    return nil unless generator_class

    generator = generator_class.new(step, ctx)
    code = generator.generate
    return nil unless code

    # Apply wrappers from the generator's base class
    generator.send(:apply_wrappers, code)
  end
end
```

- [ ] **Step 2: Run existing integration tests**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb -fd`
Expected: All PASS — the generated output must be identical

- [ ] **Step 3: Run compound conditions integration tests**

Run: `bundle exec rspec spec/services/activity_generator_compound_conditions_spec.rb -fd`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/activity_generator.rb
git commit -m "refactor: rewrite ActivityGenerator to delegate to GeneratorRegistry"
```

---

## Task 17: Delete Old Module Files

**Files:**
- Delete: `app/services/activity_generator/base_step_helpers.rb`
- Delete: `app/services/activity_generator/model_steps.rb`
- Delete: `app/services/activity_generator/validation_steps.rb`
- Delete: `app/services/activity_generator/data_steps.rb`
- Delete: `app/services/activity_generator/communication_steps.rb`
- Delete: `app/services/activity_generator/security_steps.rb`
- Delete: `app/services/activity_generator/background_steps.rb`
- Delete: `app/services/activity_generator/file_steps.rb`
- Delete: `app/services/activity_generator/realtime_steps.rb`
- Delete: `app/services/activity_generator/response_steps.rb`

- [ ] **Step 1: Delete all old module files**

```bash
rm app/services/activity_generator/base_step_helpers.rb
rm app/services/activity_generator/model_steps.rb
rm app/services/activity_generator/validation_steps.rb
rm app/services/activity_generator/data_steps.rb
rm app/services/activity_generator/communication_steps.rb
rm app/services/activity_generator/security_steps.rb
rm app/services/activity_generator/background_steps.rb
rm app/services/activity_generator/file_steps.rb
rm app/services/activity_generator/realtime_steps.rb
rm app/services/activity_generator/response_steps.rb
rmdir app/services/activity_generator/
```

- [ ] **Step 2: Delete old unit test files**

The old specs tested methods on the mixed-in modules. They're now replaced by the individual generator specs.

```bash
rm spec/services/activity_generator/model_steps_spec.rb
rm spec/services/activity_generator/validation_steps_spec.rb
rm spec/services/activity_generator/data_steps_spec.rb
rm spec/services/activity_generator/communication_steps_spec.rb
rm spec/services/activity_generator/security_steps_spec.rb
rm spec/services/activity_generator/background_steps_spec.rb
rm spec/services/activity_generator/file_steps_spec.rb
rm spec/services/activity_generator/realtime_steps_spec.rb
rm spec/services/activity_generator/response_steps_spec.rb
rmdir spec/services/activity_generator/
```

- [ ] **Step 3: Run full test suite**

Run: `bundle exec rspec spec/services/ -fd`
Expected: All PASS — old specs are gone, new generator specs pass, integration specs pass

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete old activity_generator modules and specs, replaced by code_generators"
```
