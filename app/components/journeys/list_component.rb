# frozen_string_literal: true

module Journeys
  # One domain's journeys on its entities workspace: a table from `md:` up,
  # a stacked list on mobile.
  class ListComponent < ApplicationComponent
    STATUS_VARIANTS = { "draft" => :default, "launched" => :success }.freeze
    ICON = "M13 7l5 5m0 0l-5 5m5-5H6"

    attr_reader :journeys

    def initialize(journeys:, customer_id:)
      @journeys = Array(journeys)
      @customer_id = customer_id
    end

    def edit_path(journey) = helpers.edit_admin_maintenance_journey_path(@customer_id, journey)
    def status_variant(journey) = STATUS_VARIANTS.fetch(journey.status)
    def status_label(journey) = t("journeys.admin.status.#{journey.status}")
    def step_count_label(journey) = t("journeys.admin.step_count", count: journey.steps_definition.progress_steps.size)

    def audience_labels(journey)
      journey.visible_audiences.map { |audience| t("journeys.audiences.#{audience}") }.join(t("support.array.words_connector"))
    end

    def updated_label(journey) = l(journey.updated_at, format: :short)
  end
end
