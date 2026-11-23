# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class AggregateQueryGenerator < BaseGenerator
          EMPTY_CONDITIONS = { "type" => "group", "joins" => [], "conditions" => [] }.freeze
          OPERATIONS = %w[sum avg min max count].freeze
          FUNCTIONS = %w[sum average minimum maximum count].freeze

          generator_metadata do
            description "Computes sum, average, min, max, or count over tenant-scoped rows of the bound entity, or of another entity named in entity (for example invoice totals). Use count_records for a plain count and query_models to list rows. Writes a scalar or keyed hash to resultVar. groupByFields groups by attribute slugs; having is an allowlisted aggregate comparison such as SUM(amount) > 100. Fails when entity is not reachable or having is unsafe."
            category :model_operations
            version "4.0.0"
            presentation icon: "M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z",
                        color: "indigo", single_use: false, privileged: false
          end

          config_schema do
            reference :entity, source: :entities,
              description: "Entity to aggregate, by name or id (Invoice). Leave blank to use the page's bound entity. Must be reachable from this customer."
            mapping :aggregations, key: :entity_attribute, value: :literal, default: [],
              description: "Attribute slug to operation pairs (amount => sum, qty => count). Operations: sum, avg, min, max, count. When set, aggregateFunction and aggregateField are ignored."
            enum :aggregateFunction, FUNCTIONS, default: "sum",
              description: "Function used when aggregations is empty. sum (default) totals aggregateField; average/minimum/maximum/count use the matching SQL aggregate."
            entity_attribute :aggregateField, of: :bound, default: "amount",
              description: "Attribute slug to aggregate when aggregations is empty (amount). Default amount. Must be a safe identifier."
            list :groupByFields, item: :entity_attribute, default: [],
              description: "Attribute slugs to group by (status, category). Leave empty for a single scalar. Grouped results are typically a hash of group value => metric."
            literal :having, group: :advanced,
              description: "Allowlisted HAVING comparison applied after grouping, for example SUM(amount) > 100 or COUNT(*) > 1. Rejected unless it matches that shape. Requires groupByFields."
            enum :resultFormat, %w[scalar hash], default: "scalar",
              description: "scalar (default) writes one number (or a grouped hash of group => value). hash writes keyed metrics such as sum_amount. Scalar requires at most one aggregation pair."
            conditions :conditions, default: EMPTY_CONDITIONS,
              description: "Filter rows before aggregating. leftOperand is an attribute slug (status) or row column (created_at, id). rightOperand is a literal (paid) or a ctx path (ctx.model.status)."
            enum :recordScope, %w[all own], default: "all",
              description: "all (default) aggregates every tenant row. own aggregates only the signed-in member's rows via People::Ownership. Unsigned runs, and entities no member owns, aggregate none."
            integer :roundTo, min: 0, max: 10, group: :advanced,
              description: "Decimal places to round numeric results to (0-10). Leave blank to keep full precision. Applied to scalars and hash values."
            output :resultVar, default: "aggregates",
              description: "Ctx variable that receives the scalar, grouped hash, or keyed metrics. Default aggregates."

            validate do |cfg, errors|
              aggregations = normalize_aggregations(cfg["aggregations"])
              aggregations.each do |_field, op|
                next if OPERATIONS.include?(op.to_s) || FUNCTIONS.include?(op.to_s)

                errors.add(:aggregations, :invalid_operation, operation: op)
              end
              if cfg["resultFormat"].to_s == "scalar" && aggregations.size > 1
                errors.add(:resultFormat, :scalar_needs_single_aggregation)
              end
              grouping = Array(cfg["groupByFields"]).any? { |item| item.to_s.strip.present? }
              if cfg["having"].present? && !grouping
                errors.add(:having, :having_needs_group)
              end
              if cfg["having"].present? && !cfg["having"].to_s.strip.match?(FlowchartRuntime::QueryBuilder::SAFE_HAVING_RE)
                errors.add(:having, :invalid_having)
              end
              field = cfg["aggregateField"].to_s.strip
              if field.present? && !safe_group_field?(field)
                errors.add(:aggregateField, :unsafe_column, column: field)
              end
              Array(cfg["groupByFields"]).each do |item|
                next if item.to_s.strip.empty?
                next if safe_group_field?(item)

                errors.add(:groupByFields, :unsafe_column, column: item)
              end
            end
          end

          def generate_body
            call = assign(:resultVar, aggregate_call)
            return wrap_entity([call]) if named_entity?

            call
          end

          private

          def wrap_entity(lines)
            attempt('"aggregate_query.failed"', FlowchartRuntime::Entries::Error) { lines }
          end

          def normalize_aggregations(raw)
            FlowchartRuntime::Entries.send(:normalize_aggregations, raw)
          end

          def safe_group_field?(field)
            value = field.to_s.strip.delete_prefix("data.")
            return false if value.empty?

            FlowchartRuntime::JsonPathValidator.safe_json_path!(value)
            true
          rescue FlowchartRuntime::JsonPathValidator::Error
            false
          end

          def aggregate_call
            args = aggregate_kwargs
            args.empty? ? "FlowchartRuntime::Entries.aggregate(ctx)" : "FlowchartRuntime::Entries.aggregate(ctx, #{args})"
          end

          def aggregate_kwargs
            parts = [conditions_arg]
            parts << "entity: #{read(:entity)}" if named_entity?
            parts << "record_scope: #{read(:recordScope)}" unless value(:recordScope) == "all"
            metrics = normalize_aggregations(value(:aggregations))
            if metrics.any?
              parts << "aggregations: #{read(:aggregations)}"
            else
              parts << "function: #{read(:aggregateFunction)}"
              parts << "field: #{read(:aggregateField)}"
            end
            fields = Array(value(:groupByFields)).reject { |item| item.to_s.empty? }
            parts << "group_by_fields: #{read(:groupByFields)}" if fields.any?
            parts << "having: #{read(:having)}" if value(:having).to_s.strip.present?
            parts << "result_format: #{read(:resultFormat)}" unless value(:resultFormat) == "scalar"
            parts << "round_to: #{read(:roundTo)}" unless value(:roundTo).nil?
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
