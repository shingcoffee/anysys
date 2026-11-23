# frozen_string_literal: true

module EntityDefinitions
  # Turns LLM (or catalog-echo) hashes into persistable definitions: drops
  # serializer identity keys, allowlists attribute/association fields, and
  # rejects tenant or EntityReference smuggling.
  class Normalizer
    IDENTITY_KEYS = %w[id shared status current_version category].freeze
    ASSOCIATION_SYSTEM_KEYS = %w[target_entity_id bridge_entity_id bridge_entity_name bridge_entity_display_label].freeze
    ATTRIBUTE_KEYS = %w[
      name name_slug display_label html_type description type formula
      validators visibility validator_apply group_id config readonly storage
      owner editable lifecycle
    ].freeze
    COMPUTED_TYPES = Capabilities::AUTHORABLE_ATTRIBUTE_TYPES
    # Choice controls carry either a static list or a binding to another
    # entity's entries; `options_entity_name` is resolved to `entity_id` by
    # Persist, which is why the LLM never sends an id.
    INPUT_CONFIG_KEYS = %w[
      options options_source options_entity_name label_field
      source constant_id constant_name accept multiple
    ].freeze
    COMPUTED_CONFIG_KEYS = %w[target_entity_name function source_slug precision filter bridge_role].freeze
    HTML_TYPES = Capabilities.control_values

    Result = Struct.new(:definitions, :errors, keyword_init: true) do
      def ok? = errors.empty?
    end

    def self.call(entities)
      new(entities).call
    end

    def initialize(entities)
      @entities = Array(entities)
      @errors = []
    end

    def call
      definitions = reject_duplicate_names(@entities.filter_map { |row| normalize_entity(row) })
      Result.new(definitions: definitions, errors: @errors)
    end

    private

    # Writing two definitions for one entity means writing the first and then
    # partly overwriting it, and only one of the two can be reviewed before
    # that happens. The entity operations reject such a request
    # (entity.duplicate_in_request) before it is planned; this is the same rule at the
    # door of the write, so no caller can hand Persist a document whose second
    # definition nobody has seen.
    #
    # Both definitions are dropped rather than one being picked: a contested
    # name is not something to guess at. The recorded error already stops the
    # write (Persist halts on a normalizer error), so this only decides what a
    # caller that ignores errors would be left holding.
    def reject_duplicate_names(definitions)
      counts = definitions.map { |definition| definition["name"].to_s.strip }.tally
      duplicated = counts.select { |name, count| name.present? && count > 1 }.keys
      return definitions if duplicated.empty?

      @errors << I18n.t("ai_assistant.assistant.apply_errors.duplicate_entity_name", names: duplicated.join(", "))
      definitions.reject { |definition| duplicated.include?(definition["name"].to_s.strip) }
    end

    def normalize_entity(row)
      unless row.is_a?(Hash)
        @errors << I18n.t("ai_assistant.assistant.apply_errors.definition_not_an_object")
        return nil
      end

      definition = row.deep_stringify_keys.except(*IDENTITY_KEYS)
      if definition.key?("customer_id")
        @errors << I18n.t("ai_assistant.assistant.apply_errors.forbidden_identity")
        return nil
      end

      definition["property_schema"] = Array(definition["property_schema"]).filter_map { |attr| normalize_attribute(attr) } if definition.key?("property_schema")
      definition["associations"] = Array(definition["associations"]).filter_map { |assoc| normalize_association(assoc) } if definition.key?("associations")
      definition["attribute_groups"] = Array(definition["attribute_groups"]) if definition.key?("attribute_groups")
      definition
    end

    def normalize_association(assoc)
      unless assoc.is_a?(Hash)
        @errors << I18n.t("ai_assistant.assistant.apply_errors.definition_not_an_object")
        return nil
      end

      assoc = assoc.deep_stringify_keys.except(*ASSOCIATION_SYSTEM_KEYS)
      assoc["associated_entity_name"] = assoc["associated_entity_name"].presence || assoc.delete("target_entity_name")
      assoc.delete("target_entity_name")
      extras = Array(assoc["additional_attributes"]).filter_map { |attr| normalize_attribute(attr, extra: true) }
      assoc["additional_attributes"] = extras
      assoc.slice("associated_entity_name", "display_field", "display_field_label", "additional_attributes")
    end

    def normalize_attribute(attr, extra: false)
      unless attr.is_a?(Hash)
        @errors << I18n.t("ai_assistant.assistant.apply_errors.definition_not_an_object")
        return nil
      end

      attr = attr.deep_stringify_keys
      if attr["type"].to_s == Entity::ENTITY_REFERENCE_TYPE || attr.key?("entity_id")
        @errors << I18n.t("ai_assistant.assistant.apply_errors.forbidden_reference")
        return nil
      end

      type = attr["type"].to_s
      attr.delete("type") unless COMPUTED_TYPES.include?(type)
      if extra
        attr.delete("type")
        attr.delete("formula")
      end

      # The LLM contract permits an omitted machine identifier; persisted
      # schemas require one. Use the same identity as planning/merge rather
      # than weakening the model's slug validation. Explicit invalid slugs
      # remain invalid and cannot be silently repaired by normalization.
      attr["name_slug"] = AttributeMerge.attribute_key(attr) unless attr.key?("name_slug")

      html = attr["html_type"].to_s
      attr["html_type"] = "text" if html.blank?
      unless HTML_TYPES.include?(attr["html_type"].to_s)
        @errors << I18n.t("ai_assistant.assistant.apply_errors.invalid_html_type", value: attr["html_type"])
        return nil
      end

      attr["config"] = normalize_config(attr["config"], computed: attr["type"].to_s == Entity::COMPUTED_TYPE) if attr.key?("config")
      stored = attr.slice(*ATTRIBUTE_KEYS)
      stored.delete("owner") unless stored["owner"] == true
      stored.delete("lifecycle") if extra || !stored["lifecycle"].is_a?(Hash)
      stored
    end

    def normalize_config(config, computed:)
      return {} unless config.is_a?(Hash)

      config = config.deep_stringify_keys
      return config.slice(*COMPUTED_CONFIG_KEYS) if computed

      config = config.slice(*INPUT_CONFIG_KEYS)
      config["options"] = normalize_options(config["options"]) if config.key?("options")
      config
    end

    # The schema lets the model send a bare string per choice, but every
    # reader downstream (list filters, badge columns, page fields) indexes
    # options by "value"/"label", so they are canonicalized on the way in.
    def normalize_options(options)
      Array(options).filter_map do |option|
        case option
        when String then option.strip.presence&.then { |value| { "value" => value, "label" => value } }
        when Hash then normalize_option_pair(option)
        end
      end
    end

    def normalize_option_pair(option)
      option = option.deep_stringify_keys
      value = option["value"].to_s.strip
      label = option["label"].to_s.strip
      return nil if value.blank? && label.blank?

      pair = { "value" => value.presence || label, "label" => label.presence || value }
      pair["default"] = option["default"] if option.key?("default")
      pair
    end
  end
end
