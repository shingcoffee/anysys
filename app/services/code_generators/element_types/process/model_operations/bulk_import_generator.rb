# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class BulkImportGenerator < BaseGenerator
          MAX_ROWS = FlowchartRuntime::BulkImport::MAX_ROWS

          generator_metadata do
            description "Creates or updates tenant-scoped rows of the bound entity (or entity when set) from sourceVariable hashes. uniqueBy attribute slugs find an existing row; onDuplicateKey skip or update. Field mappings rename source columns to entity attributes. Each row is saved through Entries.save so lifecycle and audience still apply. Writes created/updated/skipped/failed counts to resultVar and skipped-row errors to errorsVar. Fails when the list exceeds 1000 rows, a row fails and onRowError is fail, or entity is not reachable."
            category :model_operations
            version "3.2.0"
            presentation icon: "M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12",
                        color: "green", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "records",
              description: "Ctx path holding an array of row hashes (records). At most 1000 rows. Extra columns are ignored unless fieldMappings is set."
            reference :entity, source: :entities,
              description: "Entity to import into, by name or id. Leave blank to use the page's bound entity. Must be reachable from this customer."
            enum :onDuplicateKey, %w[update skip], default: "skip",
              description: "skip (default) leaves an existing uniqueBy match unchanged. update assigns the row and saves through Entries.save. update requires uniqueBy."
            list :uniqueBy, item: :entity_attribute, default: [],
              description: "Attribute slugs used to find an existing row (email). Empty uniqueBy always creates. Internal columns cannot be used. Required when onDuplicateKey is update."
            mapping :fieldMappings, key: :literal, value: :entity_attribute, default: [],
              description: "Source column name to entity attribute slug pairs (addr => email). Leave empty to use hash keys as attribute slugs."
            enum :recordScope, %w[all own], default: "all",
              description: "all (default) matches existing rows across the tenant. own only matches the signed-in member's rows, so an import cannot update someone else's record; on an entity no member owns it matches none."
            integer :batchSize, min: 1, max: MAX_ROWS, default: 500, group: :advanced,
              description: "Rows committed per batch (1-1000). Default 500. When onRowError is fail, the whole list is one batch so a failure rolls every row back."
            enum :onRowError, %w[fail skip], default: "skip",
              description: "skip (default) records the row error and continues. fail stops, rolls back the import, and moves to the failure track with bulk_import.row_failed."
            output :resultVar, default: "import_result",
              description: "Ctx variable that receives the counts hash (created, updated, skipped, failed, errors). Default import_result."
            output :errorsVar, default: "import_errors", group: :advanced,
              description: "Ctx variable that receives skipped-row errors ({index, message}). Default import_errors. Empty when every row succeeds."

            validate do |cfg, errors|
              keys = Array(cfg["uniqueBy"]).map(&:to_s).reject(&:empty?)
              if cfg["onDuplicateKey"].to_s == "update" && keys.empty?
                errors.add(:uniqueBy, :required)
              end
              internal = keys.select { |key| FlowchartRuntime::Entries::INTERNAL_COLUMNS.include?(key) }
              errors.add(:uniqueBy, :internal_column, columns: internal.join(", ")) if internal.any?
            end
          end

          def generate_body
            body(
              "result = FlowchartRuntime::BulkImport.run(ctx, #{import_kwargs})",
              "return false unless result",
              assign(:resultVar, "result"),
              assign(:errorsVar, "result.is_a?(Hash) ? result[:errors] : []"),
              "result"
            )
          end

          private

          def import_kwargs
            parts = [
              "rows: #{read(:sourceVariable)}",
              "on_duplicate: #{read(:onDuplicateKey)}",
              "unique_by: #{read(:uniqueBy)}"
            ]
            parts << "entity: #{read(:entity)}" if named_entity?
            parts << "record_scope: #{read(:recordScope)}" unless value(:recordScope) == "all"
            parts << "field_mappings: #{read(:fieldMappings)}" if Array(value(:fieldMappings)).any?
            parts << "batch_size: #{read(:batchSize)}" unless value(:batchSize) == FlowchartRuntime::BulkImport::DEFAULT_BATCH_SIZE
            parts << "on_row_error: #{read(:onRowError)}" unless value(:onRowError) == "skip"
            parts.join(", ")
          end

          def named_entity?
            value(:entity).to_s.strip.present?
          end
        end
      end
    end
  end
end
