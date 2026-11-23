# frozen_string_literal: true

module EntityDomains
  # Arranges a customer's entities into domain sections by their explicit
  # memberships. Customer-owned entities are created into a domain; shared
  # entities the customer has not placed form a trailing ungrouped section.
  class Layout
    Section = Data.define(:domain, :items) do
      def ungrouped? = domain.nil?
    end
    Item = Data.define(:entity)

    # `kind` narrows the list: "entity" (non-bridge) or "bridge"; anything
    # else lists both.
    KINDS = %w[entity bridge].freeze

    def self.call(...) = new(...).sections

    def initialize(customer_id:, entities:, query: nil, kind: nil)
      @customer_id = customer_id
      @entities = Array(entities)
      @query = query.to_s.strip.downcase
      @kind = KINDS.include?(kind.to_s) ? kind.to_s : nil
    end

    def sections
      items = Hash.new { |hash, key| hash[key] = [] }
      @entities.each do |entity|
        items[placements[entity.id]] << Item.new(entity: entity) if matches?(entity)
      end

      sections = domains.filter_map do |domain|
        next if items[domain.id].empty? && filtering?

        Section.new(domain: domain, items: items[domain.id])
      end
      sections << Section.new(domain: nil, items: items[nil]) if items[nil].any?
      sections
    end

    private

    def domains
      @domains ||= EntityDomain.for_customer(@customer_id).by_name.to_a
    end

    def placements
      @placements ||= EntityDomainMembership.for_customer(@customer_id).pluck(:entity_id, :entity_domain_id).to_h
    end

    def filtering? = @query.present? || !@kind.nil?

    def matches?(entity)
      return false if @kind && (@kind == "bridge") != entity.bridge_entity?
      return true if @query.empty?

      [entity.display_label, entity.name].any? { |text| text.to_s.downcase.include?(@query) }
    end
  end
end
