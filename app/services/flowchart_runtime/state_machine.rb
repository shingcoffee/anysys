# frozen_string_literal: true

module FlowchartRuntime
  # Declared-map state transitions for transition_state. Record writes go
  # through Entries.assign and are not saved. A record step with no map of its
  # own follows the lifecycle declared on the state field (Entities::Lifecycle):
  # any of its transitions, whoever causes it, since the save checks who may.
  module StateMachine
    class Error < StandardError; end

    WILDCARD = "*"

    module_function

    def transition(ctx, current:, target:, transitions:, initial_state: "",
                   allow_same: false, guard: true, on_invalid: "fail",
                   record: nil, state_field: nil, timestamp_field: nil, variable: nil)
      if state_field && record.nil?
        return Step.fail(ctx, :"transition_state.missing_record")
      end

      lifecycle = lifecycle_for(record, state_field) if normalize_table(transitions).empty?
      initial_state = lifecycle.initial if lifecycle && initial_state.to_s.empty?
      from = resolve_current(current, initial_state)
      to = target.to_s

      if from == to && allow_same
        return outcome(from, to, false)
      end

      unless lifecycle ? lifecycle.next_states(from).include?(to) : allowed?(from, to, transitions)
        return invalid_transition(ctx, from, to, on_invalid)
      end

      unless guard
        return guard_failed(ctx, from, to, on_invalid)
      end

      apply!(record, state_field, timestamp_field, to)
      write_variable(ctx, variable, to)
      outcome(from, to, true)
    end

    def read_field(record, field)
      return if record.nil? || field.to_s.empty?

      Collections.dig_item(record, field)
    end

    def resolve_current(current, initial_state)
      text = current.nil? ? "" : current.to_s
      return initial_state.to_s if text.empty? && !initial_state.to_s.empty?

      text
    end

    def allowed?(from, to, transitions)
      targets_for(from, transitions).include?(to.to_s)
    end

    def targets_for(from, transitions)
      table = normalize_table(transitions)
      key = from.to_s
      list = table.key?(key) ? table[key] : table[WILDCARD]
      Array(list)
    end

    def lifecycle_for(record, state_field)
      return unless record.is_a?(EntityEntry) && state_field.to_s.present?

      ::Entities::Lifecycle.find(record.class.try(:bound_entity) || record.entity, state_field)
    end

    def normalize_table(transitions)
      transitions.to_h.each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = value.to_s.split(",").map(&:strip).reject(&:empty?)
      end
    end

    def invalid_transition(ctx, from, to, on_invalid)
      return outcome(from, from, false) if on_invalid.to_s == "skip"

      Step.fail(ctx, :"transition_state.invalid_transition", from: from, to: to)
    end

    def guard_failed(ctx, from, to, on_invalid)
      return outcome(from, from, false) if on_invalid.to_s == "skip"

      Step.fail(ctx, :"transition_state.guard_failed", from: from, to: to)
    end

    def apply!(record, state_field, timestamp_field, value)
      return unless record && state_field.to_s.present?

      attrs = { state_field.to_s => value }
      attrs[timestamp_field.to_s] = Time.current if timestamp_field.to_s.present?
      Entries.assign(record, attrs, strict: true)
    rescue Entries::UnknownAttribute => error
      raise Error, "unknown field #{error.message}"
    end

    def write_variable(ctx, variable, value)
      return unless variable

      ctx[variable] = value
    end

    def outcome(from, to, transitioned)
      { state: (transitioned ? to : from), previous_state: from, transitioned: transitioned }
    end

    private_class_method :resolve_current, :allowed?, :targets_for, :normalize_table, :lifecycle_for,
      :invalid_transition, :guard_failed, :apply!, :write_variable, :outcome
  end
end
