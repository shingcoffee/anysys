# frozen_string_literal: true

require "reform/form"

module Sms
  module Contracts
    class Contact < Reform::Form
      FIELDS = %i[phone name country_code timezone status custom_attributes lock_version].freeze
      Input = Struct.new(*FIELDS, keyword_init: true)
      FIELDS.each { |field| property field }
      validate :contact_values

      def phone_e164
        PhoneNumber.normalize(phone, country: country_code) if Bounds.country?(country_code)
      end

      private

      def contact_values
        { name: Bounds.text?(name, bytes: 200), country_code: Bounds.country?(country_code),
          timezone: Bounds.timezone?(timezone), status: Sms::Contact::STATUSES.include?(status),
          custom_attributes: Bounds.custom_attributes?(custom_attributes), phone: phone_e164.present? }.each do |field, valid|
          errors.add(field, I18n.t("sms_audience.errors.invalid_#{field}")) unless valid
        end
      end
    end
  end
end
