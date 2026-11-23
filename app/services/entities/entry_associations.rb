# frozen_string_literal: true

module Entities
  # The many-to-many associations a primary entity takes part in, resolved for
  # the admin entry pages: each association's bridge entity, the bridge's
  # reference back to the primary entity, the associated (target) entity, and
  # the bridge rows that link one primary entry. An association counts from
  # both ends: the ones this entity declares come first, then the ones other
  # entities declare towards it, whose declaring entity is the target.
  class EntryAssociations
    Association = Struct.new(:bridge, :target, :source_slug, :columns, keyword_init: true) do
      def id = bridge.id
      def label = target.display_label.presence || target.name

      # Bridge attributes shown for a row: everything the admin may see except
      # the reference back to the primary entry, which every row shares.
      def column_slugs = columns.map { |column| column["name_slug"].to_s }

      def reference_column?(column)
        column["type"] == Entity::ENTITY_REFERENCE_TYPE && ReferenceLabels.reference?(column)
      end

      # The fixed reference values a bridge row form writes for +entry+.
      def links(entry) = { source_slug => entry.id.to_s }
    end

    # One association's rows for an entry, their display text, and the ids of
    # target records that still exist (so only those are linked).
    Section = Struct.new(:association, :rows, :display, :existing_target_ids, keyword_init: true)

    def initialize(entity:, customer:)
      @entity = entity
      @customer = customer
    end

    def all
      @all ||= if @entity.bridge_entity?
        []
      else
        Current.set(customer: @customer, shared_resources_mode: false) { (declared + inverse).uniq(&:id) }
      end
    end

    def find(bridge_id)
      all.find { |association| association.id.to_s == bridge_id.to_s }
    end

    def rows(association, entry)
      EntityEntry.where(customer_id: @customer.id, entity_id: association.bridge.id)
                 .where("CAST(json_extract(entity_entries.data, ?) AS TEXT) = ?",
                        "$.\"#{association.source_slug}\"", entry.id.to_s)
                 .order(:created_at, :id)
    end

    def sections(entry)
      all.map do |association|
        rows = rows(association, entry).to_a.each { |row| row.entity = association.bridge }
        Section.new(
          association: association,
          rows: rows,
          display: EntryDisplay.new(entity: association.bridge, entries: rows, customer_id: @customer.id,
                                    audience: EntityAttributeAudience::ADMIN),
          existing_target_ids: existing_target_ids(association, rows)
        )
      end
    end

    private

    def tenant_entities = Entity.where(customer_id: [@customer.id, nil]).active

    def declared
      @entity.associations_list.filter_map do |item|
        resolve(item, tenant_entities.non_bridge.find_by(id: item["target_entity_id"]))
      end
    end

    # Read through each peer's effective definition, so a customer override's
    # associations count. A peer whose records cannot be picked (no labelable
    # field) is left out: its rows could not be added from this end.
    def inverse
      tenant_entities.non_bridge.where.not(id: @entity.id).order(:id).flat_map do |peer|
        peer.associations_list.select { |item| item["target_entity_id"].to_s == @entity.id.to_s }
            .filter_map { |item| resolve(item, peer) }
            .select { |association| pickable?(association, peer) }
      end
    end

    def pickable?(association, peer)
      association.columns.any? do |column|
        association.reference_column?(column) && column.dig("config", "entity_id").to_s == peer.id.to_s
      end
    end

    def resolve(item, target)
      return unless target

      bridge = tenant_entities.find_by(id: item["bridge_entity_id"], category: :bridge)
      return unless bridge

      references = Array(bridge.property_schema_json).grep(Hash)
                                                    .select { |attribute| attribute["type"] == Entity::ENTITY_REFERENCE_TYPE }
      source = references.find { |reference| reference["entity_id"].to_s == @entity.id.to_s }
      return unless source

      Association.new(bridge: bridge, target: target, source_slug: source["name_slug"].to_s,
                      columns: columns_for(bridge, source))
    end

    def columns_for(bridge, source)
      BridgeParticipants.pickers(Array(bridge.property_schema_json).grep(Hash), customer_id: @customer.id).select do |attribute|
        attribute["name_slug"].present? && attribute["name_slug"] != source["name_slug"] &&
          EntityAttributeAudience.visible_to?(attribute, EntityAttributeAudience::ADMIN)
      end
    end

    def existing_target_ids(association, rows)
      association.columns.select { |column| association.reference_column?(column) }.to_h do |column|
        ids = rows.flat_map { |row| Array(row.data_json[column["name_slug"]]) }.map(&:to_s).grep(/\A\d+\z/).uniq
        found = ids.empty? ? [] : EntityEntry.where(customer_id: @customer.id, entity_id: column.dig("config", "entity_id"), id: ids).pluck(:id)
        [column["name_slug"].to_s, found.map(&:to_s).to_set]
      end
    end
  end
end
