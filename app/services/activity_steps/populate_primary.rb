# frozen_string_literal: true

module ActivitySteps
  # Trailblazer step that populates the primary model with entity params.
  #
  # Entity attributes are assigned via hash-style access (stored in EntityEntry.data JSON).
  #
  # Requires ctx[:model] and ctx[:routed_params] to be set.
  #
  # @example Usage in a Trailblazer Activity
  #   step ActivitySteps::PopulatePrimary
  #
  module PopulatePrimary
    module_function

    def call(ctx, model:, routed_params:, **)
      return false if BaseModelInput.rejected?(ctx, routed_params: routed_params, model: model)
      primary = routed_params[:primary]
      entity_params = primary[:entity] || {}

      # Submitted keys are not whitelisted to the schema, so real columns
      # (customer_id, user_id, …) must never be assignable from a form.
      entity_params.each do |key, value|
        model[key] = value unless FlowchartRuntime::Entries::INTERNAL_COLUMNS.include?(key.to_s)
      end

      true
    end
  end
end
