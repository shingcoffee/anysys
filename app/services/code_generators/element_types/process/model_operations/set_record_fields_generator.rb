# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class SetRecordFieldsGenerator < BaseGenerator
          BoundView = Data.define(:name, :attribute_slugs)

          generator_metadata do
            description "Writes attributes on a loaded EntityEntry in memory without saving. Use this to stage values before save_model, or to fill blanks on a record another step will persist; use update_model (or referenced_record / related_record operation update) when this step should save. Reads modelVariable and assignments. writeMode only_blank leaves stored values that are already present; skipNilValues leaves a field unchanged when the expression is nil. Mutates the record in place and does not write a resultVar. Fails as set_record_fields.missing_record when the path is nil, or set_record_fields.failed on an unknown attribute."
            category :model_operations
            version "1.2.0"
            presentation icon: "M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z",
              color: "indigo", single_use: false, privileged: false
          end

          config_schema do
            input :modelVariable, default: "model",
                  description: "Ctx path of the loaded EntityEntry to mutate, such as model or product. The record is not saved; a later save_model or update_model persists it."
            mapping :assignments, key: :entity_attribute, value: :expression,
                    example: [{ "key" => "email", "value" => "ctx[:params][:email]" }],
                    description: "Entity attributes mapped to Ruby expressions, such as email => ctx[:params][:email]. Keys must belong to the record's entity. Nothing is written to the database here."
            enum :writeMode, %w[overwrite only_blank], default: "overwrite",
                 description: "overwrite replaces every mapped field (default). only_blank fills a field only when its stored value is nil or empty, leaving existing values."
            flag :skipNilValues, default: false,
                 description: "When true, a mapped expression that evaluates to nil leaves that field unchanged. When false (default), nil is written."
          end

          def generate_body
            parts = ["record", mapping_source(value(:assignments)) || "{}", "strict: true"]
            parts << "write_mode: #{read(:writeMode)}" unless value(:writeMode) == "overwrite"
            parts << "skip_nil: true" if value(:skipNilValues)
            attempt('"set_record_fields.failed"', FlowchartRuntime::Entries::Error) do
              [
                "record = #{read(:modelVariable)}",
                fail_with('"set_record_fields.missing_record"', unless: "record"),
                "FlowchartRuntime::Entries.assign(#{parts.join(', ')})"
              ]
            end
          end

          # Keys are checked only on the page's own record, whose entity is known here.
          def bound_entity
            raw = context.is_a?(Hash) ? (context[:bound_entity] || context["bound_entity"]) : nil
            return unless raw && value(:modelVariable).to_s.in?(["", "model"])
            return raw if raw.respond_to?(:attribute_slugs)

            slugs = Array(raw.try(:property_schema_json)).filter_map do |row|
              row["name_slug"].to_s.presence if row.is_a?(Hash)
            end
            BoundView.new(raw.try(:name), slugs)
          end

          private

          def mapping_source(rows)
            pairs = Array(rows).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              next if key.to_s.blank?

              "#{literal(key.to_s)} => #{emit_expression(row["value"] || row[:value])}"
            end
            "{#{pairs.join(', ')}}" unless pairs.empty?
          end
        end
      end
    end
  end
end
