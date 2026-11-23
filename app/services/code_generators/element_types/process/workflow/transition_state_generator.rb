# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Workflow
        class TransitionStateGenerator < BaseGenerator
          BoundView = Data.define(:name, :attribute_slugs)

          STATE_SOURCES = %w[record variable].freeze
          TARGET_SOURCES = %w[literal variable].freeze
          ON_INVALID = %w[fail skip].freeze

          generator_metadata do
            description "Moves a record field or ctx variable through a declared state machine and rejects transitions the map does not allow. On a page record, leave transitions empty to follow that status field's Entities::Lifecycle (any of its transitions; Entries::Save still checks who may). Use request_payment paidFields for a status a payment confirms, never this step. Reads modelVariable/stateField or stateVariable, plus targetState or targetVariable. Writes resultVar, previousStateVar, and transitionedVar. Does not save the record. Refuses transition_state.invalid_transition, guard_failed, or missing_record."
            category :workflow
            version "1.1.0"
            presentation icon: "M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4",
                          color: "amber", single_use: false, privileged: false
          end

          config_schema do
            enum :stateSource, STATE_SOURCES, default: "record",
                 description: "record (default) reads and writes a field on the loaded EntityEntry at modelVariable. variable reads and writes a plain ctx variable named by stateVariable (not a nested path)."
            input :modelVariable, default: "model", visible: { stateSource: "record" },
                  description: "Ctx path of the loaded EntityEntry, such as model. The field is written in memory only; a later save_model persists it."
            entity_attribute :stateField, of: :bound, example: "status", required: true,
                             visible: { stateSource: "record" },
                             description: "Attribute slug that holds the current state, such as status. Must be a writable field of that record's entity. The record is not saved by this step."
            input :stateVariable, example: "status", required: true, placeholder: true,
                  visible: { stateSource: "variable" },
                  description: "Plain ctx variable name that holds the current state, such as status. Nested paths (order.status) are rejected because the new state could not be written back."
            enum :targetSource, TARGET_SOURCES, default: "literal",
                 description: "literal uses targetState. variable reads the next state from targetVariable at runtime (for example a decision-table result)."
            literal :targetState, example: "approved", required: true, placeholder: true,
                    visible: { targetSource: "literal" },
                    description: "State to move to when the map or lifecycle allows it, such as approved. Must match an option value of the status field, not its label."
            input :targetVariable, example: "next_status", required: true,
                  visible: { targetSource: "variable" },
                  description: "Ctx path of the state to move to when targetSource is variable, such as next_status. Evaluated at runtime."
            mapping :transitions, key: :literal, value: :literal,
                    example: [{ "key" => "draft", "value" => "submitted" },
                              { "key" => "submitted", "value" => "approved, rejected" }],
                    description: "From-state mapped to allowed targets. Each value is one slug or a comma-separated list (approved, rejected). Use * as the from-state to allow any current state. Leave empty on a record step to follow the field's lifecycle."
            literal :initialState, default: "",
                    description: "State assumed when the current value is blank, such as draft. On a lifecycle-backed record step, the field's default option is used when this is blank."
            flag :allowSameState, default: false,
                 description: "When on, a target equal to the current state is a successful no-op (transitionedVar is false, state unchanged). Off (default) treats it as invalid unless the map lists it."
            expression :guardExpression, group: :advanced,
                       description: "Optional extra Ruby boolean that must be true for the transition to proceed, such as ctx[:allowed]. A false guard refuses as transition_state.guard_failed (or skips when onInvalid is skip)."
            enum :onInvalid, ON_INVALID, default: "fail",
                 description: "When the map, lifecycle, or guard rejects the transition: fail refuses the run; skip leaves the state unchanged, sets transitionedVar to false, and continues."
            entity_attribute :timestampField, of: :bound, default: "", group: :advanced,
                             visible: { stateSource: "record" },
                             description: "Optional attribute stamped with Time.current when the transition happens, such as status_changed_at. The record is not saved. Leave blank to skip."
            output :resultVar, default: "state",
                   description: "Ctx variable later steps read for the resulting state, such as state. Unchanged when the step skips an invalid transition."
            output :previousStateVar, default: "previous_state", group: :advanced,
                   description: "Ctx variable later steps read for the state before this step, such as previous_state."
            output :transitionedVar, default: "transitioned", group: :advanced,
                   description: "Ctx variable later steps read for whether the state changed (true or false), such as transitioned."
            validate do |cfg, errors|
              rows = value(:transitions)
              if (rows.nil? || (rows.is_a?(Array) && rows.empty?)) && !lifecycle_fallback?
                errors.add(:transitions, :required)
              end

              variable = cfg["stateVariable"].to_s
              if cfg["stateSource"].to_s == "variable" && variable.present? &&
                 !CodeGenerators::ConfigSchema::IDENT_SEGMENT.match?(variable)
                errors.add(:stateVariable, :plain_variable)
              end
            end
          end

          def generate_body
            attempt('"transition_state.failed"', FlowchartRuntime::StateMachine::Error) do
              [
                "result = FlowchartRuntime::StateMachine.transition(ctx, #{transition_args})",
                "next false unless result",
                assign(:resultVar, "result[:state]"),
                assign(:previousStateVar, "result[:previous_state]"),
                assign(:transitionedVar, "result[:transitioned]"),
                "result"
              ]
            end
          end

          # The field is checked only on the page's own record, whose entity is known here.
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

          # Without a map a record step follows the lifecycle on its state
          # field; when the page's entity is known here it must declare one.
          def lifecycle_fallback?
            return false unless record_mode?

            raw = context.is_a?(Hash) ? (context[:bound_entity] || context["bound_entity"]) : nil
            return true unless raw.respond_to?(:property_schema_json) && value(:modelVariable).to_s.in?(["", "model"])

            Entities::Lifecycle.find(raw, value(:stateField)).present?
          end

          def transition_args
            args = [
              "current: #{current_source}",
              "target: #{target_source}",
              "transitions: #{read(:transitions)}",
              ("initial_state: #{read(:initialState)}" if value(:initialState).to_s.strip.present?),
              ("allow_same: #{read(:allowSameState)}" if value(:allowSameState)),
              ("guard: #{guard_source}" if guard_source),
              ("on_invalid: #{read(:onInvalid)}" unless value(:onInvalid).to_s == "fail")
            ]
            args.concat(record_args) if record_mode?
            args << "variable: #{variable_key_source}" unless record_mode?
            args.compact.join(", ")
          end

          def record_args
            [
              "record: #{read(:modelVariable)}",
              "state_field: #{read(:stateField)}",
              ("timestamp_field: #{read(:timestampField)}" if value(:timestampField).to_s.strip.present?)
            ]
          end

          def current_source
            if record_mode?
              "FlowchartRuntime::StateMachine.read_field(#{read(:modelVariable)}, #{read(:stateField)})"
            else
              read(:stateVariable)
            end
          end

          def target_source
            value(:targetSource).to_s == "variable" ? read(:targetVariable) : read(:targetState)
          end

          def guard_source
            raw = value(:guardExpression).to_s.strip
            return if raw.empty?
            raise_unsafe_value!(:guardExpression) unless safe_expression?(raw)

            emit_expression(raw)
          end

          def variable_key_source
            path = value(:stateVariable).to_s
            safe_ident?(path) ? ":#{path}" : "nil"
          end

          def record_mode?
            value(:stateSource).to_s == "record"
          end
        end
      end
    end
  end
end
