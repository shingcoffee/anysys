# frozen_string_literal: true

module FieldTemplates
  class Delete < Trailblazer::Activity::Railway
    step :find_model
    step :check_not_built_in
    step :destroy

    def find_model(ctx, id:, customer_id:, **)
      ctx[:model] = ::FieldTemplate.find_by(id: id, customer_id: customer_id)
      ctx[:model].present?
    end

    def check_not_built_in(ctx, model:, **)
      !model.built_in?
    end

    def destroy(ctx, model:, **)
      model.destroy
    end
  end
end
