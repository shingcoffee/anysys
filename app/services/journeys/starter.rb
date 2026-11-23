# frozen_string_literal: true

module Journeys
  # Finds the journey a page starts. Launch checks keep at most one launched
  # journey per first page and audience, so the answer is unambiguous.
  module Starter
    def self.for_page(page:, audience:, customer_id:)
      return if page.action_key.blank?

      Journey.launched.where(customer_id: customer_id).for_any_audience([audience]).starting_on(page.action_key).order(:id).first
    end

    # Owner preview of a draft through ?journey=<key>.
    def self.preview(key:, page:, customer_id:, viewer:)
      return if key.blank? || page.action_key.blank? || !JourneyVisibility.allowed?(viewer)

      journey = Journey.find_by(customer_id: customer_id, key: key.to_s)
      journey if journey && starts_on?(journey, page)
    end

    def self.starts_on?(journey, page) = journey.steps_definition.first_step&.action_key == page.action_key
    private_class_method :starts_on?
  end
end
