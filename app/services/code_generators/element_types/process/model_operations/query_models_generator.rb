# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class QueryModelsGenerator < BaseGenerator
          EMPTY_CONDITIONS = { "type" => "group", "joins" => [], "conditions" => [] }.freeze

          generator_metadata do
            description "Lists tenant-scoped rows of the page's bound entity, or of another entity named in entity (for example Bookings). Use find_model for a single row, count_records for a count, and aggregate_query for sum/avg/min/max. Conditions filter by attribute slug on the left and a literal or ctx path on the right. Writes matching records or plucked values to resultVar and optional page metadata to paginationVar. Fails when onEmpty is fail and nothing matches, or when entity is not reachable from this customer."
            category :model_operations
            version "3.2.0"
            presentation icon: "M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4",
                        color: "purple", single_use: false, privileged: false
          end

          config_schema do
            reference :entity, source: :entities,
              description: "Entity to query, by name or id (Bookings). Leave blank to use the page's bound entity. Must be reachable from this customer."
            conditions :conditions, default: EMPTY_CONDITIONS,
              description: "Filter rows. leftOperand is an attribute slug on the queried entity (status, email) or a row column (created_at, id), never a ctx path. rightOperand is a literal (active) or a ctx path (ctx.model.status, ctx.current_user_id) resolved at run time."
            list :select, item: :entity_attribute, default: [],
              description: "Attribute slugs to return. Required when returns is values (email). When returns is records, a non-empty list projects each row to those slugs."
            enum :returns, %w[records values], default: "records",
              description: "records (default) writes EntityEntry rows, or projected hashes when select is set. values plucks select slugs as scalars (one slug) or arrays (several)."
            enum :recordScope, %w[all own], default: "all",
              description: "all (default) includes every tenant row of the entity. own keeps only the signed-in member's rows via People::Ownership (person, owned, or nested). Unsigned runs, and entities no member owns, see none."
            input :pageVariable, default: "page",
              description: "Ctx path holding the 1-based page number (page, or params.page). Used only when pageSize is set. Defaults to page."
            integer :pageSize, min: 1, max: 200,
              description: "Rows per page (1-200). Leave blank to skip pagination. When set, writes page metadata to paginationVar."
            integer :limit, min: 1, max: 1000,
              description: "Maximum rows to return when pageSize is blank (1-1000). Ignored when paginating."
            literal :orderBy,
              description: "Attribute slug (email, status) or row column (created_at, updated_at, id) to sort by. Leave blank for unordered results. Unsafe names are rejected."
            enum :orderDirection, %w[asc desc], default: "asc",
              description: "Primary sort direction. asc (default) is A-Z / oldest first; desc is Z-A / newest first. Used only when orderBy is set."
            flag :distinct, default: false,
              description: "When true, drop duplicate rows after select and order. Default false."
            enum :onEmpty, %w[empty fail], default: "empty",
              description: "empty (default) writes an empty list and stays on the success track. fail moves to the failure track with query_models.empty when no rows match."
            integer :offset, min: 0, max: 100_000, group: :advanced,
              description: "Rows to skip before limit or the current page (0-100000). Added on top of pagination. Default 0."
            literal :thenOrderBy, group: :advanced,
              description: "Secondary sort attribute slug or column (email) used when the primary sort ties. Same safety rule as orderBy."
            enum :thenOrderDirection, %w[asc desc], default: "asc", group: :advanced,
              description: "Secondary sort direction. asc (default) or desc. Used only when thenOrderBy is set."
            output :resultVar, default: "models",
              description: "Ctx variable that receives the records, projected hashes, or plucked values. Default models."
            output :paginationVar, default: "pagination",
              description: "Ctx variable that receives page metadata (total_count, page, per_page, total_pages, has_next) when pageSize is set. Default pagination."

            validate do |cfg, errors|
              if cfg["returns"].to_s == "values" && Array(cfg["select"]).empty?
                errors.add(:select, :required)
              end
              %w[orderBy thenOrderBy].each do |key|
                order = cfg[key].to_s.strip
                next if order.empty?
                next if FlowchartRuntime::ConditionInput.safe_column?(order.delete_prefix("data."))

                errors.add(key.to_sym, :unsafe_column, column: order)
              end
            end
          end

          def generate_body
            lines = query_lines
            return wrap_entity(lines) if named_entity?

            body(*lines)
          end

          private

          def query_lines
            call = query_call
            paginate = value(:pageSize)
            fail_empty = value(:onEmpty) == "fail"
            return [assign(:resultVar, "#{call}.records")] unless paginate || fail_empty

            lines = ["query = #{call}", assign(:resultVar, "query.records")]
            lines << assign(:paginationVar, "query.pagination") if paginate
            lines << fail_with('"query_models.empty"', unless: "query.records.present?") if fail_empty
            lines << "query.records"
            lines
          end

          def wrap_entity(lines)
            attempt('"query_models.failed"', FlowchartRuntime::Entries::Error) { lines }
          end

          def query_call
            args = query_kwargs
            args.empty? ? "FlowchartRuntime::Entries.query(ctx)" : "FlowchartRuntime::Entries.query(ctx, #{args})"
          end

          def query_kwargs
            page_size = value(:pageSize)
            parts = [conditions_arg]
            parts << "entity: #{read(:entity)}" if named_entity?
            parts << "record_scope: #{read(:recordScope)}" unless value(:recordScope) == "all"
            parts << "select: #{read(:select)}" if Array(value(:select)).any?
            parts << "returns: #{read(:returns)}" unless value(:returns) == "records"
            parts << "order_by: #{read(:orderBy)}" unless blank_literal?(:orderBy)
            parts << "order_direction: #{read(:orderDirection)}" unless value(:orderDirection) == "asc"
            parts << "then_order_by: #{read(:thenOrderBy)}" unless blank_literal?(:thenOrderBy)
            parts << "then_order_direction: #{read(:thenOrderDirection)}" unless value(:thenOrderDirection) == "asc"
            parts << "distinct: true" if value(:distinct)
            parts << "limit: #{read(:limit)}" if value(:limit)
            if page_size
              parts << "page: #{read(:pageVariable)}"
              parts << "per_page: #{read(:pageSize)}"
            end
            parts << "offset: #{read(:offset)}" if value(:offset)
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

          def blank_literal?(name)
            value(name).to_s.strip.empty?
          end
        end
      end
    end
  end
end
