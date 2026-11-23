# frozen_string_literal: true

module Sms
  module Activities
    # Persists a platform SMS credential. The form posts a flat params hash;
    # vendor-specific keys (sign_name, region, from, messaging_service_sid) are
    # funneled into the JSON `config` blob for the record's provider. A blank
    # access_key_secret keeps the existing encrypted value; likewise a blank
    # :password config field keeps its existing value (the form renders it
    # masked, never echoing the secret). A blank non-secret config field clears it.
    class SaveCredential
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(record:, params:)
        attrs = sanitize(params, record)
        record.assign_attributes(attrs)

        assignment = AssignDelivery.persist(record: record)
        if assignment.success?
          Result.new(success?: true, model: record, errors: [])
        else
          Result.new(success?: false, model: record, errors: assignment.errors)
        end
      rescue ActiveRecord::RecordNotUnique
        # Lost the race on the (provider, mode) unique index — surface as a
        # graceful validation error rather than a 500.
        record.errors.add(:mode, :taken)
        Result.new(success?: false, model: record, errors: record.errors.full_messages)
      end

      def self.sanitize(params, record)
        h = params.to_h.symbolize_keys
        attrs = {}
        attrs[:provider] = h[:provider] if h.key?(:provider)
        attrs[:mode]     = h[:mode]     if h.key?(:mode)
        attrs[:status]   = h[:status]   if h.key?(:status)
        attrs[:access_key_id] = h[:access_key_id] if h.key?(:access_key_id)

        if h.key?(:access_key_secret)
          attrs[:access_key_secret] = h[:access_key_secret].presence || record.access_key_secret
        end

        attrs[:config] = merged_config(h, attrs[:provider] || record.provider, record)
        attrs
      end

      # Funnel the selected provider's config fields out of the flat hash; a blank
      # value deletes the key so reads fall back to the field default.
      def self.merged_config(h, provider, record)
        adapter = Sms::Adapters.for(provider)
        config  = (record.config || {}).dup
        adapter.config_fields.each do |field|
          key = field[:name].to_sym
          next unless h.key?(key)

          value = h[key].to_s
          if value.strip.empty?
            # A blank :password field means "keep the existing secret" (the form
            # renders it masked and never re-submits it); a blank non-secret
            # field clears the key so reads fall back to the field default.
            config.delete(field[:name].to_s) unless field[:type] == :password
          else
            config[field[:name].to_s] = value
          end
        end
        config
      rescue ArgumentError
        record.config || {}
      end
    end
  end
end
