# frozen_string_literal: true

module Emails
  class PersistMessage
    def self.existing(customer_id:, idempotency_key:)
      return if idempotency_key.blank?

      Emails::Message.uncached do
        Emails::Message.find_by(customer_id: customer_id, idempotency_key: idempotency_key)
      end
    end

    def self.call(attrs, idempotency_key: nil)
      new(attrs, idempotency_key: idempotency_key).call
    end

    def initialize(attrs, idempotency_key: nil)
      @idempotency_key = (idempotency_key || attrs[:idempotency_key]).presence
      @attrs = attrs.merge(idempotency_key: @idempotency_key)
      @customer = attrs[:customer]
    end

    def call
      existing = existing_message if idempotency_key.present?
      return [existing, false] if existing
      # A savepoint keeps a unique-index collision from poisoning a caller's
      # surrounding quota transaction on adapters such as PostgreSQL.
      [Emails::Message.transaction(requires_new: true) { Emails::Message.create!(@attrs) }, true]
    rescue ActiveRecord::RecordNotUnique
      existing = existing_message
      raise unless existing

      [existing, false]
    rescue ActiveRecord::RecordInvalid => error
      details = error.record.errors.details
      raise unless details.keys == [:idempotency_key] &&
        details[:idempotency_key].all? { |detail| detail[:error] == :taken }

      existing = existing_message
      raise unless existing

      [existing, false]
    end

    private

    attr_reader :idempotency_key

    def existing_message
      self.class.existing(customer_id: @customer.id, idempotency_key: @idempotency_key)
    end
  end
end
