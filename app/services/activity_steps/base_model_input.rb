# frozen_string_literal: true

module ActivitySteps
  # Base metadata is not a write capability. Until a linked-record resolver,
  # authenticated policy and model-specific contract exist, reject it before
  # routing, assignment or persistence; never select an AR class from a section.
  module BaseModelInput
    module_function

    def rejected?(ctx, routed_params: ctx[:routed_params], model: ctx[:model])
      routed = routed_params&.dig(:primary, :base_models)
      contract_model = ctx[:contract].model if ctx[:contract].is_a?(Reform::Form)
      base_record = [model, contract_model].any? { |record| record.is_a?(ActiveRecord::Base) && !record.is_a?(EntityEntry) }
      return false unless Pages::FormParams.base_submission?(ctx[:params]) || routed.present? || base_record

      ctx[:error] = I18n.t("common.errors.dynamic.base_model_submission_not_supported")
      true
    end
  end
end
