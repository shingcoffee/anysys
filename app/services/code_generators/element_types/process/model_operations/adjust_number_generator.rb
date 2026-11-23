# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class AdjustNumberGenerator < BaseGenerator
          generator_metadata do
            description "Takes from or adds to a number field on a loaded EntityEntry and saves it through Entries::Save, reloading the stored row under a lock so concurrent submits cannot both spend the same stock. Use this for seats left, inventory, or a running total; use set_record_fields to assign without saving, or update_model to persist other attributes. Reads modelVariable, field, direction, and amount. Writes the new number to resultVar. Refuses the run (adjust_number.below_minimum / above_maximum) when the result would pass minimum or maximum, showing message on errorField; other write errors fail as adjust_number.failed."
            category :model_operations
            version "1.1.0"
            presentation icon: "M12 6v6m0 0v6m0-6h6m-6 0H6", color: "indigo", single_use: false, privileged: false
          end

          config_schema do
            input :modelVariable, required: true, example: "product",
                  description: "Ctx path of the loaded EntityEntry to change, such as product after referenced_record. Not a person id or a hash."
            literal :field, required: true, example: "stock",
                    description: "Slug of the number attribute to change, such as stock or seats_left. Must be a writable field of that record's entity."
            enum :direction, %w[subtract add], default: "subtract",
                 description: "subtract takes amount away (booked seats, sold stock). add increases the stored number (returning stock, adding points)."
            expression :amount, required: true, example: "ctx[:model].quantity",
                       description: "Ruby expression for how much to take or add, such as ctx[:model].quantity. Must evaluate to an integer or decimal."
            expression :minimum, example: "0",
                       description: "Ruby expression for the lowest allowed result, commonly 0. Omit for no floor. A result below this refuses the submit and writes nothing."
            expression :maximum, group: :advanced,
                       description: "Ruby expression for the highest allowed result, such as ctx[:product].capacity. Omit for no ceiling. A result above this refuses the submit."
            localized_text :message, group: :advanced,
                           example: { "en" => "Only %{available} left in stock.", "zh-CN" => "库存仅剩 %{available}。" },
                           description: "Localized refusal copy. Placeholder available is how much can still be taken or added. When blank, the default below_minimum / above_maximum message is used."
            literal :errorField, example: "quantity",
                    description: "Form field slug the refusal is shown on, such as quantity (the amount the visitor typed), not the stock field being changed."
            output :resultVar, default: "adjusted_value",
                   description: "Ctx variable that receives the new stored number after a successful save, such as adjusted_value."

            validate do |cfg, errors|
              %w[field errorField].each do |name|
                slug = cfg[name].to_s.strip
                errors.add(name.to_sym, :invalid_identifier) unless slug.empty? || ConfigSchema::IDENT_SEGMENT.match?(slug)
              end
            end
          end

          def generate_body
            attempt('"adjust_number.failed"', FlowchartRuntime::Entries::Error) do
              ["adjusted = FlowchartRuntime::Entries.adjust(#{adjust_args})", "next false if adjusted == false",
               assign(:resultVar, "adjusted"), "true"]
            end
          end

          private

          def adjust_args
            message = value(:message)
            english = message.is_a?(Hash) ? (message["en"] || message[:en]).to_s.strip : ""
            ["ctx", read(:modelVariable), read(:field), "amount: #{read(:amount)}",
             ("subtract: true" if value(:direction) == "subtract"),
             ("minimum: #{read(:minimum)}" if value(:minimum).to_s.strip.present?),
             ("maximum: #{read(:maximum)}" if value(:maximum).to_s.strip.present?),
             ("message: #{read(:message)}" if english.present?),
             ("field: #{read(:errorField)}" if value(:errorField).to_s.strip.present?)].compact.join(", ")
          end
        end
      end
    end
  end
end
