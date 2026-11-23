# frozen_string_literal: true

module Sms
  # Structural association validation shared by the thin domain records.
  class TenantReferences < ActiveModel::Validator
    def validate(record)
      options.fetch(:attributes).each do |attribute|
        related = record.public_send(attribute)
        next unless related
        next if related.customer_id == record.customer_id
        next if Array(options[:shared]).include?(attribute) && related.customer_id.nil?
        next if Array(options[:actors]).include?(attribute) && related.platform_owner?

        record.errors.add(attribute, I18n.t("sms_audience.errors.tenant_mismatch"))
      end
      if options[:source_pair] && record.source_entity && record.source_entry &&
          record.source_entry.entity_id != record.source_entity_id
        record.errors.add(:source_entry, I18n.t("sms_audience.errors.invalid_source"))
      end
    end
  end
end
