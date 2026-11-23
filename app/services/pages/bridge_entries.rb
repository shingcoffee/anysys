# frozen_string_literal: true

module Pages
  # Writes the bridge rows a page form collects beside its primary entry
  # (the bridge sections of Pages::FormParams#permit_parts). The page's
  # flowchart writes them when it first saves the new page record, inside the
  # submission's savepoint, so a rejected row rolls the whole submission back.
  #
  # A section is written only when one of its target references (the bridge's
  # EntityReference to the associated entity) is filled; the reference back to
  # the primary entity is always set here, never taken from the submission.
  # EntityEntryContract checks that each target id is a record of the target
  # entity in this customer.
  class BridgeEntries
    def self.call(...)
      new(...).call
    end

    def initialize(entry:, entity:, sections:, customer_id:, audience:)
      @entry = entry
      @entity = entity
      @sections = sections
      @customer_id = customer_id
      @audience = audience
    end

    # Submitter-safe error messages; empty when every row saved.
    def call
      @sections.flat_map { |section_key, values| save_section(section_key, values.to_h) }
    end

    private

    def save_section(section_key, values)
      bridge = bridge_entity(section_key)
      return [I18n.t("common.errors.dynamic.association_unavailable")] unless bridge

      targets = references(bridge).reject { |ref| ref["entity_id"].to_s == @entity.id.to_s }
      return [] if targets.none? { |ref| values[ref["name_slug"]].present? }

      input = values.merge(links(bridge))
      model = EntityEntry.build_for(bridge).new(entity: bridge, customer_id: @customer_id)
      contract = EntityEntryContract.build_for(bridge, audience: @audience, writable_slugs: input.keys).new(model)
      return contract.errors.full_messages unless contract.validate(input)

      result = Entries::Save.call(contract: contract, audience: @audience.presence || Entities::Lifecycle::SYSTEM)
      result.ok? ? [] : result.errors
    end

    def bridge_entity(section_key)
      association = @entity.associations_list.find do |item|
        bridge_id = item["bridge_entity_id"].to_s
        bridge_id == section_key.to_s || SectionSlug.for(item["bridge_entity_name"].to_s) == section_key.to_s
      end
      return unless association

      Entity.where(customer_id: [@customer_id, nil]).find_by(id: association["bridge_entity_id"])
    end

    def references(bridge)
      Array(bridge.property_schema_json).select { |attribute| attribute["type"] == Entity::ENTITY_REFERENCE_TYPE }
    end

    def links(bridge)
      references(bridge).select { |ref| ref["entity_id"].to_s == @entity.id.to_s }
                        .to_h { |ref| [ref["name_slug"], @entry.id.to_s] }
    end
  end
end
