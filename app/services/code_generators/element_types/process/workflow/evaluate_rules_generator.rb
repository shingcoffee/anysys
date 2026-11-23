# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Workflow
        class EvaluateRulesGenerator < BaseGenerator
          HIT_POLICIES = FlowchartRuntime::RulesTable::HIT_POLICIES
          ON_NO_MATCH = %w[default fail].freeze

          generator_metadata do
            description "Evaluates a decision table of condition/result rows with DMN-style hit policies for pricing tiers, eligibility, routing, or scoring. Use first for the first matching row, collect for every match, sum/min/max/count for numeric matches, and any when every match must return the same value. Use transition_state to move a status, or select_assignee to pick a person. Reads nothing from ctx except what the row expressions themselves read. Writes the decision value to resultVar and 1-based matched row numbers to matchedVar. Refuses evaluate_rules.no_match, non_numeric, or any_conflict."
            category :workflow
            version "1.1.0"
            presentation icon: "M3 10h18M3 14h18m-9-4v8m-7 0h14a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z",
                          color: "violet", single_use: false, privileged: false
          end

          config_schema do
            mapping :rules, key: :expression, value: :expression, required: true,
                    example: [{ "key" => "ctx[:amount].to_d > 1000", "value" => '"vip"' },
                              { "key" => "true", "value" => '"standard"' }],
                    description: "Decision-table rows in order. Each key is a Ruby condition over ctx (for example ctx[:amount].to_d > 1000) and each value is the result expression (for example \"vip\"). first stops at the first true condition; other policies collect every true row. A catch-all row uses true as the condition."
            enum :hitPolicy, HIT_POLICIES, default: "first",
                 description: "How matching rows combine. first: first match only. collect: array of all results. sum/min/max: numeric aggregate (BigDecimal). count: how many rows matched (results are not evaluated). any: all matches must be equal, otherwise the step fails."
            flag :uniqueResults, default: false, visible: { hitPolicy: "collect" },
                 description: "When hitPolicy is collect, drop duplicate values from the result array while keeping the matched row numbers. Off (default) keeps duplicates."
            expression :defaultValue, default: "nil", visible: { onNoMatch: "default" },
                       description: "Ruby expression used when nothing matches and onNoMatch is default, such as \"standard\" or nil. Ignored when onNoMatch is fail."
            enum :onNoMatch, ON_NO_MATCH, default: "default",
                 description: "When no rule matches: default writes defaultValue to resultVar and continues; fail refuses the run as evaluate_rules.no_match."
            output :resultVar, default: "rule_result",
                   description: "Ctx variable later steps read for the decision result, such as rule_result. Shape depends on hitPolicy: a single value, an array (collect), or a number (sum/min/max/count)."
            output :matchedVar, default: "matched_rules", group: :advanced,
                   description: "Ctx variable for the 1-based row numbers that matched, such as matched_rules. Empty array when nothing matched and onNoMatch is default."
            validate do |_cfg, errors|
              rows = value(:rules)
              next unless rows.is_a?(Array)

              errors.add(:rules, :required) if rows.empty?
            end
          end

          def generate_body
            attempt('"evaluate_rules.failed"', FlowchartRuntime::RulesTable::Error) do
              [
                "rules = #{rules_source}",
                "result = FlowchartRuntime::RulesTable.evaluate(#{evaluate_args})",
                "next false unless result",
                assign(:resultVar, "result[:result]"),
                assign(:matchedVar, "result[:matched]"),
                "result"
              ]
            end
          end

          private

          def evaluate_args
            [
              "ctx",
              "rules",
              "hit_policy: #{read(:hitPolicy)}",
              ("default_value: #{emit_expression(value(:defaultValue).to_s.strip)}" unless default_is_nil? || value(:onNoMatch).to_s == "fail"),
              ("on_no_match: #{read(:onNoMatch)}" unless value(:onNoMatch).to_s == "default"),
              ("unique_results: #{read(:uniqueResults)}" if value(:hitPolicy).to_s == "collect" && value(:uniqueResults))
            ].compact.join(", ")
          end

          def rules_source
            items = Array(value(:rules)).filter_map do |row|
              next unless row.is_a?(Hash)

              cond = (row["key"] || row[:key]).to_s
              result = (row["value"] || row[:value]).to_s
              next if cond.strip.empty? && result.strip.empty?
              raise_unsafe_value!(:rules) unless safe_expression?(cond) && safe_expression?(result)

              "[-> { #{emit_expression(cond.strip)} }, -> { #{emit_expression(result.strip)} }]"
            end
            return "[]" if items.empty?
            return "[#{items.first}]" if items.one?

            "[\n#{items.map { |item| "  #{item}" }.join(",\n")}\n]"
          end

          def default_is_nil?
            raw = value(:defaultValue).to_s.strip
            raise_unsafe_value!(:defaultValue) unless safe_expression?(raw)

            raw.empty? || raw == "nil"
          end
        end
      end
    end
  end
end
