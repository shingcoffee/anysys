# frozen_string_literal: true

module Journeys
  module Activities
    # Takes a journey live once every launch check passes. The customer lock
    # keeps two launches from claiming the same first page and audience
    # between the check and the write.
    class Launch
      Result = Struct.new(:ok, :journey, :errors, keyword_init: true)

      def self.call(...) = new(...).call

      def initialize(journey:)
        @journey = journey
      end

      def call
        errors = @journey.customer.with_lock(requires_new: true) do
          LaunchChecks.new(@journey).errors.tap { |list| @journey.update!(status: :launched) if list.empty? }
        end
        Result.new(ok: errors.empty?, journey: @journey, errors: errors)
      end
    end
  end
end
