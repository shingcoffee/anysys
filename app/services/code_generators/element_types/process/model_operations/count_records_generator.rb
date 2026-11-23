# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class CountRecordsGenerator < BaseGenerator
          EMPTY_CONDITIONS = { "type" => "group", "joins" => [], "conditions" => [] }.freeze

          generator_metadata do
            description "Counts tenant-scoped rows of the page's bound entity, or of another entity named in entity (for example this member's Bookings). Use query_models to list rows and aggregate_query to sum or average a field. Writes a count, true/false existence, or grouped counts to resultVar. recordScope own keeps only the signed-in member's rows. Fails when onZero is fail and the count is 0, or when entity is not reachable from this customer."
            category :model_operations
            version "3.2.0"
            presentation icon: "M7 20l4-16m2 16l4-16M6 9h14M4 15h14",
                        color: "purple", single_use: false, privileged: false
          end

          config_schema do
            reference :entity, source: :entities,
              description: "Entity to count, by name or id (Bookings). Leave blank to use the page's bound entity. Must be reachable from this customer."
            conditions :conditions, default: EMPTY_CONDITIONS,
              description: "Filter rows before counting. leftOperand is an attribute slug (status, member) or row column (created_at, id). rightOperand is a literal (active) or a ctx path (ctx.model.status, ctx.current_user_id)."
            enum :resultAs, %w[count exists absent], default: "count",
              description: "count (default) writes the number of matching rows. exists writes true when at least one row matches. absent writes true when none match."
            enum :recordScope, %w[all own], default: "all",
              description: "all (default) counts every tenant row. own counts only the signed-in member's rows via People::Ownership. Unsigned runs, and entities no member owns, count 0."
            flag :distinct, default: false, visible: { resultAs: "count" },
              description: "When true, count distinct rows (or distinct distinctField values). Shown only when resultAs is count. Default false."
            entity_attribute :distinctField, of: :bound, visible: { distinct: true },
              description: "Attribute slug whose distinct values are counted (email). Shown when distinct is true. Leave blank to count distinct rows."
            entity_attribute :groupBy, of: :bound, visible: { resultAs: "count" },
              description: "Attribute slug to group the count by (status). Writes a hash of value => count. Shown only when resultAs is count. Leave blank for a single number."
            enum :onZero, %w[zero fail], default: "zero", visible: { resultAs: "count" },
              description: "zero (default) writes 0 and stays on the success track. fail moves to the failure track with count_records.zero when no rows match. Shown only when resultAs is count."
            output :resultVar, default: "count",
              description: "Ctx variable that receives the count, grouped hash, or boolean. Default count."

            validate do |cfg, errors|
              %w[distinctField groupBy].each do |key|
                field = cfg[key].to_s.strip
                next if field.empty?
                next if FlowchartRuntime::ConditionInput.safe_column?(field.delete_prefix("data."))

                errors.add(key.to_sym, :unsafe_column, column: field)
              end
            end
          end

          def generate_body
            lines = tally_lines
            return wrap_entity(lines) if named_entity?

            body(*lines)
          end

          private

          def tally_lines
            call = tally_call
            return [assign(:resultVar, call)] unless fail_on_zero?

            [
              "count = #{call}",
              assign(:resultVar, "count"),
              fail_with('"count_records.zero"', unless: "count != 0"),
              "count"
            ]
          end

          def wrap_entity(lines)
            attempt('"count_records.failed"', FlowchartRuntime::Entries::Error) { lines }
          end

          def fail_on_zero?
            value(:resultAs) == "count" && value(:onZero) == "fail"
          end

          def tally_call
            args = tally_kwargs
            args.empty? ? "FlowchartRuntime::Entries.tally(ctx)" : "FlowchartRuntime::Entries.tally(ctx, #{args})"
          end

          def tally_kwargs
            parts = [conditions_arg]
            parts << "entity: #{read(:entity)}" if named_entity?
            parts << "record_scope: #{read(:recordScope)}" unless value(:recordScope) == "all"
            parts << "result_as: #{read(:resultAs)}" unless value(:resultAs) == "count"
            parts << "distinct: true" if value(:resultAs) == "count" && value(:distinct)
            parts << "distinct_field: #{read(:distinctField)}" if value(:resultAs) == "count" && value(:distinct) && value(:distinctField).to_s.strip.present?
            parts << "group_by: #{read(:groupBy)}" if value(:resultAs) == "count" && value(:groupBy).to_s.strip.present?
            parts.compact.join(", ")
          end

          def named_entity?
            value(:entity).to_s.strip.present?
          end

          def conditions_arg
            conditions = value(:conditions)
            return if blank_conditions?(conditions)

            "conditions: #{literal(conditions)}"
          end

          def blank_conditions?(conditions)
            return true if conditions.blank?
            return true if conditions.is_a?(Array) && conditions.empty?
            return false unless conditions.respond_to?(:[])

            conditions["type"] == "group" && Array(conditions["conditions"]).empty?
          end
        end
      end
    end
  end
end
