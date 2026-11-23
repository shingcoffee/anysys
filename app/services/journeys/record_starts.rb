# frozen_string_literal: true

module Journeys
  # The launched journeys an audience can start from one record of an entity
  # (a record start step), each with the page it opens first and the field
  # that page locks the record into. A journey whose first page adds an
  # association's bridge rows with the record locked takes over that
  # association section's "+ Add" on the record's page; the rest are started
  # from the page header. Admins start them from the record's admin page,
  # members from their own record's page, and only on a record type a member
  # owns. Given the +entry+, only journeys whose start condition admits it
  # (Definition::Step#admits?) are listed.
  class RecordStarts
    ADMIN = EntityAttributeAudience::ADMIN
    MEMBER = EntityAttributeAudience::MEMBER

    Start = Data.define(:journey, :page, :field)

    def initialize(entity:, customer_id:, audience: ADMIN, entry: nil)
      @entity = entity
      @customer_id = customer_id
      @audience = audience.to_s
      @entry = entry
    end

    def all
      @all ||= offered? ? starts : []
    end

    def find(key) = all.find { |start| start.journey.key == key.to_s }

    # Entities::EntryAssociations::Association: the bridge rows it lists, linked
    # to the record through `source_slug`.
    def for_association(association)
      all.find { |start| start.page.entity_id.to_s == association.bridge.id.to_s && start.field == association.source_slug }
    end

    def unsectioned(associations)
      all - Array(associations).filter_map { |association| for_association(association) }
    end

    # Issues +viewer+'s run on +start+'s first page step, holding +entry+
    # under the record step, and returns its token.
    def self.begin!(start:, entry:, viewer:, session:)
      definition = start.journey.steps_definition
      _run, token = JourneyRun.issue!(customer_id: start.journey.customer_id, user: viewer, session: session,
                                      journey: start.journey, current_step: definition.first_page_step.key,
                                      state: { "records" => { definition.record_start.key => [entry.id.to_s] } })
      token
    end

    private

    def offered?
      @audience == ADMIN || (@audience == MEMBER && People::Ownership.kind(@entity) == :owned)
    end

    def starts
      journeys = Journey.launched.where(customer_id: @customer_id).for_any_audience([@audience])
                        .starting_from_record(@entity.id).by_name.to_a
      journeys.select! { |journey| journey.steps_definition.record_start&.admits?(@entry) } if @entry
      keys = journeys.map { |journey| journey.steps_definition.first_page_step&.action_key }
      pages = Pages::ActionResolver.pages_for(customer_id: @customer_id, action_keys: keys, audience: @audience)
      journeys.filter_map { |journey| start_for(journey, pages) }
    end

    def start_for(journey, pages)
      definition = journey.steps_definition
      record = definition.record_start
      step = definition.first_page_step
      page = record && step && pages[step.action_key]
      Start.new(journey: journey, page: page, field: step.inputs.key(record.key)) if page
    end
  end
end
