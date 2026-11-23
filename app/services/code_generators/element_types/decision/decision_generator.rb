# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Decision
      class DecisionGenerator < BaseGenerator
        include CodeGenerators::Shared::ConditionBuilder

        ROUTE_BY_VALUE = "value"
        ROUTE_BY_CONDITION = "condition"
        YES_MATCH = "true"
        NO_MATCH = "false"

        generator_metadata do
          description "Routes the run down one of its outgoing connections, compiled to a Railway step that " \
                      "returns one Routes signal per branch. routeBy condition is a Yes/No question; routeBy value " \
                      "is a case/when on subject. It only routes: it never writes variables or refuses, so put " \
                      "the work in Process steps before or after it."
          category :flow_control
          version "2.0.2"
        end

        config_schema do
          enum :routeBy, %w[value condition], default: "condition", required: true,
                         description: "condition takes the connection whose matchValue is \"true\" when the " \
                                      "condition holds, else \"false\" or the blank Otherwise. value takes the " \
                                      "connection whose matchValue equals subject as text."
          expression :subject, visible: { routeBy: "value" }, required: true,
                     example: "ctx[:status]", placeholder: true,
                     description: "Value compared as text with each connection's matchValue, such as " \
                                  "ctx[:model].status or ctx[:params][:plan]; no match takes the blank Otherwise."
          conditions :condition, visible: { routeBy: "condition" }, required: true,
                     description: "Yes/No test; leftOperand is a ctx path such as ctx.model.status and " \
                                  "rightOperand a literal or another ctx path.",
                     example: {
                       "type" => "group",
                       "joins" => [],
                       "conditions" => [
                         { "kind" => "field", "leftOperand" => "ctx.status", "operator" => "==", "rightOperand" => "active" }
                       ]
                     }

          validate do |cfg, errors|
            errors.concat(decision_topology_errors)
            errors.concat(ConditionRules.errors(cfg["condition"], field: "condition", required: true)) if route_by_condition?(cfg)
          end
        end

        def generate_body
          errors = validate_config(config)
          if errors.any?
            raise ArgumentError, "Invalid Decision configuration: #{errors.map(&:to_s).join('; ')}"
          end

          if route_by_value?(config)
            subject = read(:subject)
            return "#{subject}.to_s" unless topology_provided?

            build_value_switch(subject, topology_branches)
          else
            cond_code = build_structured_condition(value(:condition))
            return cond_code unless topology_provided?

            build_boolean_switch(cond_code, topology_branches)
          end
        end

        private

        def route_by_value?(cfg)
          route_by(cfg) == ROUTE_BY_VALUE
        end

        def route_by_condition?(cfg)
          route_by(cfg) == ROUTE_BY_CONDITION
        end

        def route_by(cfg)
          raw = cfg && (cfg["routeBy"] || cfg[:routeBy])
          raw.to_s.presence || ROUTE_BY_CONDITION
        end

        def topology_source
          return unless context.is_a?(Hash)

          context[:flowchart_topology] || context["flowchart_topology"]
        end

        def topology_provided?
          topology_source.is_a?(Hash)
        end

        def topology
          value = topology_source
          value.is_a?(Hash) ? value.with_indifferent_access : {}.with_indifferent_access
        end

        def topology_branches
          Array(topology[:outgoing_branches])
        end

        def decision_error(field, code, **vars)
          CodeGenerators::ConfigError.new(
            field: field.to_s,
            code: code.to_sym,
            message: I18n.t("flowchart_elements.decision.errors.#{code}", **vars)
          )
        end

        def decision_topology_errors
          return [] unless topology_provided?

          errors = []
          branches = topology_branches
          errors << decision_error(:branches, :too_few_branches) if branches.size < 2

          stripped = branches.map { |branch| branch_match(branch) }
          errors << decision_error(:branches, :multiple_otherwise) if stripped.count { |match| match.empty? } > 1
          errors << decision_error(:branches, :duplicate_match_value) if stripped.uniq.size != stripped.size

          if route_by_condition?(config)
            errors.concat(condition_branch_errors(stripped))
          end

          errors
        end

        def condition_branch_errors(stripped)
          errors = []
          concrete = stripped.reject(&:empty?)
          unless concrete.all? { |match| match == YES_MATCH || match == NO_MATCH }
            errors << decision_error(:branches, :invalid_condition_match)
          end

          has_yes = stripped.include?(YES_MATCH)
          has_no_or_otherwise = stripped.include?(NO_MATCH) || stripped.include?("")
          errors << decision_error(:branches, :missing_yes_branch) unless has_yes && has_no_or_otherwise
          errors
        end

        def branch_match(branch)
          branch && branch["matchValue"].to_s.strip
        end

        def build_value_switch(subject_code, match_values)
          default_signal = branch_signal(default_branch(match_values))
          with_values = match_values.reject { |branch| branch_match(branch).empty? }
          return default_signal if with_values.empty?

          when_clauses = with_values.map { |branch|
            "when #{literal(branch_match(branch))} then #{branch_signal(branch)}"
          }
          <<~RUBY.chomp
            case #{subject_code}.to_s
            #{when_clauses.join("\n")}
            else #{default_signal}
            end
          RUBY
        end

        def build_boolean_switch(cond_code, match_values)
          default = default_branch(match_values)
          truthy = branch_for_bool(match_values, true) || default
          falsy = branch_for_bool(match_values, false) || default
          <<~RUBY.chomp
            if #{cond_code}
              #{branch_signal(truthy)}
            else
              #{branch_signal(falsy)}
            end
          RUBY
        end

        def branch_for_bool(match_values, bool)
          wanted = bool ? YES_MATCH : NO_MATCH
          match_values.find { |branch| branch_match(branch) == wanted }
        end

        def branch_signal(branch)
          branch&.[]("signal").to_s
        end

        def default_branch(match_values)
          match_values.find { |branch| branch_match(branch).empty? } || match_values.last
        end
      end
    end
  end
end
