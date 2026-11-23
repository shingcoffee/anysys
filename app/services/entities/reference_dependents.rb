# frozen_string_literal: true

module Entities
  # What reads an entity's records as references, in the definitions the
  # affected tenants actually use: customer-owned definitions, shared defaults
  # and every tenant override of them. Backs the trash guard and the
  # display-field save guard.
  class ReferenceDependents
    Reference = Data.define(:entity, :field_label, :label_field)
    Form = Data.define(:page, :field_label, :audiences)

    OPTIONS_SOURCE = ReferenceLabels::OPTIONS_SOURCE

    # A shared entity can be referenced from any tenant; a customer's only
    # from that customer.
    def self.for_trash(entity)
      new(entity, tenant_ids: entity.customer_id ? [entity.customer_id] : nil)
    end

    # The tenants whose view of `entity` this save changes: its owner, the
    # tenant whose override is being written, or, for a shared default, every
    # tenant that has no override of its own.
    def self.for_save(entity)
      if entity.customer_id
        new(entity, tenant_ids: [entity.customer_id])
      elsif (tenant_id = entity.override_customer_id)
        new(entity, tenant_ids: [tenant_id])
      else
        new(entity, tenant_ids: nil, excluded_tenant_ids: entity.entity_customer_heads.pluck(:customer_id))
      end
    end

    def self.field_paths(references)
      references.map do |ref|
        I18n.t("common.references.field_path", entity: ref.entity.display_label, field: ref.field_label)
      end.uniq
    end

    def initialize(entity, tenant_ids:, excluded_tenant_ids: [])
      @entity = entity
      @tenant_ids = tenant_ids
      @excluded = excluded_tenant_ids.to_set
    end

    def references
      @references ||= definitions(referrers).flat_map { |record, payload| references_in(record, payload) }
    end

    # Launched forms whose entity-records dropdowns list this entity by `label_field`.
    def forms(label_field)
      slug = label_field.to_s
      launched_pages.flat_map do |page, config|
        Page.input_fields_in(config).filter_map do |field|
          dynamic = field["dynamic_options"]
          next unless dynamic.is_a?(Hash) && dynamic["options_source"] == OPTIONS_SOURCE
          next unless dynamic["entity_id"].to_s == @entity.id.to_s && dynamic["label_field"].to_s == slug

          Form.new(page: page, field_label: field["label"].presence || field["id"].to_s, audiences: page.visible_audiences)
        end
      end
    end

    private

    # Other non-bridge entities; trashed ones are outside the default scope.
    # A bridge's reference mirrors its source's association, which is
    # reported from the source.
    def referrers
      scope = Entity.non_bridge.where.not(id: @entity.id)
      owned = @tenant_ids ? scope.where(customer_id: @tenant_ids) : scope.where.not(customer_id: nil)
      owned.to_a + scope.where(customer_id: nil).to_a
    end

    def launched_pages
      @launched_pages ||= begin
        scope = Page.launched
        owned = @tenant_ids ? scope.where(customer_id: @tenant_ids) : scope.where.not(customer_id: nil)
        definitions(owned.to_a + scope.where(customer_id: nil).to_a)
      end
    end

    # [[record, parsed payload], ...] for every definition line that applies
    # to an affected tenant.
    def definitions(records)
      records.flat_map do |record|
        applicable_versions(record).filter_map do |version|
          payload = version&.content&.payload
          [record, JSON.parse(payload)] if payload.present?
        rescue JSON::ParserError
          nil
        end
      end
    end

    def applicable_versions(record)
      return [record.current_version] if record.customer_id

      reflection = record.class.versionable_options[:customer_head_reflection]
      heads = record.public_send(reflection).includes(current_version: :content).to_a
      overridden = heads.map(&:customer_id)
      versions = heads.select { |head| affected?(head.customer_id) }.map(&:current_version)
      versions << record.current_version if @tenant_ids.nil? || (@tenant_ids - overridden).any?
      versions
    end

    def affected?(tenant_id)
      (@tenant_ids.nil? || @tenant_ids.include?(tenant_id)) && !@excluded.include?(tenant_id)
    end

    def references_in(record, payload)
      schema = Array(payload["property_schema"]).grep(Hash)
      associations = Array(payload["associations"]).grep(Hash)
      extras = associations.flat_map { |assoc| Array(assoc["additional_attributes"]).grep(Hash) }

      dropdowns = (schema + extras).select { |attr| references_entity?(attr) }.map do |attr|
        Reference.new(entity: record,
                      field_label: attr["display_label"].presence || attr["name"].presence || attr["name_slug"].to_s,
                      label_field: attr.dig("config", "label_field").to_s)
      end
      links = associations.select { |assoc| assoc["target_entity_id"].to_s == @entity.id.to_s }.map do |assoc|
        Reference.new(entity: record, field_label: assoc["target_entity_name"].presence || @entity.display_label,
                      label_field: assoc["display_field"].to_s)
      end
      dropdowns + links
    end

    def references_entity?(attr)
      ReferenceLabels.reference?(attr) && attr.dig("config", "entity_id").to_s == @entity.id.to_s
    end
  end
end
