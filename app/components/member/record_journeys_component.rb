# frozen_string_literal: true

module Member
  # The journeys a member may start from their own record
  # (Journeys::RecordStarts), one button each, for its member detail page.
  # Each posts to Member::EntityEntryJourneysController, which re-checks the
  # member reaches the record before the run begins.
  class RecordJourneysComponent < ApplicationComponent
    include UsesSiteChrome

    def initialize(starts:, record:, customer:)
      @starts = Array(starts)
      @record = record
      @customer = customer
    end

    attr_reader :starts

    def render? = starts.any?

    def start_path(start)
      helpers.member_entity_entry_journey_path(@customer.id, @record.entity_id, @record.id, start.journey.key)
    end

    def start_label(start) = t("journeys.runtime.start_from_record", name: start.journey.name)
  end
end
