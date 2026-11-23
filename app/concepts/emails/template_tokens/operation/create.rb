# frozen_string_literal: true

module Emails
  module TemplateTokens
    module Operation
      class Create
        Result = Struct.new(:success?, :model, :errors, keyword_init: true) do
          def [](k) = send(k)
        end

        def self.call(customer:, params:)
          model = Emails::TemplateToken.new(
            customer_id: customer.id,
            source_type: Emails::TemplateToken::SOURCE_ENTITY
          )
          form = Contract::Create.new(model)
          unless form.validate(params.to_h)
            form.errors.messages.each do |attribute, messages|
              Array(messages).each { |message| model.errors.add(attribute, message) }
            end
            return Result.new(success?: false, model: model, errors: model.errors)
          end

          model.assign_attributes(
            label: form.label,
            entity_id: form.entity_id,
            attribute_slug: form.attribute_slug,
            source_type: Emails::TemplateToken::SOURCE_ENTITY,
            customer_id: customer.id
          )

          if model.save
            Result.new(success?: true, model: model, errors: nil)
          else
            Result.new(success?: false, model: model, errors: model.errors)
          end
        end
      end
    end
  end
end
