# frozen_string_literal: true

module Member
  # The rows that hang off a member's record — a cart's items, an order's
  # lines — for its member detail page: one section per record type whose
  # rows belong to the member through this record (People::Ownership
  # nested), with the member-visible columns and, when a page manages them
  # (Pages::MemberRows), what the member may do with them.
  class RecordRows
    MEMBER = EntityAttributeAudience::MEMBER
    LIMIT = 200

    Column = Data.define(:slug, :label)
    Section = Data.define(:entity, :title, :columns, :rows, :page, :record) do
      def addable? = !page.nil? && page.serves?(:create)
      def changeable? = !page.nil? && page.serves?(:update)
      def removable? = !page.nil?
      def actions? = changeable? || removable?
    end

    def self.call(...) = new(...).call

    def initialize(record:, viewer:, customer:)
      @record = record
      @viewer = viewer
      @customer = customer
    end

    def call
      return [] unless @record.is_a?(EntityEntry)

      children.map { |entity, slug| section(entity, slug) }
    end

    private

    def children
      Entity.where(customer_id: [@customer.id, nil]).active.order(:id).filter_map do |entity|
        next unless references_record_type?(entity)

        parent = People::Ownership.describe(entity).parents.find { |row| row.entity_id == @record.entity_id }
        [entity, parent.slug] if parent
      end
    end

    def references_record_type?(entity)
      Array(entity.property_schema_json).grep(Hash).any? do |attribute|
        Entities::BridgeParticipants.referenced_entity_id(attribute) == @record.entity_id.to_s
      end
    end

    def section(entity, slug)
      rows = rows_of(entity, slug)
      Entities::EntryDisplay.prime!(rows, customer_id: @customer.id, audience: MEMBER, viewer: @viewer)
      Section.new(entity: entity, title: title(entity, slug), columns: columns(entity, slug), rows: rows, record: @record,
                  page: Pages::MemberRows.page_for(entity: entity, parent_entity_id: @record.entity_id, customer_id: @customer.id))
    end

    # A bridge's rows read as the records they link this one to (a cart's
    # products), as on the admin record page; another child's as itself.
    def title(entity, slug)
      linked = (linked_entity(entity, slug) if entity.bridge_entity?) || entity
      linked.display_label.presence || linked.name
    end

    def linked_entity(bridge, slug)
      other = Array(bridge.property_schema_json).grep(Hash).find do |attribute|
        attribute["name_slug"].to_s != slug && Entities::BridgeParticipants.participant?(attribute)
      end
      other && Entity.where(customer_id: [@customer.id, nil]).find_by(id: Entities::BridgeParticipants.referenced_entity_id(other))
    end

    def rows_of(entity, slug)
      safe = FlowchartRuntime::JsonPathValidator.safe_json_path!(slug)
      People::Ownership.scope(entity, viewer: @viewer, audience: MEMBER, customer_id: @customer.id)
                       .where("EXISTS (SELECT 1 FROM json_each(entity_entries.data, '$.#{safe}') AS ref " \
                              "WHERE CAST(ref.value AS TEXT) = ?)", @record.id.to_s)
                       .order(:id).limit(LIMIT).to_a
    end

    # What the member sees of a row, less the reference back to this record.
    def columns(entity, slug)
      Array(entity.property_schema_json).grep(Hash).filter_map do |attribute|
        key = attribute["name_slug"].to_s
        next if key.blank? || key == slug || attribute["type"] == "Calculated"
        next unless EntityAttributeAudience.visible_to?(attribute, MEMBER)

        Column.new(slug: key, label: attribute["display_label"].presence || attribute["name"].presence || key)
      end
    end
  end
end
