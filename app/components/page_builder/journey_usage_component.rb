# frozen_string_literal: true

module PageBuilder
  # The page editor's "Used in journeys" card (platform owner only): the
  # customer's journeys that open this page from a step or from their finish,
  # each with its status and where the page sits in it.
  class JourneyUsageComponent < ApplicationComponent
    def initialize(page:, customer_id:)
      @page = page
      @customer_id = customer_id
    end

    def journeys
      @journeys ||= @page.action_key.blank? ? [] : Journey.for_customer(@customer_id).by_name.select { |journey| role_index(journey) }
    end

    def edit_path(journey) = helpers.edit_admin_maintenance_journey_path(@customer_id, journey)
    def status_label(journey) = t("journeys.admin.status.#{journey.status}")
    def status_dot(journey) = journey.launched? ? "bg-emerald-500" : "bg-gray-300"

    def role_label(journey)
      index = role_index(journey)
      if index == :finish then t("journeys.admin.step_kind.finish")
      elsif index.zero? then t("journeys.admin.step_start")
      else t("journeys.admin.step_number", number: index + 1)
      end
    end

    private

    # The page's step position in the journey, :finish when only the finish
    # opens it, or nil when the journey doesn't use it.
    def role_index(journey)
      definition = journey.steps_definition
      definition.action_keys.index(@page.action_key) ||
        (:finish if definition.finish&.target.to_h["action_key"] == @page.action_key)
    end
  end
end
