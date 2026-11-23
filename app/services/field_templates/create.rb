# frozen_string_literal: true

module FieldTemplates
  class Create < Trailblazer::Activity::Railway
    step :build_model
    step :validate
    step :save

    def build_model(ctx, params:, **)
      ctx[:model] = ::FieldTemplate.new(params)
    end

    def validate(ctx, model:, **)
      contract = Contract.new(model)
      ctx[:contract] = contract
      contract.validate(model.attributes)
    end

    def save(ctx, contract:, **)
      contract.save
    end
  end
end
