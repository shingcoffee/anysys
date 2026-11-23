# frozen_string_literal: true

require "reform/form"

module Sms
  module Contracts
    class EntitySync < Reform::Form
      FIELDS = %i[entity_id phone_field name_field country_code timezone attribute_map after_entry_id through_entry_id].freeze
      Input = Struct.new(*FIELDS, keyword_init: true)
      FIELDS.each { |field| property field }
      attr_accessor :source_fields
      validate :mapping_values

      def mapping
        { "phone_field" => phone_field, "name_field" => name_field.presence, "country_code" => country_code,
          "timezone" => timezone.presence, "attribute_map" => attribute_map }
      end

      private

      def mapping_values
        errors.add(:entity_id, I18n.t("sms_audience.errors.invalid_source")) unless DomainAccess.integer(entity_id)&.positive?
        errors.add(:country_code, I18n.t("sms_audience.errors.invalid_country_code")) unless Bounds.country?(country_code)
        errors.add(:timezone, I18n.t("sms_audience.errors.invalid_timezone")) unless Bounds.timezone?(timezone)
        %i[after_entry_id through_entry_id].each do |field|
          value = public_send(field)
          next if field == :through_entry_id && value.nil?
          errors.add(field, I18n.t("sms_audience.errors.invalid_cursor")) unless DomainAccess.integer(value)
        end
        if DomainAccess.integer(through_entry_id) && DomainAccess.integer(after_entry_id) &&
            DomainAccess.integer(through_entry_id) < DomainAccess.integer(after_entry_id)
          errors.add(:through_entry_id, I18n.t("sms_audience.errors.invalid_cursor"))
        end
        fields = source_fields || { phone: [], scalar: [] }
        phone_choices = fields[:phone].map { |row| row[:value] }
        scalar_choices = fields[:scalar].map { |row| row[:value] }
        errors.add(:phone_field, I18n.t("sms_audience.errors.invalid_phone_field")) unless phone_choices.include?(phone_field)
        unless name_field.nil? || name_field == "" || scalar_choices.include?(name_field)
          errors.add(:name_field, I18n.t("sms_audience.errors.invalid_mapping"))
        end
        valid_map = Bounds.object?(attribute_map, bytes: 8192) && attribute_map.size <= 32 && attribute_map.all? do |key, field|
          key.match?(Bounds::CUSTOM_KEY) && scalar_choices.include?(field)
        end
        errors.add(:attribute_map, I18n.t("sms_audience.errors.invalid_mapping")) unless valid_map
      end
    end
  end
end
