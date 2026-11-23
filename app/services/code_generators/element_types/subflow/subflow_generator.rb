# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Subflow
      class SubflowGenerator < BaseGenerator
        generator_metadata do
          description "Runs another launched flowchart as one step, compiled to a Trailblazer Subprocess. The child " \
                      "sees every variable of this run plus the named inputs, and everything it writes comes back " \
                      "under the same names. When the child refuses, this run refuses with the child's messages; " \
                      "otherwise the run continues along the subflow's single outgoing connection. Use it to reuse " \
                      "a shared routine such as notifying an approver or recalculating totals."
          category :flow_control
          version "1.1.0"
        end

        config_schema do
          reference :flowchartId, source: :flowcharts, required: true, example: 1,
                    description: "Id of the launched flowchart to run. It must belong to the same customer or be " \
                                 "shared, and must not lead back to this flowchart."
          mapping :inputVariables, key: :output, value: :expression, default: [],
                                   example: [{ "key" => "order", "value" => "ctx[:model]" }],
                                   description: "Named inputs the child reads: key is the variable name inside " \
                                                "the child (ctx[:key]), value is an expression in this flowchart. " \
                                                "Inputs exist only while the child runs; leave empty when the " \
                                                "names already match."

          validate do |cfg, errors|
            names = CodeGenerators::Shared::KeyValueList.pairs(cfg["inputVariables"]).map(&:first)
            duplicate = names.find { |name| names.count(name) > 1 }
            errors.add(:inputVariables, :duplicate_input, value: duplicate) if duplicate
          end
        end

        def generate_body
          nil
        end

        # Trailblazer variable-mapping options for the Subprocess declaration.
        # Inject keeps the default input (the whole ctx) and adds each named
        # input; only what the child writes is merged back.
        def variable_mapping
          safe_expression_pairs(value(:inputVariables)).filter_map do |name, expression|
            next unless safe_ident?(name)

            "Inject(:#{name}, override: true) => ->(ctx, **) { #{emit_expression(expression)} }"
          end
        end
      end
    end
  end
end
