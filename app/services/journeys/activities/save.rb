# frozen_string_literal: true

module Journeys
  module Activities
    # Creates or updates a journey from the builder's step rows. Everything
    # runs in one transaction, so page action keys assigned while normalising
    # roll back when the journey fails to save.
    class Save
      Result = Struct.new(:ok, :journey, :errors, keyword_init: true)
      ID = /\A[1-9][0-9]*\z/

      def self.call(...) = new(...).call

      def initialize(journey:, params:, customer_id:)
        @journey = journey
        @params = params
        @customer = Customer.find_by(id: customer_id) if customer_id.to_s.match?(ID)
      end

      def call
        Current.set(customer: @customer, shared_resources_mode: false) do
          saved = false
          serialized do
            saved = scope_customer && validate(normalized_attributes) && persist
            raise ActiveRecord::Rollback unless saved
          end
          Result.new(ok: saved, journey: @journey, errors: saved ? [] : @journey.errors.full_messages)
        end
      end

      private

      def scope_customer
        @journey.errors.clear
        if @customer.nil? || (@journey.customer_id.present? && @journey.customer_id != @customer.id)
          @journey.errors.add(:base, I18n.t("journeys.admin.errors.invalid_customer"))
          return false
        end
        @journey.customer_id = @customer.id
        true
      end

      def normalized_attributes
        input = @params.to_h.stringify_keys
        @journey.visible_audiences = input["visible_audiences"] if input.key?("visible_audiences")
        steps = @journey.definition_json
        steps = StepParams.to_definition(input["steps"], customer_id: @customer.id, start: input["start"]) if input.key?("steps")
        {
          "name" => input.fetch("name", @journey.name).to_s.strip,
          "key" => input.fetch("key", @journey.key).to_s.strip,
          "description" => input.fetch("description", @journey.description).to_s.strip.presence,
          "entity_domain_id" => input.fetch("entity_domain_id", @journey.entity_domain_id).to_s.presence,
          "definition" => Definition.new(steps).to_h.to_json,
          "visible_audiences" => @journey.visible_audiences
        }
      end

      # A launched journey must still pass its launch checks, so a live
      # journey is never saved into a state it couldn't have launched in.
      def validate(attrs)
        @contract = Contracts::Journey.new(@journey)
        valid = @contract.validate(attrs)

        # The attempted values stay on the model for the launch checks and the re-rendered form.
        @journey.assign_attributes(attrs.except("visible_audiences"))
        @contract.errors.each { |error| @journey.errors.add(error.attribute, error.message) }
        return valid unless valid && @journey.launched?

        LaunchChecks.new(@journey).errors.each { |message| @journey.errors.add(:base, message) }
        @journey.errors.empty?
      end

      def persist
        @contract.sync
        @journey.save!
      rescue ActiveRecord::RecordInvalid
        false
      rescue ActiveRecord::RecordNotUnique
        @journey.errors.add(:key, I18n.t("errors.messages.taken"))
        false
      end

      # A launched journey re-runs its launch checks, so it takes the same
      # customer lock (as the outer transaction) that launching does.
      def serialized(&)
        return ::Journey.transaction(requires_new: true, &) unless @journey.launched? && @customer

        @customer.with_lock(requires_new: true, &)
      end
    end
  end
end
