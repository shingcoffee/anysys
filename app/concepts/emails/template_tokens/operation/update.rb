# frozen_string_literal: true

module Emails
  module TemplateTokens
    module Operation
      class Update
        Result = Struct.new(:success?, :model, :errors, keyword_init: true) do
          def [](k) = send(k)
        end

        def self.call(token:, params:)
          token.errors.clear
          if token.platform?
            token.errors.add(:base, I18n.t("email.template_tokens.errors.platform_readonly"))
            return Result.new(success?: false, model: token, errors: token.errors)
          end

          form = Contract::Update.new(token)
          unless form.validate(params.to_h)
            form.errors.messages.each do |attribute, messages|
              Array(messages).each { |message| token.errors.add(attribute, message) }
            end
            return Result.new(success?: false, model: token, errors: token.errors)
          end

          token.assign_attributes(
            label: form.label,
            entity_id: form.entity_id,
            attribute_slug: form.attribute_slug
          )

          if Emails::TemplateToken.custom_for(token.customer_id)
              .where(entity_id: token.entity_id, attribute_slug: token.attribute_slug).where.not(id: token.id).exists?
            token.errors.add(:base, I18n.t("settings_modules.email.edit_field_already_added"))
            return Result.new(success?: false, model: token, errors: token.errors)
          end

          if token.save
            Result.new(success?: true, model: token, errors: nil)
          else
            Result.new(success?: false, model: token, errors: token.errors)
          end
        rescue ActiveRecord::RecordNotUnique
          token.errors.add(:base, I18n.t("settings_modules.email.edit_field_already_added"))
          Result.new(success?: false, model: token, errors: token.errors)
        end
      end
    end
  end
end
