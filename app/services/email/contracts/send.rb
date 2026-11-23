# frozen_string_literal: true

require "reform/form"

module Email
  module Contracts
    class Send < Reform::Form
      # Lightweight backing object (avoids pulling in OpenStruct).
      Input = Struct.new(:customer_id, :to, :template_id, :vars, :cc, :bcc, :reply_to, :idempotency_key)

      property :customer_id
      property :to
      property :template_id
      property :vars
      property :cc
      property :bcc
      property :reply_to
      property :idempotency_key

      validates :to,           presence: true, format: { with: URI::MailTo::EMAIL_REGEXP,
                                                         message: ->(*) { I18n.t("admin_modules.errors.validations.invalid_email_format") } }
      validates :template_id, presence: true
      validates :vars,         presence: true
      validate  :template_exists_and_active

      def template
        @template ||= Emails::Template.active.find_by(customer_id: customer_id, id: template_id)
      end

      private

      def template_exists_and_active
        return if template_id.blank?
        return if template.present?
        errors.add(:template_id, I18n.t("admin_modules.errors.validations.template_not_active"))
      end
    end
  end
end
