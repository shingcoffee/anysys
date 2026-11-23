# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class TypeCastGenerator < BaseGenerator
          TARGET_TYPES = %w[string integer decimal boolean date datetime array].freeze

          generator_metadata do
            description "Converts a value to a business type using ActiveModel::Type: string, integer, decimal, boolean, date, datetime, or array. Invalid integers such as 'abc' do not become 0; they fail or follow onError (fail, nil, default). Use map_value to translate enums, calculate for numeric aggregates, and parse_data for JSON text. Reads sourceVariable; writes resultVar. Fails with type_cast.failed when onError is fail and the value cannot be cast."
            category :data_operations
            version "3.0.0"
            presentation icon: "M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4", color: "gray",
                          single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "amount",
                  description: "Ctx path of the value to cast. Example: amount or submitted_on."
            output :resultVar, default: "cast_value",
                   description: "Ctx variable later steps read. Example: amount_cents or starts_on."
            enum :targetType, TARGET_TYPES, default: "string",
                 description: "Type to cast to. string/integer/decimal/boolean use ActiveModel::Type; date/datetime parse in Time.zone; array wraps a value or parses a JSON list."
            literal :format, placeholder: true, visible: { targetType: %w[date datetime] },
                    description: "strftime pattern for date and datetime. Example: %Y-%m-%d. Leave blank to use Date.parse / Time.zone.parse."
            literal :timezone, placeholder: true, visible: { targetType: "datetime" },
                    description: "Time zone name for datetime, e.g. UTC or America/New_York. Blank uses Time.zone."
            enum :onError, FlowchartRuntime::Cast::ON_ERRORS, default: "fail",
                 description: "When the value cannot be cast: fail stops the step with type_cast.failed; nil writes nil; default writes defaultValue."
            literal :defaultValue, default: "", placeholder: true, visible: { onError: "default" },
                    description: "Value stored when onError is default. Example: 0 or 1970-01-01. Required for that mode."
            requires :defaultValue, when: { onError: "default" }
          end

          def generate_body
            body(
              attempt('"type_cast.failed"', FlowchartRuntime::Cast::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::Cast.apply(#{apply_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def apply_args
            args = [read(:sourceVariable), "type: #{read(:targetType)}"]
            args << "format: #{read(:format)}" if present_literal?(:format)
            args << "timezone: #{read(:timezone)}" if present_literal?(:timezone)
            args << "on_error: #{read(:onError)}" unless value(:onError) == "fail"
            args << "default_value: #{read(:defaultValue)}" if present_literal?(:defaultValue)
            args.join(", ")
          end

          def present_literal?(name)
            !value(name).to_s.strip.empty?
          end
        end
      end
    end
  end
end
