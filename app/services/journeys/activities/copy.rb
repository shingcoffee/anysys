# frozen_string_literal: true

module Journeys
  module Activities
    # Duplicates a journey as a draft the owner can edit. Keys stay unique
    # within the customer by suffixing `_copy`, then `_copy_2`, `_copy_3`…
    # truncated so the result still fits PageVisibility::ACTION_KEY. The
    # customer lock keeps two copies from claiming the same key.
    class Copy
      Result = Struct.new(:ok, :journey, :errors, keyword_init: true)

      def self.call(...) = new(...).call

      def initialize(journey:)
        @source = journey
        @customer = journey.customer
      end

      def call
        Current.set(customer: @customer, shared_resources_mode: false) do
          @customer.with_lock(requires_new: true) { Result.new(ok: true, journey: Journey.create!(copy_attributes), errors: []) }
        end
      rescue ActiveRecord::RecordInvalid => e
        Result.new(ok: false, journey: nil, errors: e.record.errors.full_messages.uniq)
      end

      private

      def copy_attributes
        { customer: @customer, entity_domain: @source.entity_domain, description: @source.description,
          definition: @source.definition, status: :draft, visible_audiences: @source.visible_audiences,
          name: I18n.t("journeys.admin.copy_name", name: @source.name).first(120), key: unique_key }
      end

      def unique_key
        taken = Journey.where(customer_id: @customer.id)
        (1..).lazy.map { |attempt| bounded(attempt == 1 ? "_copy" : "_copy_#{attempt}") }.find { |key| !taken.exists?(key: key) }
      end

      def bounded(suffix) = "#{@source.key.first(63 - suffix.length)}#{suffix}"
    end
  end
end
