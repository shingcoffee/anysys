# frozen_string_literal: true

module Journeys
  # The journeys a customer's domain supports (EntityDomains::JourneyPlanner
  # over the entities placed in it), and the journey already generated from
  # one of them.
  module DomainCandidates
    module_function

    def call(customer_id:, domain_id:)
      section = EntityDomains::Layout.call(customer_id: customer_id, entities: EntityDomains::Catalog.entities(customer_id))
                                     .find { |item| !item.ungrouped? && item.domain.id.to_s == domain_id.to_s }
      return [] unless section

      EntityDomains::JourneyPlanner.call(customer_id: customer_id, entities: section.items.map(&:entity))
    end

    # Candidate key => the journey generated from it, or nil. Generate
    # suffixes a taken key ("<key>_2"); a copy ends in "_copy" and is not the
    # generated journey.
    def existing_journeys(customer_id:, candidates:)
      journeys = Journey.for_customer(customer_id).order(:id).to_a
      candidates.to_h do |candidate|
        family = /\A#{Regexp.escape(candidate.journey_key)}(_\d+)?\z/
        [candidate.key, journeys.find { |journey| journey.key.match?(family) }]
      end
    end
  end
end
