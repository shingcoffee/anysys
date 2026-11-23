# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class NextSequenceNumberGenerator < BaseGenerator
          PERIODS = FlowchartRuntime::Sequence::PERIODS
          DATE_SEGMENTS = FlowchartRuntime::Sequence::DATE_SEGMENTS

          generator_metadata do
            description "Allocates the next tenant-scoped sequence number for a named counter, formatted with prefix, zero-padding, optional date segment, and suffix (for example ORD-2026-000001). Use this after save_model for a reference number the visitor does not type; use adjust_number to change a stored quantity on a record. resetEvery starts a new counter per calendar period; dateSegment only inserts a display date and does not reset the counter. Allocation runs inside the submit transaction, so a refused run does not consume a number; concurrent submits still receive distinct values. Writes the formatted string to resultVar. Fails as next_sequence_number.failed when customer_id or name is missing."
            category :model_operations
            version "1.2.0"
            presentation icon: "M7 20l4-16m2 16l4-16M6 9h14M4 15h14",
                        color: "purple", single_use: false, privileged: false
          end

          config_schema do
            literal :sequenceName, required: true, example: "order", placeholder: true,
                    description: "Identifier of this customer's counter, such as order or invoice. Same name, same period bucket, one sequence. Must be a Ruby identifier (letters, digits, underscore)."
            literal :prefix, default: "", placeholder: true, example: "INV-",
                    description: "Text prepended to the formatted number, such as INV- or ORD-. May be blank."
            literal :suffix, default: "", placeholder: true, example: "-CN",
                    description: "Text appended after the padded number, such as -CN. May be blank."
            integer :padding, min: 1, max: 12, default: 6,
                    description: "Zero-pad width of the numeric part (1-12, default 6). 6 yields 000001."
            integer :startAt, min: 1, max: 1_000_000, default: 1, group: :advanced,
                    description: "First number issued for a new period bucket (1-1000000, default 1). Applied as startAt + (count-1)*step."
            integer :step, min: 1, max: 1000, default: 1, group: :advanced,
                    description: "Amount added after each issue (1-1000, default 1). Use 5 to get 100, 105, 110 when startAt is 100."
            enum :resetEvery, PERIODS, default: "never",
                 description: "When a new counter starts for this name: never is one running counter. year/month/day/week/quarter each use a fresh last_value for that calendar bucket (Time.zone)."
            enum :dateSegment, DATE_SEGMENTS, default: "none",
                 description: "Optional date inserted between prefix and the padded number: none, year (2026), year_month (2026-11), or date (2026-11-23). Display only; it does not reset the counter."
            literal :separator, default: "-", placeholder: true, visible: { dateSegment: %w[year year_month date] },
                    description: "Separator between the date segment and the padded number, default -. Ignored when dateSegment is none."
            output :resultVar, default: "sequence_number",
                   description: "Ctx variable that receives the formatted string, such as sequence_number. Assign it onto the record with update_model."
            validate do |cfg, errors|
              name = cfg["sequenceName"].to_s
              next if name.empty?
              next if CodeGenerators::ConfigSchema::IDENT_SEGMENT.match?(name)

              errors.add(:sequenceName, :invalid_identifier)
            end
          end

          def generate_body
            attempt('"next_sequence_number.failed"', FlowchartRuntime::Sequence::Error) do
              [assign(:resultVar, "FlowchartRuntime::Sequence.next(ctx, #{sequence_args})")]
            end
          end

          private

          def sequence_args
            parts = ["name: #{read(:sequenceName)}", "period: #{read(:resetEvery)}"]
            parts << "prefix: #{read(:prefix)}" unless value(:prefix).to_s.empty?
            parts << "suffix: #{read(:suffix)}" unless value(:suffix).to_s.empty?
            parts << "padding: #{read(:padding)}" unless value(:padding) == FlowchartRuntime::Sequence::DEFAULT_PADDING
            parts << "start_at: #{read(:startAt)}" unless value(:startAt) == FlowchartRuntime::Sequence::DEFAULT_START_AT
            parts << "step: #{read(:step)}" unless value(:step) == FlowchartRuntime::Sequence::DEFAULT_STEP
            parts << "date_segment: #{read(:dateSegment)}" unless value(:dateSegment) == "none"
            parts << "separator: #{read(:separator)}" unless value(:separator) == FlowchartRuntime::Sequence::DEFAULT_SEPARATOR
            parts.join(", ")
          end
        end
      end
    end
  end
end
