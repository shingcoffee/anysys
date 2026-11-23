# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class DestroyModelGenerator < BaseGenerator
          generator_metadata do
            description "Deletes or archives a loaded EntityEntry (modelVariable, default model). mode " \
                        "delete (default) destroys the row through Entries.destroy; archive stamps " \
                        "archiveField with the current time and optionally archivedByField with " \
                        "ctx[:current_user_id], then saves. onMissing fail (default) refuses with " \
                        "record_missing; ignore continues. Use find_model first to load the row. This " \
                        "does not cascade to other entities. Prefer archive when the business must keep " \
                        "history; delete removes the tenant row permanently."
            category :model_operations
            version "5.2.0"
            presentation icon: "M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16",
              color: "red", single_use: true, privileged: false
          end

          config_schema do
            input :modelVariable, default: "model",
                  description: "Context path of the record to destroy or archive. Default model. Load it " \
                               "with find_model (or related_record) first."
            enum :mode, %w[delete archive], default: "delete",
                 description: "delete (default) permanently removes the tenant row. archive keeps the " \
                              "row and writes the current time to archiveField (and optionally the " \
                              "current user id to archivedByField)."
            entity_attribute :archiveField, of: :bound, example: "archived_at", visible: { mode: "archive" },
                             description: "Date-time attribute set to Time.current when mode is archive. " \
                                          "Example: archived_at. Required for archive."
            entity_attribute :archivedByField, of: :bound, visible: { mode: "archive" },
                             description: "Optional attribute set to ctx[:current_user_id] when mode is " \
                                          "archive. Example: archived_by. Leave blank to stamp only the time."
            enum :onMissing, %w[fail ignore], default: "fail",
                 description: "When the record variable is empty: fail (default) refuses with " \
                              "record_missing; ignore continues without writing."
            requires :archiveField, when: { mode: "archive" }
          end

          def generate_body
            model_expr = read(:modelVariable)
            body(
              missing_guard(model_expr),
              attempt('"destroy_model.failed"', FlowchartRuntime::Entries::Error) { [destroy_call(model_expr)] }
            )
          end

          def dependencies
            [:find_model]
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

          def destroy_call(model_expr)
            if value(:mode) == "archive"
              args = ["ctx", model_expr, "field: #{read(:archiveField)}"]
              args << "by_field: #{read(:archivedByField)}" if value(:archivedByField).present?
              "FlowchartRuntime::Entries.archive(#{args.join(', ')})"
            else
              "FlowchartRuntime::Entries.destroy(ctx, #{model_expr})"
            end
          end
        end
      end
    end
  end
end
