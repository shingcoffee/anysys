# frozen_string_literal: true

module Journeys
  # A domain's journeys linked by the records they hand on: one row per link,
  # from a journey whose steps leave records in a status to one that starts
  # from records in it (Handoffs#links). Read-only and derived from each
  # step's processing; shown on the domain's Journeys tab once it lists two
  # journeys.
  class WorkflowMapComponent < ApplicationComponent
    Row = Data.define(:from, :to, :records)

    def initialize(journeys:, customer_id:)
      @journeys = Array(journeys)
      @customer_id = customer_id
    end

    def render? = @journeys.size > 1

    def rows
      @rows ||= begin
        links = Handoffs.new(customer: Customer.find(@customer_id), journeys: @journeys).links
        entities = Entity.where(customer_id: [@customer_id, nil], id: links.map(&:entity_id).uniq).index_by { |entity| entity.id.to_s }
        links.map { |link| Row.new(from: link.from, to: link.to, records: records_label(link, entities[link.entity_id.to_s])) }
      end
    end

    def edit_path(journey) = helpers.edit_admin_maintenance_journey_path(@customer_id, journey)
    def audiences(journey) = StepEffects.join(journey.visible_audiences.map { |audience| t("journeys.audiences.#{audience}") })
    def connection_label(row) = t("journeys.admin.map.connection", from: row.from.name, to: row.to.name)

    private

    def records_label(link, entity)
      lifecycle = Entities::Lifecycle.find(entity, link.field)
      states = link.values.map { |value| lifecycle ? lifecycle.label(value) : value }
      t("journeys.admin.map.picks_up", entity: entity&.display_label.to_s, states: StepEffects.join(states, last: :or))
    end
  end
end
