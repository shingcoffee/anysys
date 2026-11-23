# frozen_string_literal: true

module Pages
  # Validates the rules & calculations stored in Page#configuration_json against
  # the fields actually present on the page. Pure PORO — no AR, no tenancy logic
  # (the page is already customer-scoped by the controller).
  class ConfigurationValidator
    FUNCTION_ALLOWLIST = %w[
      SUM SUBTRACT MULTIPLY DIVIDE MIN MAX AVERAGE ROUND FLOOR CEIL ABS MOD
      IF AND OR NOT SWITCH
      CONCAT UPPER LOWER TRIM LENGTH LEFT RIGHT
      TODAY NOW YEAR MONTH DAY DATE_DIFF DATE_ADD
    ].freeze

    FIELD_REF = /\{([a-zA-Z0-9_]+)\}/

    attr_reader :errors

    def initialize(configuration)
      @config = configuration || {}
      @errors = []
    end

    def valid?
      @errors = []
      unless @config.is_a?(Hash)
        @errors << I18n.t("maint_core.pages.configuration_errors.must_be_object")
        return false
      end

      validate_rules
      validate_calculations
      @errors.empty?
    end

    private

    def hashes(value)
      Array(value).grep(Hash)
    end

    def field_ids
      @field_ids ||= hashes(@config["pages"]).flat_map { |p| hashes(p["fields"]) }
                                            .map { |f| f["id"] }.compact.to_set
    end

    def page_ids
      @page_ids ||= hashes(@config["pages"]).map { |p| p["id"] }.compact.to_set
    end

    def validate_rules
      rules = @config["rules"]

      if rules && !rules.is_a?(Array)
        @errors << I18n.t("maint_core.pages.configuration_errors.rules_must_be_array")
        return
      end

      Array(rules).each_with_index do |rule, idx|
        unless rule.is_a?(Hash)
          @errors << I18n.t("maint_core.pages.configuration_errors.rule_must_be_hash", index: idx + 1) if rule.present?
          next
        end

        @errors << I18n.t("maint_core.pages.configuration_errors.rule_missing_id", index: idx + 1) if rule["id"].blank?
        @errors << I18n.t("maint_core.pages.configuration_errors.rule_missing_conditions", index: idx + 1) unless rule.key?("conditions")
        @errors << I18n.t("maint_core.pages.configuration_errors.rule_missing_actions", index: idx + 1) unless rule.key?("actions")

        name = rule["name"].presence || rule["id"]
        hashes(rule.dig("conditions", "groups")).each do |group|
          hashes(group["items"]).each do |item|
            next if item["field_id"].blank?
            unless field_ids.include?(item["field_id"])
              @errors << I18n.t("maint_core.pages.configuration_errors.rule_unknown_condition_field", name: name, field: item["field_id"])
            end
          end
        end
        hashes(rule["actions"]).each do |action|
          next if action["target_id"].blank?
          unless field_ids.include?(action["target_id"]) || page_ids.include?(action["target_id"])
            @errors << I18n.t("maint_core.pages.configuration_errors.rule_unknown_action_field", name: name, field: action["target_id"])
          end
        end
      end
    end

    def validate_calculations
      raw_calcs = @config["calculations"]

      if raw_calcs && !raw_calcs.is_a?(Array)
        @errors << I18n.t("maint_core.pages.configuration_errors.calculations_must_be_array")
        return
      end

      calcs = Array(raw_calcs)

      calcs.each_with_index do |calc, idx|
        unless calc.is_a?(Hash)
          @errors << I18n.t("maint_core.pages.configuration_errors.calculation_must_be_hash", index: idx + 1) if calc.present?
          next
        end

        @errors << I18n.t("maint_core.pages.configuration_errors.calculation_missing_target", index: idx + 1) if calc["target_field_id"].blank?
        @errors << I18n.t("maint_core.pages.configuration_errors.calculation_missing_formula", index: idx + 1) if calc["formula"].blank?

        label   = calc["target_field_id"].presence || calc["id"]
        formula = calc["formula"].to_s

        if calc["target_field_id"].present? && !field_ids.include?(calc["target_field_id"])
          @errors << I18n.t("maint_core.pages.configuration_errors.calculation_unknown_target", label: label, field: calc["target_field_id"])
        end

        formula.scan(FIELD_REF).flatten.uniq.each do |ref|
          @errors << I18n.t("maint_core.pages.configuration_errors.calculation_unknown_formula_field", label: label, field: ref) unless field_ids.include?(ref)
        end

        formula.scan(/\b([A-Z][A-Z0-9_]*)\s*\(/).flatten.uniq.each do |fn|
          @errors << I18n.t("maint_core.pages.configuration_errors.calculation_unknown_function", label: label, function: fn) unless FUNCTION_ALLOWLIST.include?(fn)
        end

        if formula.count("(") != formula.count(")")
          @errors << I18n.t("maint_core.pages.configuration_errors.calculation_unbalanced", label: label)
        end
      end

      detect_cycles(hashes(calcs))
    end

    # Builds target_field_id -> [referenced field ids that are themselves calc targets]
    # and runs a DFS cycle check.
    def detect_cycles(calcs)
      targets = calcs.map { |c| c["target_field_id"] }.compact.to_set
      graph = {}
      calcs.each do |calc|
        tgt = calc["target_field_id"]
        next if tgt.blank?
        refs = calc["formula"].to_s.scan(FIELD_REF).flatten.uniq.select { |r| targets.include?(r) }
        graph[tgt] = refs
      end

      visiting = Set.new
      visited  = Set.new
      cycle = lambda do |node|
        return false if visited.include?(node)
        return true  if visiting.include?(node)
        visiting << node
        found = false
        Array(graph[node]).each do |n|
          if cycle.call(n)
            found = true
            break
          end
        end
        visiting.delete(node)
        visited << node
        found
      end

      graph.keys.each do |node|
        if cycle.call(node)
          @errors << I18n.t("maint_core.pages.configuration_errors.calculation_cycle", field: node)
          break
        end
      end
    end
  end
end
