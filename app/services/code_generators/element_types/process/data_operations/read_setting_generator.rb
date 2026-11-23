# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class ReadSettingGenerator < BaseGenerator
          generator_metadata do
            description "Reads a Constant's option list, or the label for one value, using this customer's override when the constant is shared. Use this to show or branch on configured labels (order status, ticket type); do not use it for entity records (query_models / find_model) or for the signed-in user (load_current_user). constant is the Constant's id or name. returns options writes the array to resultVar; returns label looks up value and writes that option's label, or defaultValue (nil when omitted) when the value is not in the list. Fails as read_setting.failed when the constant is missing or belongs to another tenant."
            category :data_operations
            version "1.2.0"
            presentation icon: "M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4",
              color: "amber", single_use: false, privileged: false
          end

          config_schema do
            reference :constant, source: :constants, required: true, example: 1,
                      description: "Constant to read: its numeric id, or its name such as OrderStatus. Shared constants use this customer's override options when present."
            enum :returns, %w[options label], default: "options",
                 description: "options writes the option list (array of values or {label, value} hashes) to resultVar. label looks up one value and writes that option's display label."
            expression :value, example: "ctx[:params][:status]", visible: { returns: "label" },
                       description: "Ruby expression for the option value whose label is returned, such as ctx[:params][:status] or ctx[:model].status. Required when returns is label."
            expression :defaultValue, default: "nil", visible: { returns: "label" },
                       description: "Ruby expression returned when value is not in this customer's list, such as \"Unknown\". Omit or nil to store nil."
            output :resultVar, default: "constant_options",
                   description: "Ctx variable that receives the option list or the resolved label, such as constant_options."
            requires :value, when: { returns: "label" }
          end

          def generate_body
            body(
              attempt('"read_setting.failed"', FlowchartRuntime::Constants::Error) do
                [
                  assign(:resultVar, constants_call),
                  "true"
                ]
              end
            )
          end

          private

          def constants_call
            if value(:returns) == "label"
              args = ["ctx", read(:constant), read(:value)]
              args << "default: #{read(:defaultValue)}" unless default_is_nil?
              "FlowchartRuntime::Constants.label(#{args.join(', ')})"
            else
              "FlowchartRuntime::Constants.options(ctx, #{read(:constant)})"
            end
          end

          def default_is_nil?
            raw = value(:defaultValue).to_s.strip
            raw.empty? || raw == "nil"
          end
        end
      end
    end
  end
end
