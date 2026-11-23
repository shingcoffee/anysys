# frozen_string_literal: true

module Email
  module Activities
    # Persists a platform email credential. SMTP keeps its typed columns; API
    # providers' fields are funneled into the JSON config blob. Blank encrypted
    # fields (password, dkim_private_key) keep their existing values; a blank
    # non-secret config field clears it.
    class SaveCredential
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      ENCRYPTED = %i[password dkim_private_key webhook_secret].freeze
      TYPED = %i[host port username authentication enable_starttls ssl domain mode status
                 dkim_enabled dkim_domain dkim_selector].freeze

      def self.call(record:, params:)
        record.assign_attributes(sanitize(params, record))
        assignment = AssignDelivery.persist(record: record)
        if assignment.success?
          Result.new(success?: true, model: record, errors: [])
        else
          Result.new(success?: false, model: record, errors: assignment.errors)
        end
      rescue ActiveRecord::RecordNotUnique
        record.errors.add(:mode, :taken)
        Result.new(success?: false, model: record, errors: record.errors.full_messages)
      end

      def self.sanitize(params, record)
        h = params.to_h.symbolize_keys
        attrs = {}
        attrs[:provider] = h[:provider] if h.key?(:provider)
        TYPED.each { |k| attrs[k] = h[k] if h.key?(k) }
        ENCRYPTED.each do |k|
          next unless h.key?(k)

          attrs[k] = h[k].presence || record.public_send(k)
        end
        attrs[:config] = merged_config(h, attrs[:provider] || record.provider, record)
        attrs
      end

      def self.merged_config(h, provider, record)
        klass  = Email::Providers.for(provider)
        config = (record.config || {}).dup
        klass.config_fields.each do |field|
          key = field[:name].to_sym
          next unless h.key?(key)

          value = h[key].to_s
          value.strip.empty? ? config.delete(field[:name].to_s) : config[field[:name].to_s] = value
        end
        config
      rescue ArgumentError
        record.config || {}
      end
    end
  end
end
