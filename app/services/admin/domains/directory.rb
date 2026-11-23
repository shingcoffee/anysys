# frozen_string_literal: true

module Admin
  module Domains
    # Builds the domain sections behind /:cid/admin/domains: one card per
    # browsable (non-bridge) entity with its tenant entry and form stats,
    # arranged into the customer's domains by EntityDomains::Layout, so each
    # section can total its record types, entries, pages and last activity.
    # Domains come by name, entities in no domain form a trailing ungrouped
    # section, and domains without a browsable entity are left out. Unbound
    # forms (see Admin::Pages::BrowseScope) belong to the ungrouped section,
    # which is kept for them even when every entity sits in a domain. Uses the
    # same EntityAssociationGraph as the sidebar so both count the same set. A
    # section's `key` (the domain id, or "ungrouped") addresses it at
    # /:cid/admin/domains/:key.
    class Directory
      UNGROUPED = "ungrouped"

      Card = Struct.new(:entity, :entry_count, :last_entry_at, :form_count, keyword_init: true)
      Section = Data.define(:domain, :cards, :unbound_form_count) do
        def ungrouped? = domain.nil?
        def key = Directory.key_for(domain)
        def entity_ids = cards.map { |card| card.entity.id }
        def record_type_count = cards.size
        def entry_count = cards.sum(&:entry_count)
        def form_count = cards.sum(&:form_count) + unbound_form_count
        def last_entry_at = cards.filter_map(&:last_entry_at).max
      end

      def self.call(customer_id:) = new(customer_id: customer_id).call

      def self.key_for(domain) = domain ? domain.id.to_s : UNGROUPED

      def initialize(customer_id:)
        @customer_id = customer_id
      end

      def call
        entities = EntityAssociationGraph.build(@customer_id).all_entities
        form_counts = ::Admin::Pages::BindingCounts.call(customer_id: @customer_id)
        unbound = form_counts[nil].total
        cards = build_cards(entities, form_counts).index_by { |card| card.entity.id }

        sections = layout(entities).filter_map do |section|
          next if section.items.empty?

          Section.new(domain: section.domain, unbound_form_count: section.ungrouped? ? unbound : 0,
                      cards: section.items.map { |item| cards.fetch(item.entity.id) })
        end
        sections << Section.new(domain: nil, cards: [], unbound_form_count: unbound) if unbound.positive? && sections.none?(&:ungrouped?)
        sections
      end

      private

      def layout(entities)
        return [] if entities.empty?

        ::EntityDomains::Layout.call(customer_id: @customer_id, entities: entities)
      end

      def build_cards(entities, form_counts)
        entries = EntityEntry.where(customer_id: @customer_id, entity_id: entities.map(&:id)).group(:entity_id)
        counts = entries.count
        latest = entries.maximum(:updated_at)

        entities.map do |entity|
          Card.new(entity: entity, entry_count: counts.fetch(entity.id, 0), last_entry_at: latest[entity.id],
                   form_count: form_counts[entity.id].total)
        end
      end
    end
  end
end
