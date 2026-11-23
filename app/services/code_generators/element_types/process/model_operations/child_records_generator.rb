# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class ChildRecordsGenerator < BaseGenerator
          EMPTY_CONDITIONS = { "type" => "group", "joins" => [], "conditions" => [] }.freeze
          BoundView = Data.define(:name, :attribute_slugs)
          LOOKUP_OPS = %w[find list count].freeze
          ORDERED_OPS = %w[find list].freeze

          generator_metadata do
            description "Finds, lists, counts, or creates EntityEntry rows of another entity whose reference field points at a loaded record, such as an order's lines. Use this for records that point at the source, including a link row's own values; use related_record to walk a declared association to the other end of a link, and referenced_record to follow a reference field on the source. Reads entity, optional field, modelVariable, and operation. Writes the rows, one row, the count, or the created row to resultVar. Create always sets the child's reference to the source. Fails as child_records.failed on resolver errors, or child_records.not_found when find onNotFound is fail and nothing matches."
            category :model_operations
            version "1.1.0"
            presentation icon: "M4 6h16M4 12h16M4 18h7",
              color: "teal", single_use: false, privileged: false
          end

          config_schema do
            reference :entity, source: :entities, required: true, example: "Order line",
                      description: "Name of the child entity whose rows point at the source, such as Order line. A numeric entity id is also accepted."
            literal :field, example: "order",
                    description: "Slug of the child's reference to the source, such as order. Leave blank when that entity has exactly one such reference; name one when it has several."
            input :modelVariable, default: "model",
                  description: "Ctx path of the parent record the children point at, such as model or cart. A numeric id is accepted when field names the child's reference."
            enum :operation, %w[list find count create], default: "list",
                 description: "list returns rows for a loop (collection = resultVar). find returns the first match. count returns an integer. create writes one child pointing at the source."
            conditions :conditions, default: EMPTY_CONDITIONS, visible: { operation: LOOKUP_OPS },
                       description: "Extra filters on the child rows, such as status == Open. Ignored for create. Leave empty to include every child of the source."
            mapping :assignments, key: :entity_attribute, value: :expression, default: [],
                    visible: { operation: "create" }, example: [{ "key" => "quantity", "value" => "ctx[:line].quantity" }],
                    description: "Child attributes to set on create, such as quantity => ctx[:line].quantity. The reference to the source is set for you and cannot be redirected. Assign a reference as a record id, such as ctx[:product].id."
            enum :onNotFound, %w[nil fail], default: "nil", visible: { operation: "find" },
                 description: "When find matches nothing: nil stores nil on resultVar and the step succeeds. fail refuses the run as child_records.not_found."
            integer :limit, min: 1, max: 1000, default: 100, visible: { operation: "list" },
                    description: "Maximum child rows list returns (1-1000, default 100). find and count ignore this."
            literal :orderBy, visible: { operation: ORDERED_OPS },
                    description: "Child attribute or column to sort by, such as quantity or id. Blank sorts by id. Used by list and find (first after sort)."
            enum :orderDirection, %w[asc desc], default: "asc", visible: { operation: ORDERED_OPS },
                 description: "asc is oldest/lowest first (default). desc is newest/highest first, including when orderBy is blank (then by id)."
            output :resultVar, default: "child_records", example: "lines",
                   description: "Ctx variable for the result: an array (list), one row (find/create), or an integer (count). Use a singular name such as line for find/create."

            validate do |cfg, errors|
              slug = cfg["field"].to_s.strip
              next errors.add(:field, :invalid_identifier) unless slug.empty? || ConfigSchema::IDENT_SEGMENT.match?(slug)

              order = cfg["orderBy"].to_s.strip
              if order.present? && !FlowchartRuntime::ConditionInput.safe_column?(order.delete_prefix("data."))
                errors.add(:orderBy, :unsafe_column, column: order)
              end
              next unless respond_to?(:child_entity, true)

              child = child_entity
              next if child.nil?
              next errors.add(:entity, :unknown_entity, entity: cfg["entity"].to_s) if child == :unresolved

              parent = parent_entity
              next if slug.empty? && parent.nil?

              target = slug.empty? ? nil : FlowchartRuntime::Entries.reference_target(child, slug)
              if !slug.empty? && target.nil?
                errors.add(:field, :not_a_reference, attribute: slug, entity: child.display_label.presence || child.name)
              elsif parent && (slug.empty? ? reference_count(child, parent) != 1 : target.id != parent.id)
                errors.add(:field, :not_pointing_at, entity: child.display_label.presence || child.name,
                                                     target: parent.display_label.presence || parent.name)
              end
            end
          end

          def generate_body
            attempt('"child_records.failed"', FlowchartRuntime::ChildRecords::Error) do
              [
                "records = FlowchartRuntime::ChildRecords.call(ctx, #{call_kwargs})",
                "return false if records == false",
                assign(:resultVar, "records"),
                missing_guard,
                "true"
              ]
            end
          end

          # Condition and assignment keys are the child entity's attributes.
          def bound_entity
            child = child_entity
            return if child.nil? || child == :unresolved

            BoundView.new(child.name, Array(child.property_schema_json).filter_map { |row| row["name_slug"].to_s.presence if row.is_a?(Hash) })
          end

          private

          def call_kwargs
            parts = ["operation: #{read(:operation)}", "entity: #{read(:entity)}", "source: #{read(:modelVariable)}"]
            parts << "field: #{read(:field)}" unless value(:field).to_s.strip.empty?
            op = value(:operation).to_s
            parts << "conditions: #{literal(value(:conditions))}" if LOOKUP_OPS.include?(op) && !blank_conditions?(value(:conditions))
            parts << "assignments: #{assignments_source}" if op == "create"
            parts << "limit: #{read(:limit)}" if op == "list"
            if ORDERED_OPS.include?(op)
              parts << "order_by: #{read(:orderBy)}" unless value(:orderBy).to_s.strip.empty?
              parts << "order_direction: #{read(:orderDirection)}" unless value(:orderDirection).to_s == "asc"
            end
            parts.join(", ")
          end

          def assignments_source
            pairs = Array(value(:assignments)).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              "#{literal(key.to_s)} => #{emit_expression(row["value"] || row[:value])}" if key.to_s.present?
            end
            "{#{pairs.join(', ')}}"
          end

          def missing_guard
            return unless value(:operation).to_s == "find" && value(:onNotFound) == "fail"

            fail_with('"child_records.not_found"', unless: "records")
          end

          def blank_conditions?(conditions)
            return true if conditions.blank?
            return conditions.empty? if conditions.is_a?(Array)

            conditions.respond_to?(:[]) && conditions["type"] == "group" && Array(conditions["conditions"]).empty?
          end

          # The child entity, nil when it can't be looked up here (no tenant),
          # or :unresolved when the tenant has no such entity.
          def child_entity
            return @child_entity if defined?(@child_entity)

            customer_id = Current.customer&.id
            name = value(:entity).to_s.strip
            return @child_entity = nil if customer_id.nil? || name.empty?

            @child_entity = FlowchartRuntime::EntityResolver.named(name, customer_id: customer_id)
          rescue FlowchartRuntime::EntityResolver::Error
            @child_entity = :unresolved
          end

          # The page's entity, when the record is the page's own.
          def parent_entity
            return unless value(:modelVariable).to_s == "model" && context.is_a?(Hash)

            entity = context[:bound_entity] || context["bound_entity"]
            entity if entity.respond_to?(:property_schema_json)
          end

          def reference_count(child, parent)
            Array(child.property_schema_json).count do |attribute|
              FlowchartRuntime::Entries.reference_target_id(attribute).to_s == parent.id.to_s
            end
          end
        end
      end
    end
  end
end
