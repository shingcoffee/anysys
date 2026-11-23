# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class BatchOperationGenerator < BaseGenerator
          EMPTY_CONDITIONS = { "type" => "group", "joins" => [], "conditions" => [] }.freeze
          ITERATING = %w[find_each in_batches each_batch].freeze

          generator_metadata do
            description "Updates, destroys, or iterates tenant-scoped rows from sourceVariable, intersected with the bound entity (or entity when set). Prefer update_all and destroy_all, which write through Entries.save/destroy so lifecycle and audience still apply. find_each and in_batches run stepBody per record; each_batch yields a relation. Writes the processed count to progressVar. Fails when the source cannot be ANDed with the tenant scope, or when entity is not reachable."
            category :model_operations
            version "3.2.0"
            presentation icon: "M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10",
                        color: "purple", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "items",
              description: "Ctx path holding the source relation or collection (items). ANDed with the tenant-scoped entity so another customer's rows cannot be written."
            reference :entity, source: :entities,
              description: "Entity whose rows are batched, by name or id. Leave blank to use the page's bound entity. Must be reachable from this customer."
            enum :operationType, %w[find_each in_batches each_batch update_all destroy_all], default: "find_each",
              description: "find_each (default) and in_batches yield each record to stepBody. each_batch yields a relation. update_all assigns fieldAssignments through Entries.save. destroy_all deletes through Entries.destroy."
            integer :batchSize, min: 1, max: 10_000, default: 1000,
              description: "Records processed per batch (1-10000). Default 1000."
            expression :stepBody, visible: { operationType: ITERATING },
              description: "Ruby run for each record (find_each/in_batches) or batch relation (each_batch). Default saves the record through Entries.save. each_batch defaults to true (count only)."
            mapping :fieldAssignments, key: :entity_attribute, value: :expression,
                    visible: { operationType: "update_all" }, default: [],
              description: "Attribute slug to Ruby expression pairs written on each matching row (status => \"closed\"). Required for update_all. Internal columns cannot be assigned."
            conditions :conditions, default: EMPTY_CONDITIONS,
              description: "Extra filters ANDed onto the tenant-scoped source. leftOperand is an attribute slug (status) or row column (id). rightOperand is a literal or a ctx path (ctx.model.status)."
            enum :recordScope, %w[all own], default: "all",
              description: "all (default) includes every tenant row. own keeps only the signed-in member's rows via People::Ownership. Unsigned runs, and entities no member owns, process none."
            flag :errorCollection, default: false,
              description: "When true, a failed row is stored on ctx[:_batch_errors] and the batch continues. Default false fails the step on the first failed write."
            integer :maxRecords, min: 0, max: 100_000, default: 0, group: :advanced,
              description: "Stop after this many records (0-100000). 0 (default) means no cap."
            flag :stopOnError, default: false, group: :advanced, visible: { errorCollection: true },
              description: "When true with errorCollection, skip remaining records after the first collected error. Default false. Shown when errorCollection is on."
            output :progressVar, default: "progress",
              description: "Ctx variable that receives how many records were processed. Default progress."

            validate do |cfg, errors|
              if cfg["operationType"].to_s == "update_all" && Array(cfg["fieldAssignments"]).empty?
                errors.add(:fieldAssignments, :assignments_required)
              end
              internal = assignment_keys(cfg["fieldAssignments"]).select do |column|
                FlowchartRuntime::Entries::INTERNAL_COLUMNS.include?(column)
              end
              errors.add(:fieldAssignments, :internal_column, columns: internal.join(", ")) if internal.any?
            end
          end

          def generate_body
            attempt('"batch_operation.incompatible_scope"', FlowchartRuntime::Batch::Error) do
              [assign(:progressVar, batch_run)]
            end
          end

          private

          def assignment_keys(raw)
            Array(raw).filter_map do |row|
              next row.to_s if row.is_a?(String) || row.is_a?(Symbol)
              next unless row.is_a?(Hash)

              (row["key"] || row[:key]).to_s.presence
            end
          end

          def batch_run
            call = "FlowchartRuntime::Batch.run(ctx, #{batch_kwargs})"
            return call unless ITERATING.include?(value(:operationType))

            <<~RUBY.chomp
              #{call} do |#{block_arg}|
                #{step_body_source}
              end
            RUBY
          end

          def batch_kwargs
            parts = [
              "source: #{read(:sourceVariable)}",
              "operation: #{read(:operationType)}",
              "batch_size: #{read(:batchSize)}",
              conditions_arg
            ]
            parts << "entity: #{read(:entity)}" if named_entity?
            parts << "record_scope: #{read(:recordScope)}" unless value(:recordScope) == "all"
            assignments = mapping_source(value(:fieldAssignments))
            parts << "assignments: #{assignments}" if assignments
            parts << "collect_errors: true" if value(:errorCollection)
            parts << "max_records: #{read(:maxRecords)}" if value(:maxRecords).to_i.positive?
            parts << "stop_on_error: true" if value(:errorCollection) && value(:stopOnError)
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

          def mapping_source(rows)
            pairs = Array(rows).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              next if key.to_s.blank?

              "#{literal(key.to_s)} => #{emit_expression(row["value"] || row[:value])}"
            end
            "{#{pairs.join(', ')}}" unless pairs.empty?
          end

          def block_arg
            value(:operationType) == "each_batch" ? "batch_rel" : "record"
          end

          def step_body_source
            raw = value(:stepBody).to_s.strip
            return raw if raw.present?
            return "batch_rel" if value(:operationType) == "each_batch"

            "FlowchartRuntime::Entries.save(ctx, record)"
          end
        end
      end
    end
  end
end
