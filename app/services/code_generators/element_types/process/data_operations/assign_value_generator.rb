# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class AssignValueGenerator < BaseGenerator
          VALUE_TYPES = %w[
            string integer float boolean array hash expression null
            ctx_ref first_present
          ].freeze

          generator_metadata do
            description "Writes a value into the ctx variable named by resultVar. Use this to set a constant, copy another ctx path (ctx_ref), evaluate a short Ruby expression, or pick the first non-blank of several fields (first_present, e.g. preferred_name then name). Use generate_id for identifiers, calculate for aggregates over lists, and map_value to translate a status into a label. Reads the configured source; writes resultVar. Assigning nil or false still succeeds. Fails only when a required field is missing at design time."
            category :data_operations
            version "3.0.0"
            presentation icon: "M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7",
                         color: "blue", single_use: false, privileged: false
          end

          config_schema do
            output :resultVar, default: "assigned",
                   description: "Ctx variable later steps read. Example: display_name."
            enum :valueType, VALUE_TYPES, default: "expression",
                 description: "Kind of value to write. string/integer/float/boolean/array/hash are literals; expression is Ruby such as ctx[:count].to_i + 1; null writes nil; ctx_ref copies another path; first_present picks the first non-blank candidate."
            expression :valueExpression, example: "ctx[:count].to_i + 1", visible: { valueType: "expression" },
                       description: "Ruby expression stored in resultVar when valueType is expression. Example: ctx[:qty].to_i * ctx[:unit_price].to_f."
            literal :stringValue, default: "", visible: { valueType: "string" },
                    description: "Literal string stored when valueType is string. Example: pending."
            integer :integerValue, default: 0, visible: { valueType: "integer" },
                    description: "Literal integer stored when valueType is integer. Example: 0 or 42."
            decimal :floatValue, default: 0.0, visible: { valueType: "float" },
                    description: "Literal number stored when valueType is float. Example: 19.99."
            flag :booleanValue, default: false, visible: { valueType: "boolean" },
                 description: "Literal true or false stored when valueType is boolean. Default false."
            list :arrayValue, item: :literal, default: [], visible: { valueType: "array" },
                 description: "Literal list stored when valueType is array. Example: pending, paid."
            mapping :hashValue, key: :literal, value: :literal, default: [], visible: { valueType: "hash" },
                    description: "Literal key/value pairs stored when valueType is hash. Example: status=draft."
            input :ctxRefVariable, example: "source", visible: { valueType: "ctx_ref" },
                  description: "Existing ctx path to copy when valueType is ctx_ref. Example: order.status or source."
            list :candidates, item: :input, example: %w[preferred_name name], visible: { valueType: "first_present" },
                 description: "Ctx paths tried in order until one is present (not blank). Example: preferred_name, name."
            list :literalCandidates, item: :literal, default: [], visible: { valueType: "first_present" },
                 description: "Fallback literals tried after candidates. Example: Guest. Empty means no literal fallback."
            requires :valueExpression, when: { valueType: "expression" }
            requires :ctxRefVariable, when: { valueType: "ctx_ref" }
            requires :candidates, when: { valueType: "first_present" }
          end

          def generate_body
            body(
              assign("resultVar", value_source),
              "true"
            )
          end

          private

          def value_source
            case value("valueType").to_s
            when "string" then read("stringValue")
            when "integer" then read("integerValue")
            when "float" then read("floatValue")
            when "boolean" then read("booleanValue")
            when "array" then literal(normalized_array)
            when "hash" then literal(CodeGenerators::Shared::KeyValueList.to_hash(value("hashValue")))
            when "null" then "nil"
            when "ctx_ref" then read("ctxRefVariable")
            when "first_present" then first_present_call
            else
              read("valueExpression")
            end
          end

          def first_present_call
            literals = read("literalCandidates")
            args = ["ctx", read("candidates")]
            args << "literals: #{literals}" unless literals == "[]"
            "FlowchartRuntime::Collections.first_present_from_ctx(#{args.join(", ")})"
          end

          def normalized_array
            items = value("arrayValue")
            return [] unless items.is_a?(Array)

            if items.any? && items.all?(Hash)
              CodeGenerators::Shared::KeyValueList.pairs(items).map { |key, val| val.nil? ? key : val }
            else
              items
            end
          end
        end
      end
    end
  end
end
