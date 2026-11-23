# frozen_string_literal: true

module Pages
  # Display-only query values for a page form. Submission validation is unchanged.
  class Prefill
    def self.values(page:, params:, audience:, viewer:)
      new(page: page, params: params, audience: audience, viewer: viewer).values
    end

    def initialize(page:, params:, audience:, viewer:)
      @page = page
      @params = params
      @audience = audience
      @viewer = viewer
      @customer_id = Current.customer_id || page.customer_id
      @boundary = FormParams.new(page: page, entity: page.entity, params: {}, audience: audience)
    end

    def values
      raw = extract_prefill
      kept = {}
      raw.each do |key, value|
        break if kept.size >= ActionLink::MAX_PREFILL_KEYS
        next if value.is_a?(Hash) || value.is_a?(Array)

        slug = key.to_s
        next unless slug.match?(FormParams::SLUG)

        text = value.to_s
        next if text.length > ActionLink::MAX_PREFILL_VALUE
        next unless keep?(slug, text)

        kept[slug] = text
      end
      kept
    end

    private

    def extract_prefill
      source = hash_like(@params)
      raw = source.key?("prefill") ? source["prefill"] : source[:prefill]
      return {} unless raw.is_a?(Hash) || raw.is_a?(ActionController::Parameters)

      raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    rescue StandardError
      {}
    end

    def hash_like(value)
      return value if value.is_a?(ActionController::Parameters)
      value.is_a?(Hash) ? value.stringify_keys : {}
    end

    def keep?(slug, text)
      field = field_for(slug)
      return false unless field
      return false unless @boundary.visible_field?(field)
      return false if owner_reference?(field, slug)
      # A file field shows the files a record holds, never text from a link.
      return false if EntityEntry.file_attribute?(attribute_for(field))
      return true unless reference_attribute?(attribute_for(field))

      reachable_reference?(attribute_for(field), text)
    end

    def field_for(slug)
      page_fields.find { |field| (field["property_slug"] || field["id"]).to_s == slug }
    end

    def page_fields
      @page_fields ||= Page.input_fields_in(@page.configuration_json)
    end

    def owner_reference?(field, slug)
      entity = entity_for(field)
      return false unless entity

      People::Ownership.owner_reference(entity)&.slug == slug
    end

    def attribute_for(field)
      entity = entity_for(field)
      return unless entity

      Array(entity.property_schema_json).grep(Hash).find { |attribute| attribute["name_slug"] == field["property_slug"] }
    end

    def entity_for(field)
      field["source"] == "bridge" ? bridge_entity(field["source_section"]) : @page.entity
    end

    def bridge_entity(section)
      @bridges ||= {}
      return @bridges[section] if @bridges.key?(section)

      association = Array(@page.entity&.associations_json).grep(Hash).find do |item|
        next true if item["bridge_entity_id"].present? && item["bridge_entity_id"].to_s == section.to_s

        bridge = Entity.where(customer_id: [@customer_id, nil]).find_by(id: item["bridge_entity_id"])
        bridge && (bridge.id.to_s == section.to_s || bridge.name == section)
      end
      @bridges[section] = association && Entity.where(customer_id: [@customer_id, nil]).find_by(id: association["bridge_entity_id"])
    end

    def reference_attribute?(attribute)
      attribute.is_a?(Hash) && (
        attribute["type"] == Entity::ENTITY_REFERENCE_TYPE || Entities::ReferenceLabels.reference?(attribute)
      )
    end

    def reachable_reference?(attribute, text)
      target = target_entity(attribute)
      return false unless target

      People::Ownership.reachable_ids(
        target, [text], viewer: @viewer, audience: @audience, customer_id: @customer_id
      ).include?(text)
    end

    def target_entity(attribute)
      id =
        if attribute["type"] == Entity::ENTITY_REFERENCE_TYPE
          attribute["entity_id"].presence
        else
          attribute.dig("config", "entity_id").presence
        end
      return if id.blank?

      Entity.where(customer_id: [@customer_id, nil]).find_by(id: id)
    end
  end
end
