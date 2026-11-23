# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class CloneModelGenerator < BaseGenerator
          generator_metadata do
            description "Duplicates a loaded EntityEntry (modelVariable, default model) with dup into " \
                        "resultVar (default clone). excludeFields are cleared on the copy; overrides " \
                        "then assign expressions. persist false (default) leaves the copy unsaved for " \
                        "build_contract; persist true saves it through Entries::Save. onMissing fail " \
                        "(default) refuses with record_missing; ignore continues. File and Image fields " \
                        "keep the source's stored files unless excluded. Does not copy " \
                        "associations; use related_record to clone children separately. Fails through " \
                        "clone_model.failed when duplication raises."
            category :model_operations
            version "5.2.0"
            presentation icon: "M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z",
              color: "indigo", single_use: false, privileged: false
          end

          config_schema do
            input :modelVariable, default: "model",
                  description: "Context path of the record to copy. Default model. Load it with " \
                               "find_model first; an empty variable follows onMissing."
            list :excludeFields, item: :entity_attribute, default: [],
                 description: "Bound-entity attribute slugs cleared on the copy (set to nil). Example: " \
                              "email. Empty by default. Use this for unique fields you will override."
            mapping :overrides, key: :entity_attribute, value: :expression, default: [],
                    example: [{ "key" => "email", "value" => "ctx[:params][:email]" }],
                    description: "Bound-entity attributes written onto the copy after excludeFields. " \
                                 "Each key is an attribute slug; each value is a Ruby expression such as " \
                                 "ctx[:params][:email]. Empty by default."
            flag :persist, default: false,
                 description: "When true, save the copy immediately through Entries::Save. Default false " \
                              "(leave unsaved so build_contract can wrap it). A failed save refuses the step."
            enum :onMissing, %w[fail ignore], default: "fail",
                 description: "When the source record variable is empty: fail (default) refuses with " \
                              "record_missing; ignore continues without copying."
            output :resultVar, default: "clone",
                   description: "Context variable that receives the copy. Default clone. Distinct from " \
                                "model so the original row stays available."
          end

          def generate_body
            model_expr = read(:modelVariable)
            body(
              missing_guard(model_expr),
              attempt('"clone_model.failed"', FlowchartRuntime::Clone::Error, FlowchartRuntime::Entries::Error) { clone_lines }
            )
          end

          def dependencies
            [:new_model]
          end

          private

          def missing_guard(model_expr)
            if value(:onMissing) == "ignore"
              "return true unless #{model_expr}"
            else
              <<~RUBY.chomp
                unless #{model_expr}
                  return FlowchartRuntime::Step.fail(ctx, :record_missing, field: :modelVariable)
                end
              RUBY
            end
          end

          def clone_lines
            copy_args = [read(:modelVariable)]
            copy_args << "exclude: #{read(:excludeFields)}" if Array(value(:excludeFields)).any?
            copy_call = "FlowchartRuntime::Clone.copy(#{copy_args.join(', ')})"
            pairs = mapping_source(value(:overrides))
            persist = value(:persist)
            return [assign(:resultVar, copy_call)] unless pairs || persist

            lines = ["copy = #{copy_call}"]
            lines << "FlowchartRuntime::Entries.assign(copy, #{pairs}, strict: true)" if pairs
            lines << assign(:resultVar, "copy")
            return lines unless persist

            lines << "return false unless FlowchartRuntime::Entries.save(ctx, copy)"
            lines << "copy"
            lines
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
        end
      end
    end
  end
end
