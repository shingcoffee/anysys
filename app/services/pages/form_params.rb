# frozen_string_literal: true

module Pages
  # Shape- and audience-aware boundary for primary and bridge fields.
  # Only page-declared namespaces backed by an accessible entity schema survive.
  # Base-model fields are metadata-only: no base-record resolver, write contract
  # or authenticated persistence adapter exists in the page execution chain.
  class FormParams
    SCALAR_TYPES = ActionController::Parameters::PERMITTED_SCALAR_TYPES
    UPLOAD_TYPES = [ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile].freeze
    SLUG = /\A[a-zA-Z0-9_]+\z/

    def self.permit(page:, entity:, params:, audience: nil)
      new(page: page, entity: entity, params: params, audience: audience).permit
    end

    def self.permit_parts(page:, entity:, params:, audience: nil)
      new(page: page, entity: entity, params: params, audience: audience).permit_parts
    end

    def self.visible_field?(page:, field:, audience:)
      new(page: page, entity: page.entity, params: {}, audience: audience).visible_field?(field)
    end

    def self.editable_field?(page:, field:, audience:)
      new(page: page, entity: page.entity, params: {}, audience: audience).editable_field?(field)
    end

    def self.permit_identity(page:, entity:, params:, audience: nil)
      new(page: page, entity: entity, params: params, audience: audience).permit_identity
    end

    def self.identity_field?(field)
      identity_key(field).present? && field["source"] == "identity"
    end

    # A field of the page's own entity (not a base model, bridge or identity field).
    def self.primary_field?(field)
      %w[base_model bridge identity].exclude?(field["source"])
    end

    def self.primary_slugs(page)
      Page.input_fields_in(page.configuration_json).select { |field| primary_field?(field) }
          .filter_map { |field| field["property_slug"].presence&.to_s }
    end

    def self.identity_key(field)
      return unless field.is_a?(Hash)

      key = (field["property_slug"].presence || field["id"]).to_s
      key if People::IDENTITY_KEYS.include?(key)
    end

    def self.base_submission?(params)
      return false unless params.is_a?(Hash) || params.is_a?(ActionController::Parameters)

      value = params.key?("base") ? params["base"] : params[:base]
      return false if value.nil?

      !(value.is_a?(Hash) || value.is_a?(ActionController::Parameters)) || !value.empty?
    end

    def initialize(page:, entity:, params:, audience: nil)
      @page = page
      @entity = entity
      @params = hash_like(params)
      @audience = audience
      @customer_id = Current.customer_id || page.customer_id
      @group_keys = []
    end

    # True when this audience must supply the field: the bound attribute has a
    # presence validator that applies here. Page configuration can still force
    # the marker on its own; this only answers the schema question.
    def required_field?(field)
      return false if self.class.identity_field?(field)
      return false if owner_hidden_from_member?(field)

      attribute = attribute_for(field)
      return false unless attribute.is_a?(Hash)
      return false if %w[Calculated Computed].include?(attribute["type"])
      return false if attribute["storage"] == "computed" || attribute["readonly"] == true
      return false unless EntityAttributeAudience.applying_audiences(attribute).include?(@audience.to_s)

      Array(attribute["validators"]).any? { |validator| validator.is_a?(Hash) && validator["type"] == "presence" }
    end

    def visible_field?(field)
      return identity_visible? if self.class.identity_field?(field)
      return false if field["source"] == "base_model"
      return false unless valid_slug?(field["property_slug"] || field["id"])
      return false if owner_hidden_from_member?(field)
      # A UI-only preview has no persistence binding. An unresolved/foreign
      # metadata binding or an explicitly entity/bridge-sourced field must not
      # fall back to that preview path.
      unless @entity
        return field["source"].blank? && @page.configuration_json&.dig("metadata", "entity_id").blank?
      end

      attribute = attribute_for(field)
      attribute.present? && EntityAttributeAudience.visible_to?(attribute, @audience)
    end

    # A visible field this audience may also change. One it sees but may not
    # change renders read-only, and its posted value is dropped (#permit).
    def editable_field?(field)
      return false unless visible_field?(field)

      attribute = attribute_for(field)
      attribute.nil? || EntityAttributeAudience.editable_by?(attribute, @audience)
    end

    def read_only_fields?
      @entity.nil?
    end

    # The File or Image attribute a field is bound to, if any.
    def file_attribute(field)
      attribute = attribute_for(field)
      attribute if EntityEntry.file_attribute?(attribute)
    end

    def permit
      primary, associations = permit_parts
      return primary if associations.empty?

      { "entity" => primary, "assoc" => associations }
    end

    # What a new record starts with for the attributes this page leaves to the
    # system for this audience — ones it may not change or the page leaves
    # off — from the definition's defaults. Never the owner reference, which
    # the server fills.
    def starting_values
      return {} unless @entity && accessible?(@entity)

      offered = primary_schema.map { |attribute| attribute["name_slug"].to_s }
      left = Array(@entity.property_schema_json).grep(Hash).filter_map do |attribute|
        slug = attribute["name_slug"].to_s
        next if !valid_slug?(slug) || %w[Calculated Computed].include?(attribute["type"]) || attribute["storage"] == "computed"

        slug unless offered.include?(slug) || slug == owner_slug(@entity)
      end
      Entities::AttributeDefaults.call(@entity, left)
    end

    # [primary attributes, { bridge section key => attributes }]
    def permit_parts
      return [{}, {}] unless @entity && accessible?(@entity)

      raw_primary = @params.key?("entity") ? hash_like(@params["entity"]) : @params
      primary = permit_schema(raw_primary, primary_schema, primary_fields)

      associations = permit_associations
      qualified = primary.dup
      associations.each do |section, values|
        values.each { |slug, value| qualified["assoc.#{section}.#{slug}"] = value }
      end

      engine = Pages::RulesEngine.new(@page)
      allowed_keys = primary_schema.map { |attribute| attribute["name_slug"] } + @group_keys
      qualified = engine.apply(qualified, allowed_keys: allowed_keys).slice(*allowed_keys)
      primary = qualified.reject { |key, _| key.start_with?("assoc.") }
      sections = associations.to_h do |section, _values|
        prefix = "assoc.#{section}."
        filtered = qualified.each_with_object({}) do |(key, value), out|
          out[key.delete_prefix(prefix)] = value if key.start_with?(prefix)
        end
        [section, filtered]
      end
      [primary, sections]
    end

    # Only the identity fields this person page places; a page without them
    # accepts no identity at all.
    def permit_identity
      return {} unless identity_audience? && @entity&.person?

      raw = hash_like(@params["identity"])
      declared = fields.filter_map { |field| self.class.identity_key(field) if self.class.identity_field?(field) }
      declared.uniq.each_with_object({}) do |key, out|
        next unless raw.key?(key)

        value = raw[key]
        out[key] = value if value.is_a?(String)
      end
    end

    private

    def identity_audience?
      @audience.to_s != EntityAttributeAudience::MEMBER
    end

    def identity_visible?
      identity_audience?
    end

    def fields = @fields ||= Page.input_fields_in(@page.configuration_json)

    def primary_fields = @primary_fields ||= fields.select { |field| self.class.primary_field?(field) }

    # The page entity's attributes this audience may set here: every writable
    # one, or only those the page places when it places any.
    def primary_schema
      @primary_schema ||= if fields.empty?
        writable_schema(@entity)
      else
        writable_schema(@entity).select do |attr|
          primary_fields.any? { |field| field["property_slug"] == attr["name_slug"] }
        end
      end
    end

    def hash_like(value)
      return value if value.is_a?(ActionController::Parameters)
      value.is_a?(Hash) ? value.stringify_keys : {}
    end

    def accessible?(entity)
      @customer_id.present? && (entity.customer_id.nil? || entity.customer_id.to_s == @customer_id.to_s)
    end

    def valid_slug?(slug)
      slug.to_s.match?(SLUG)
    end

    def owner_hidden_from_member?(field)
      return false unless @audience.to_s == EntityAttributeAudience::MEMBER

      slug = (field["property_slug"] || field["id"]).to_s
      return false unless valid_slug?(slug)

      entity = field["source"] == "bridge" ? bridge_entity(field["source_section"]) : @entity
      return false unless entity

      owner_slug(entity) == slug
    end

    def owner_slug(entity)
      @owner_slugs ||= {}
      return @owner_slugs[entity.id] if @owner_slugs.key?(entity.id)

      @owner_slugs[entity.id] = People::Ownership.owner_reference(entity)&.slug
    end

    def writable_schema(entity)
      Array(entity&.property_schema_json).select do |attribute|
        valid_slug?(attribute["name_slug"]) && !%w[Calculated Computed].include?(attribute["type"]) &&
          attribute["storage"] != "computed" && EntityAttributeAudience.editable_by?(attribute, @audience)
      end
    end

    def attribute_for(field)
      return nil if field["source"] == "base_model"
      entity = field["source"] == "bridge" ? bridge_entity(field["source_section"]) : @entity
      return nil unless entity && accessible?(entity)
      Array(entity&.property_schema_json).find { |attribute| attribute["name_slug"] == field["property_slug"] }
    end

    def permit_schema(raw, schema, configured_fields)
      schema.each_with_object({}) do |attribute, out|
        slug = attribute["name_slug"]
        next unless raw.key?(slug)
        field = configured_fields.find { |item| item["property_slug"] == slug } || attribute
        next if field["storage"] == "computed"
        value = raw[slug]
        if EntityEntry.file_attribute?(attribute)
          uploads = uploads_in(value)
          out[slug] = EntityEntry.multiple_files?(attribute) ? uploads : uploads.last if uploads.any?
          next
        end

        array = field["html_type"] == "multi-select"
        valid = array ? value.is_a?(Array) && value.all? { |item| scalar?(item) } : scalar?(value)
        out[slug] = value if valid
      end
    end

    def scalar?(value)
      SCALAR_TYPES.any? { |type| value.is_a?(type) }
    end

    # Only files the browser uploaded: Active Storage would read a posted
    # string as the signed id of a blob that is already stored.
    def uploads_in(value)
      Array.wrap(value).select { |item| UPLOAD_TYPES.any? { |type| item.is_a?(type) } }
    end

    def permit_associations
      raw = hash_like(@params["assoc"])
      fields.select { |field| field["source"] == "bridge" }.group_by { |field| field["source_section"] }.each_with_object({}) do |(section, configured), out|
        section_key = SectionSlug.for(section)
        next unless valid_slug?(section_key)
        entity = bridge_entity(section)
        next unless entity && accessible?(entity)
        schema = writable_schema(entity).select { |attribute| configured.any? { |field| field["property_slug"] == attribute["name_slug"] } }
        @group_keys.concat(schema.map { |attribute| "assoc.#{section_key}.#{attribute['name_slug']}" })
        values = permit_schema(hash_like(raw[section_key]), schema, configured)
        out[section_key] = values if schema.any?
      end
    end

    def bridge_entity(section)
      @bridges ||= {}
      return @bridges[section] if @bridges.key?(section)
      association = Array(@entity&.associations_json).find do |item|
        next true if item["bridge_entity_id"].present? && item["bridge_entity_id"].to_s == section.to_s
        bridge = Entity.where(customer_id: [@customer_id, nil]).find_by(id: item["bridge_entity_id"])
        bridge && (bridge.id.to_s == section.to_s || bridge.name == section)
      end
      @bridges[section] = association && Entity.where(customer_id: [@customer_id, nil]).find_by(id: association["bridge_entity_id"])
    end
  end
end
