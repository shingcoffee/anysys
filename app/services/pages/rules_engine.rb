# frozen_string_literal: true

module Pages
  # Server-side evaluation of page form rules.
  #
  # Mirrors the client-side ConditionEvaluator logic to validate that
  # hidden fields are not submitted (prevents form field injection).
  #
  # Also evaluates calculations server-side for computed fields.
  #
  # @example Filtering submitted params
  #   engine = Pages::RulesEngine.new(page)
  #   permitted = engine.filter_hidden_fields(submitted_params)
  #
  # @example Evaluating calculations
  #   engine = Pages::RulesEngine.new(page)
  #   computed = engine.evaluate_calculations(submitted_params)
  #
  class RulesEngine
    attr_reader :rules, :calculations

    def initialize(page_or_config)
      config = if page_or_config.respond_to?(:configuration_json)
                 page_or_config.configuration_json || {}
      else
                 page_or_config
      end

      @rules = config["rules"] || []
      @calculations = config["calculations"] || []

      # Rules/calculations reference page-builder field ids (e.g. "field_ab12"),
      # but submitted params and stored entry data are keyed by the entity's
      # property_slug. Build an id => slug map so we evaluate/merge against the
      # same keys the form actually uses. Falls back to pass-through when a key
      # isn't a known field id (keeps slug- or id-keyed callers working).
      fields = flatten_fields((config["pages"] || []).flat_map { |p| p["fields"] || [] })
      @field_slug_map = fields.each_with_object({}) do |f, map|
        next unless f["id"].present? && f["property_slug"].present?
        prefix = case f["source"]
                 when "base_model" then "base.#{SectionSlug.for(f['source_section'])}."
                 when "bridge" then "assoc.#{SectionSlug.for(f['source_section'])}."
                 else ""
                 end
        map[f["id"]] = "#{prefix}#{f['property_slug']}"
      end
    end

    # Drop all client-authored calculated targets before evaluating rules.
    # Hidden inputs are removed monotonically and calculations are re-evaluated
    # so a hidden/forged intermediate cannot influence a downstream value.
    def apply(values, allowed_keys: nil)
      inputs = values.stringify_keys.except(*calculated_input_keys)
      blocked = Set.new
      allowed_targets = allowed_keys&.to_set
      loop do
        computed = evaluate_calculations(inputs, excluded_targets: blocked, allowed_targets: allowed_targets)
        combined = inputs.merge(computed)
        hidden = compute_hidden_fields(combined)
        next_blocked = blocked | hidden
        return combined.except(*next_blocked.to_a) if next_blocked == blocked

        blocked = next_blocked
        inputs = inputs.except(*blocked.to_a)
      end
    end

    # Returns a filtered params hash with hidden field values removed.
    # Fields that should be hidden (based on rule evaluation) are stripped
    # so they cannot be injected via manual form manipulation.
    #
    # @param params [Hash] submitted form field values (field_id => value)
    # @return [Hash] filtered params with hidden fields removed
    def filter_hidden_fields(params)
      hidden_field_ids = compute_hidden_fields(params)
      params.reject { |key, _| hidden_field_ids.include?(key.to_s) }
    end

    # Returns the set of field IDs that should be hidden given the current values.
    #
    # @param values [Hash] current field values
    # @return [Set<String>] field IDs that are hidden
    def compute_hidden_fields(values)
      hidden = Set.new

      rules.each do |rule|
        next unless rule["enabled"] != false

        matched = evaluate_conditions(rule["conditions"], values)

        (rule["actions"] || []).each do |action|
          target = resolve_key(action["target_id"]).to_s

          case action["type"]
          when "show_field"
            hidden.add(target) unless matched
          when "hide_field"
            hidden.add(target) if matched
          end
        end
      end

      hidden
    end

    # Evaluates all calculations and returns computed values.
    #
    # @param values [Hash] current field values
    # @return [Hash] calculated field_id => computed_value pairs
    def evaluate_calculations(values, excluded_targets: Set.new, allowed_targets: nil)
      results = {}
      inputs = values.stringify_keys.except(*calculated_input_keys)
      grouped = calculations.select { |calc| calc.is_a?(Hash) && calc["enabled"] != false && calc["target_field_id"].present? }
                            .group_by { |calc| resolve_key(calc["target_field_id"]).to_s }
      pending = grouped.filter_map do |target, definitions|
        next if definitions.size != 1 || excluded_targets.include?(target)
        next if allowed_targets && !allowed_targets.include?(target)
        calc = definitions.first
        next if calc["formula"].blank?
        references = FormulaEvaluator::Tokenizer.call(calc["formula"].to_s).filter_map do |token|
          resolve_key(token[:value]).to_s if token[:type] == :identifier
        end.uniq
        [target, calc, references & calculated_targets]
      end

      until pending.empty?
        ready, pending = pending.partition { |_, _, dependencies| (dependencies & pending.map(&:first)).empty? }
        break if ready.empty? # Cycles and their dependents stay absent.

        ready.each do |target, calc, dependencies|
          next unless dependencies.all? { |dependency| results.key?(dependency) }
          result = Pages::FormulaEvaluator.evaluate(calc["formula"], formula_value_map(inputs.merge(results)))
          next if result.nil?
          result = apply_format(result, calc["format"]) if calc["format"].is_a?(Hash)
          results[target] = result
        end
      end

      results
    end

    # Validates that no hidden fields have values in the submission.
    # Returns an array of error messages for any violations.
    #
    # @param params [Hash] submitted form params
    # @return [Array<String>] validation errors
    def validate_submission(params)
      errors = []
      hidden = compute_hidden_fields(params)

      hidden.each do |field_id|
        if params.key?(field_id) && params[field_id].present?
          errors << "Field '#{field_id}' should not be submitted when hidden"
        end
      end

      errors
    end

    private

    def flatten_fields(fields)
      fields.flat_map do |field|
        next [] unless field.is_a?(Hash)
        field["field_type"] == "columns" ? flatten_fields(Array(field["columns"]).flat_map { |column| Array(column["fields"]) }) : [field]
      end
    end

    def calculated_targets
      @calculated_targets ||= calculations.filter_map do |calc|
        resolve_key(calc["target_field_id"]).to_s if calc.is_a?(Hash) && calc["target_field_id"].present?
      end.uniq
    end

    def calculated_input_keys
      calculated_targets + @field_slug_map.filter_map { |id, slug| id.to_s if calculated_targets.include?(slug) }
    end

    # Evaluates a condition tree (mirrors JS ConditionEvaluator.evaluate)
    def evaluate_conditions(conditions, values)
      return true if conditions.nil? || conditions.empty?

      groups = conditions["groups"] || []
      return true if groups.empty?

      group_results = groups.map { |group| evaluate_group(group, values) }

      if conditions["logic"] == "all"
        group_results.all?
      else
        group_results.any?
      end
    end

    def evaluate_group(group, values)
      items = group["items"] || []
      return true if items.empty?

      item_results = items.map { |item| evaluate_condition(item, values) }

      if group["logic"] == "all"
        item_results.all?
      else
        item_results.any?
      end
    end

    def evaluate_condition(condition, values)
      key = resolve_key(condition["field_id"])
      field_value = values[key.to_s] || values[key&.to_sym]
      compare_value = condition["value"]

      case condition["operator"]
      when "equals"
        field_value.to_s == compare_value.to_s
      when "not_equals"
        field_value.to_s != compare_value.to_s
      when "contains"
        field_value.to_s.include?(compare_value.to_s)
      when "not_contains"
        !field_value.to_s.include?(compare_value.to_s)
      when "starts_with"
        field_value.to_s.start_with?(compare_value.to_s)
      when "ends_with"
        field_value.to_s.end_with?(compare_value.to_s)
      when "greater_than"
        return false if field_value.blank?
        field_value.to_f > compare_value.to_f
      when "less_than"
        return false if field_value.blank?
        field_value.to_f < compare_value.to_f
      when "greater_or_equal"
        return false if field_value.blank?
        field_value.to_f >= compare_value.to_f
      when "less_or_equal"
        return false if field_value.blank?
        field_value.to_f <= compare_value.to_f
      when "between"
        return false if field_value.blank?
        return false unless compare_value.is_a?(Array) && compare_value.size >= 2
        num = field_value.to_f
        num >= compare_value[0].to_f && num <= compare_value[1].to_f
      when "is_empty"
        field_value.blank?
      when "is_not_empty"
        field_value.present?
      when "is_selected"
        if field_value.is_a?(Array)
          field_value.include?(compare_value)
        else
          field_value.to_s == compare_value.to_s
        end
      when "is_not_selected"
        if field_value.is_a?(Array)
          !field_value.include?(compare_value)
        else
          field_value.to_s != compare_value.to_s
        end
      when "matches_regex"
        field_value.to_s.match?(Regexp.new(compare_value.to_s))
      else
        false
      end
    rescue RegexpError
      false
    end

    # Translates a page-builder field id to its property_slug (the key used in
    # submitted params / stored entry data). Passes unknown keys through so
    # slug-keyed or id-keyed callers both work.
    def resolve_key(id)
      @field_slug_map[id] || id
    end

    # Formula reference tokens are {field_id}; submitted values are slug-keyed.
    # Provide both keys so a formula resolves whether it references the field id
    # or the slug directly.
    def formula_value_map(values)
      map = values.dup
      @field_slug_map.each do |field_id, slug|
        map[field_id] = values[slug] if values.key?(slug)
      end
      map
    end

    def apply_format(value, format)
      case format["type"]
      when "currency"
        decimals = format["decimals"] || 2
        value.to_f.round(decimals)
      when "number"
        decimals = format["decimals"] || 0
        value.to_f.round(decimals)
      when "percent", "percentage"
        (value.to_f * 100).round(format["decimals"] || 1)
      else
        value
      end
    end
  end
end
