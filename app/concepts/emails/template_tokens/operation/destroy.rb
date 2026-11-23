# frozen_string_literal: true

module Emails
  module TemplateTokens
    module Operation
      class Destroy
        Result = Struct.new(:success?, :model, :errors, keyword_init: true) do
          def [](k) = send(k)
        end

        def self.call(token:)
          if token.platform?
            token.errors.add(:base, I18n.t("email.template_tokens.errors.platform_readonly"))
            return Result.new(success?: false, model: token, errors: token.errors)
          end

          token.destroy!
          Result.new(success?: true, model: token, errors: nil)
        rescue ActiveRecord::RecordNotDestroyed => e
          Result.new(success?: false, model: token, errors: e.record.errors)
        end
      end
    end
  end
end
