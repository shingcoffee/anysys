# frozen_string_literal: true

module Pages
  # Submit-boundary ownership checks. Runs after FormParams
  # permits input and before anything is written. Flowchart runtime never
  # calls this: flowcharts must see every row.
  class AudienceGuard
    Result = Data.define(:primary, :sections, :error) do
      def rejected? = !error.nil?
    end

    RESTRICTED_KINDS = %i[person owned private nested].freeze
    BLOCKED_PUBLIC_KINDS = %i[owned private nested].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(entity:, primary:, sections:, viewer:, audience:, customer_id:)
      @entity = entity
      @primary = stringify(primary)
      @sections = stringify_sections(sections)
      @viewer = viewer
      @audience = audience.to_s
      @customer_id = customer_id
      @descriptors = {}
    end

    def call
      case @audience
      when EntityAttributeAudience::ADMIN then ok
      when EntityAttributeAudience::MEMBER then guard_member
      when EntityAttributeAudience::PUBLIC then guard_public
      else reject(sign_in_required)
      end
    end

    private

    def guard_member
      return reject(sign_in_required) unless same_tenant_viewer?

      strip_back_references
      error = bind_owner(@entity, @primary)
      return reject(error) if error

      @sections.each do |key, values|
        bridge = bridge_entity(key)
        next unless bridge
        next if owner_is_primary_back_reference?(bridge)
        next unless section_filled?(bridge, values)

        error = bind_owner(bridge, values)
        return reject(error) if error
      end

      error = check_references
      return reject(error) if error

      ok
    end

    def guard_public
      return reject(sign_in_required) if blocked_public_kind?(@entity)

      strip_back_references
      @sections.each do |key, values|
        bridge = bridge_entity(key)
        next unless bridge
        next unless section_filled?(bridge, values)
        return reject(sign_in_required) if blocked_public_kind?(bridge)
      end

      error = check_references
      return reject(error) if error

      ok
    end

    def same_tenant_viewer?
      @viewer && @customer_id.present? && @viewer.customer_id.to_s == @customer_id.to_s
    end

    # Pages::BridgeEntries links each row to the new primary entry; a submitted
    # back-reference names some other record and must not reach the flowchart
    # or a module handoff.
    def strip_back_references
      @sections.each do |key, values|
        bridge = bridge_entity(key)
        back_reference_slugs(bridge).each { |slug| values.delete(slug) } if bridge
      end
    end

    def bind_owner(entity, attrs)
      owner = descriptor(entity).owner
      return unless owner

      entry_id = People::Ownership.person_entry_id(@viewer, owner.person_entity_id)
      return profile_required(owner) unless entry_id

      attrs[owner.slug] = entry_id.to_s
      nil
    end

    def owner_is_primary_back_reference?(bridge)
      owner = descriptor(bridge).owner
      owner && owner.person_entity_id.to_s == @entity.id.to_s
    end

    def check_references
      error = check_entity_references(@entity, @primary, skip_slugs: owner_slugs(@entity))
      return error if error

      @sections.each do |key, values|
        bridge = bridge_entity(key)
        next unless bridge

        skip = owner_slugs(bridge) + back_reference_slugs(bridge)
        error = check_entity_references(bridge, values, skip_slugs: skip)
        return error if error
      end
      nil
    end

    def check_entity_references(entity, attrs, skip_slugs:)
      reference_attributes(entity).each do |attribute|
        slug = attribute["name_slug"].to_s
        next if skip_slugs.include?(slug)

        value = attrs[slug]
        next if value.blank?

        target = target_entity(attribute)
        return reference_not_allowed(attribute) unless target
        next unless RESTRICTED_KINDS.include?(descriptor(target).kind)

        allowed = People::Ownership.reachable_ids(
          target, [value], viewer: @viewer, audience: @audience, customer_id: @customer_id
        )
        return reference_not_allowed(attribute) unless allowed.include?(value.to_s)
      end
      nil
    end

    def owner_slugs(entity)
      owner = descriptor(entity).owner
      owner ? [owner.slug] : []
    end

    def back_reference_slugs(entity)
      reference_attributes(entity).filter_map do |attribute|
        next unless attribute["type"] == Entity::ENTITY_REFERENCE_TYPE
        next unless attribute["entity_id"].to_s == @entity.id.to_s

        attribute["name_slug"].to_s
      end
    end

    # Any reference other than the back-reference counts, so a section filled
    # only through an entity_entries select is still checked.
    def section_filled?(bridge, values)
      back = back_reference_slugs(bridge)
      reference_attributes(bridge).any? do |attribute|
        slug = attribute["name_slug"].to_s
        !back.include?(slug) && values[slug].present?
      end
    end

    def blocked_public_kind?(entity)
      BLOCKED_PUBLIC_KINDS.include?(descriptor(entity).kind)
    end

    def descriptor(entity)
      @descriptors[entity.id] ||= People::Ownership.describe(entity)
    end

    def reference_attributes(entity)
      Array(entity.property_schema_json).grep(Hash).select do |attribute|
        attribute["type"] == Entity::ENTITY_REFERENCE_TYPE || Entities::ReferenceLabels.reference?(attribute)
      end
    end

    def reference_target_id(attribute)
      if attribute["type"] == Entity::ENTITY_REFERENCE_TYPE
        attribute["entity_id"].presence
      elsif Entities::ReferenceLabels.reference?(attribute)
        attribute.dig("config", "entity_id").presence
      end
    end

    def target_entity(attribute)
      id = reference_target_id(attribute)
      return if id.blank?

      Entity.where(customer_id: [@customer_id, nil]).find_by(id: id)
    end

    def bridge_entity(section_key)
      key = section_key.to_s
      @bridges ||= {}
      return @bridges[key] if @bridges.key?(key)

      slug = SectionSlug.for(key)
      association = Array(@entity.associations_json).grep(Hash).find do |item|
        item["bridge_entity_id"].to_s == key ||
          item["bridge_entity_name"].to_s == key ||
          SectionSlug.for(item["bridge_entity_name"].to_s) == slug
      end
      @bridges[key] = association && Entity.where(customer_id: [@customer_id, nil]).find_by(id: association["bridge_entity_id"])
    end

    def field_label(attribute)
      attribute["name"].presence || attribute["name_slug"].to_s
    end

    def profile_required(owner)
      record = Entity.unscoped.where(id: owner.person_entity_id, customer_id: [@customer_id, nil]).first
      name = record&.display_label.presence || record&.name || I18n.t("common.labels.entity")
      I18n.t("common.errors.dynamic.profile_required", entity: name)
    end

    def reference_not_allowed(attribute)
      I18n.t("common.errors.dynamic.reference_not_allowed", field: field_label(attribute))
    end

    def sign_in_required
      I18n.t("common.errors.dynamic.sign_in_required")
    end

    def ok
      Result.new(primary: @primary, sections: @sections, error: nil)
    end

    def reject(message)
      Result.new(primary: @primary, sections: @sections, error: message)
    end

    def stringify(hash)
      hash.to_h.transform_keys(&:to_s)
    end

    def stringify_sections(sections)
      stringify(sections).transform_values { |values| stringify(values) }
    end
  end
end
