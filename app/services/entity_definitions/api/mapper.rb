# frozen_string_literal: true

module EntityDefinitions
  module Api
    # Anti-corruption layer between the public entity vocabulary and the
    # stored definition the writer / editor persist.
    class Mapper
      AUDIENCES = EntityAttributeAudience::AUDIENCES
      SELECTION_TYPES = HtmlTypeOptions::SELECTION_TYPES
      FILE_TYPES = HtmlTypeOptions::CONFIG_TYPES.fetch(:file)
      DEFAULT_FLAGS = AUDIENCES.index_with(true).freeze
      SELECTION_CONFIG_KEYS = %w[source options constant_id constant_name options_source options_entity_name
                                 entity_id label_field].freeze
      FILE_CONFIG_KEYS = %w[accept multiple].freeze
      COMPUTED_CONFIG_KEYS = %w[target_entity_name bridge_entity_id function source_slug precision filter
                                bridge_role].freeze

      def initialize(customer:)
        @customer = customer
      end

      def to_definition(spec)
        spec = stringify(spec)
        definition = {}
        copy_if_present(definition, spec, "name", "display_label", "description")
        definition["extended_model"] = spec["extends"] if spec.key?("extends")
        apply_settings(definition, spec["settings"]) if spec.key?("settings")
        definition["attribute_groups"] = spec["attribute_groups"].map { |group| group_to_stored(group) } if spec.key?("attribute_groups")
        definition["property_schema"] = spec["attributes"].map { |attr| attribute_to_stored(attr) } if spec.key?("attributes")
        definition["associations"] = spec["associations"].map { |assoc| association_to_stored(assoc) } if spec.key?("associations")
        definition
      end

      def from_entity(entity)
        {
          "name" => entity.name,
          "display_label" => entity.display_label,
          "description" => entity.description,
          "extends" => entity.extended_model,
          "version" => entity.display_current_version&.version_number,
          "settings" => {
            "icon" => entity.icon,
            "color" => entity.color,
            "default_values" => entity.default_properties_json || {}
          },
          "attribute_groups" => Array(entity.attribute_groups_json).map { |group| group_from_stored(group) },
          "attributes" => public_attributes(entity),
          "associations" => public_associations(entity)
        }
      end

      def attribute_to_stored(attr, base: nil)
        public = stringify(attr)
        stored = base.is_a?(Hash) ? stringify(base) : {}
        assign_identity_fields(stored, public)
        stored["validators"] = rules_to_validators(public["rules"]) if public.key?("rules")
        # The editor writes audience flags on every attribute it creates.
        apply_access(stored, public["access"]) if public.key?("access") || base.nil?
        apply_kind(stored, public)
        apply_config(stored, public)
        apply_owner(stored, public)
        apply_lifecycle(stored, public, base)
        prune_stale_config!(stored)
        sync_inclusion!(stored)
        stored
      end

      def attribute_from_stored(stored)
        stored = stringify(stored)
        config = stored["config"].is_a?(Hash) ? stored["config"].stringify_keys : {}
        kind = kind_of(stored)
        public = {
          "name" => stored["name"],
          "slug" => stored["name_slug"],
          "display_label" => stored["display_label"].presence || stored["name"],
          "html_type" => stored["html_type"].presence || "text",
          "kind" => kind
        }
        public["description"] = stored["description"] if stored.key?("description")
        public["owner"] = true if stored["owner"] == true
        public["group"] = stored["group_id"] if stored["group_id"].present?
        public["rules"] = validators_to_rules(stored["validators"]) if stored.key?("validators")
        public["access"] = access_from_stored(stored)
        public["formula"] = stored["formula"] if kind == "calculated"
        public["aggregate"] = aggregate_from_config(config) if kind == "computed"
        attach_options_or_file(public, stored, config)
        lifecycle = lifecycle_to_public(stored["lifecycle"])
        public["lifecycle"] = lifecycle if lifecycle
        public
      end

      private

      attr_reader :customer

      def stringify(value)
        value.is_a?(Hash) ? value.deep_stringify_keys : {}
      end

      def parameterized(name)
        EntityEntry.attribute_slug_for(name)
      end

      def assign_identity_fields(stored, public)
        stored["name"] = public["name"] if public.key?("name")
        if public.key?("slug") || public.key?("name")
          stored["name_slug"] = public["slug"].presence || parameterized(public["name"])
        end
        if public.key?("display_label") || stored["display_label"].blank?
          stored["display_label"] = public["display_label"].presence || stored["name"] || public["name"]
        end
        stored["description"] = public["description"] if public.key?("description")
        if public.key?("html_type") || stored["html_type"].blank?
          stored["html_type"] = public["html_type"].presence || stored["html_type"].presence || "text"
        end
        stored["group_id"] = public["group"] if public.key?("group")
      end

      def copy_if_present(destination, source, *keys)
        keys.each { |key| destination[key] = source[key] if source.key?(key) }
      end

      def apply_settings(definition, settings)
        settings = stringify(settings)
        definition["icon"] = settings["icon"] if settings.key?("icon")
        definition["color"] = settings["color"] if settings.key?("color")
        definition["default_properties"] = settings["default_values"] if settings.key?("default_values")
      end

      def group_to_stored(group)
        group = stringify(group)
        stored = {}
        stored["id"] = group["key"] if group.key?("key")
        copy_if_present(stored, group, "name", "description", "icon", "color")
        stored
      end

      def group_from_stored(group)
        group = stringify(group)
        public = { "key" => group["id"] }
        copy_if_present(public, group, "name", "description", "icon", "color")
        public
      end

      def association_to_stored(assoc)
        assoc = stringify(assoc)
        display_field = assoc["display_field"].to_s
        stored = {}
        stored["associated_entity_name"] = assoc["related_entity"] if assoc.key?("related_entity")
        stored["display_field"] = display_field if assoc.key?("display_field")
        if assoc.key?("display_field_label") || assoc.key?("display_field")
          stored["display_field_label"] = assoc["display_field_label"].presence || display_field.titleize
        end
        stored["additional_attributes"] = Array(assoc["bridge_attributes"]).map { |attr| attribute_to_stored(attr) } if assoc.key?("bridge_attributes")
        stored
      end

      def public_attributes(entity)
        Array(entity.property_schema_json).filter_map do |attr|
          next unless attr.is_a?(Hash)
          next if attr["type"].to_s == Entity::ENTITY_REFERENCE_TYPE

          row = attr.except("entity_id")
          row = row.merge("config" => echo_computed_config(entity, row["config"])) if row["type"].to_s == Entity::COMPUTED_TYPE
          attribute_from_stored(row)
        end
      end

      def public_associations(entity)
        Array(entity.associations_list).map do |assoc|
          extras = Array(assoc["additional_attributes"]).reject { |attr| attr.is_a?(Hash) && attr["type"].to_s == Entity::ENTITY_REFERENCE_TYPE }
          {
            "related_entity" => assoc["target_entity_name"],
            "display_field" => assoc["display_field"],
            "display_field_label" => assoc["display_field_label"],
            "bridge_entity" => assoc["bridge_entity_name"],
            "bridge_attributes" => extras.map { |attr| attribute_from_stored(attr) }
          }
        end
      end

      def apply_owner(stored, public)
        if public["owner"] == true
          stored["owner"] = true
        elsif public.key?("owner")
          stored.delete("owner")
        end
      end

      # A patched attribute is a full read of its stored twin, so a lifecycle
      # missing from it was cleared by the patch.
      def apply_lifecycle(stored, public, base)
        lifecycle = lifecycle_to_public(public["lifecycle"]) if public.key?("lifecycle")
        if lifecycle
          stored["lifecycle"] = lifecycle
        elsif public.key?("lifecycle") || base
          stored.delete("lifecycle")
        end
      end

      # Stored and public shapes match: { "transitions" => [{ "from", "to", "by" }] }.
      def lifecycle_to_public(lifecycle)
        return unless lifecycle.is_a?(Hash)

        transitions = Array(stringify(lifecycle)["transitions"]).filter_map do |row|
          next unless row.is_a?(Hash)

          row = stringify(row)
          { "from" => row["from"].to_s.strip, "to" => row["to"].to_s.strip, "by" => Array(row["by"]).map(&:to_s).uniq }
        end
        { "transitions" => transitions } if transitions.any?
      end

      def apply_kind(stored, public)
        kind = public["kind"].to_s.presence
        case kind
        when "calculated"
          stored["type"] = "Calculated"
          stored["formula"] = public["formula"] if public.key?("formula")
          stored["readonly"] = true
          stored["storage"] = "computed"
        when "computed"
          stored["type"] = Entity::COMPUTED_TYPE
          stored["html_type"] = "number"
          stored["readonly"] = true
          stored["storage"] = "computed"
          stored.delete("formula")
        when "input"
          stored.delete("type") if %w[Calculated Computed].include?(stored["type"].to_s)
          stored.delete("formula")
          stored.delete("readonly")
          stored.delete("storage")
        end
      end

      def apply_config(stored, public)
        if public["kind"].to_s == "computed" && public.key?("aggregate")
          stored["config"] = aggregate_to_config(public["aggregate"])
        elsif public.key?("options")
          stored["config"] = options_to_config(public["options"])
        elsif public.key?("file")
          stored["config"] = file_to_config(public["file"])
        end
      end

      # The editor rebuilds an attribute's config whenever its control or kind
      # changes, so a config family the attribute no longer has is dropped
      # rather than inherited from `base`.
      def prune_stale_config!(stored)
        config = stored["config"]
        return unless config.is_a?(Hash)

        kind = kind_of(stored)
        html_type = stored["html_type"].to_s
        pruned = config.stringify_keys
        pruned = pruned.except(*COMPUTED_CONFIG_KEYS) unless kind == "computed"
        pruned = pruned.except(*SELECTION_CONFIG_KEYS) unless kind == "input" && SELECTION_TYPES.include?(html_type)
        pruned = pruned.except(*FILE_CONFIG_KEYS) unless kind == "input" && FILE_TYPES.include?(html_type)
        if pruned.empty?
          stored.delete("config")
        else
          stored["config"] = pruned
        end
      end

      def apply_access(stored, access)
        access = stringify(access)
        visibility = flags(access["visible_to"])
        apply = flags(access["rules_apply_to"]) || visibility
        stored["visibility"] = visibility
        stored["validator_apply"] = intersect(visibility, apply)
        apply_editable(stored, visibility, access.key?("editable_by") ? access["editable_by"] : stored["editable"])
      end

      # Stored only while an audience that sees the field may not change it.
      def apply_editable(stored, visibility, map)
        editable = map.is_a?(Hash) ? flags(map) : DEFAULT_FLAGS
        if AUDIENCES.any? { |audience| visibility[audience] && !editable[audience] }
          stored["editable"] = intersect(visibility, editable)
        else
          stored.delete("editable")
        end
      end

      def flags(map)
        return DEFAULT_FLAGS.dup if map.nil?

        map = stringify(map)
        AUDIENCES.index_with { |audience| map.key?(audience) ? map[audience] != false : true }
      end

      def intersect(visibility, apply)
        AUDIENCES.index_with { |audience| visibility[audience] && apply[audience] }
      end

      def access_from_stored(stored)
        visibility = stored["visibility"].is_a?(Hash) ? flags(stored["visibility"]) : DEFAULT_FLAGS.dup
        apply = stored["validator_apply"].is_a?(Hash) ? flags(stored["validator_apply"]) : visibility
        access = { "visible_to" => visibility, "rules_apply_to" => apply }
        editable = stored["editable"].is_a?(Hash) ? flags(stored["editable"]) : nil
        access["editable_by"] = editable if editable && !editable.values.all?
        access
      end

      def rules_to_validators(rules)
        Array(rules).map do |rule|
          rule = stringify(rule)
          type = rule["type"].to_s
          validator = { "type" => type }
          config = rule_config(type, rule)
          validator["config"] = config if config
          validator
        end
      end

      def rule_config(type, rule)
        case Vocabulary.rule_config_kind(type)
        when "single_value" then { "value" => rule["value"] } if rule.key?("value")
        when "range"
          config = {}
          config["min"] = rule["min"] if rule.key?("min")
          config["max"] = rule["max"] if rule.key?("max")
          config.presence
        when "pattern" then { "pattern" => rule["pattern"] } if rule.key?("pattern")
        when "list" then { "values" => Array(rule["values"]) } if rule.key?("values")
        end
      end

      def validators_to_rules(validators)
        Array(validators).filter_map do |validator|
          validator = validator.is_a?(Hash) ? stringify(validator) : { "type" => validator.to_s }
          type = validator["type"].to_s
          next if type.blank?

          rule = { "type" => type }
          config = validator["config"].is_a?(Hash) ? validator["config"].stringify_keys : {}
          case Vocabulary.rule_config_kind(type)
          when "single_value" then rule["value"] = config["value"] if config.key?("value")
          when "range"
            rule["min"] = config["min"] if config.key?("min")
            rule["max"] = config["max"] if config.key?("max")
          when "pattern" then rule["pattern"] = config["pattern"] if config.key?("pattern")
          when "list" then rule["values"] = Array(config["values"]) if config.key?("values")
          end
          rule
        end
      end

      def options_to_config(options)
        options = stringify(options)
        case options["source"].to_s
        when "static"
          { "source" => "manual", "options" => static_options(options["values"]) }
        when "constant"
          constant_config(options["constant"])
        when "entity_entries"
          entity_entries_config(options)
        else
          {}
        end
      end

      def static_options(values)
        Array(values).filter_map do |value|
          case value
          when String
            text = value.strip
            next if text.blank?

            { "label" => text, "value" => text, "default" => false }
          when Hash
            option = stringify(value)
            label = option["label"].to_s.strip
            stored_value = option["value"].to_s.strip
            next if label.blank? && stored_value.blank?

            {
              "label" => label.presence || stored_value,
              "value" => stored_value.presence || label,
              "default" => option.key?("default") ? option["default"] : false
            }
          end
        end
      end

      def constant_config(name)
        constant = find_constant(name)
        config = { "source" => "constant", "constant_name" => name.to_s }
        return config unless constant

        config.merge(
          "constant_id" => constant.id,
          "constant_name" => constant.name,
          "options" => Array(constant.options)
        )
      end

      def find_constant(name)
        return if name.blank? || customer.blank?

        Current.with_customer(customer) do
          rows = Constant.where(customer_id: [customer.id, nil], name: name).to_a
          rows.find { |row| row.customer_id == customer.id } || rows.first
        end
      end

      def entity_entries_config(options)
        config = { "options_entity_name" => options["entity"] }
        config["label_field"] = options["label_field"] if options.key?("label_field")
        config
      end

      def file_to_config(file)
        file = stringify(file)
        config = {}
        config["accept"] = file["accept"] if file.key?("accept")
        config["multiple"] = file.key?("multiple") ? file["multiple"] : false
        config
      end

      def aggregate_to_config(aggregate)
        aggregate = stringify(aggregate)
        config = {
          "target_entity_name" => aggregate["related_entity"],
          "function" => aggregate["function"],
          "bridge_role" => aggregate["direction"].presence || "source"
        }
        config["source_slug"] = aggregate["source_attribute"] if aggregate.key?("source_attribute")
        config["precision"] = aggregate["precision"] if aggregate.key?("precision")
        config["filter"] = filter_to_stored(aggregate["filter"]) if aggregate.key?("filter")
        config
      end

      def filter_to_stored(filter)
        filter = stringify(filter)
        stored = {}
        stored["slug"] = filter["attribute"] if filter.key?("attribute")
        stored["op"] = filter["operator"] if filter.key?("operator")
        stored["value"] = filter["value"] if filter.key?("value")
        stored
      end

      def aggregate_from_config(config)
        aggregate = {
          "related_entity" => config["target_entity_name"],
          "function" => config["function"],
          "direction" => config["bridge_role"].presence || "source"
        }
        aggregate["source_attribute"] = config["source_slug"] if config.key?("source_slug")
        aggregate["precision"] = config["precision"] if config.key?("precision")
        aggregate["filter"] = filter_from_stored(config["filter"]) if config["filter"].is_a?(Hash)
        aggregate
      end

      def filter_from_stored(filter)
        filter = stringify(filter)
        public = {}
        public["attribute"] = filter["slug"] if filter.key?("slug")
        public["operator"] = filter["op"] if filter.key?("op")
        public["value"] = filter["value"] if filter.key?("value")
        public
      end

      def attach_options_or_file(public, stored, config)
        if selection_config?(stored, config)
          public["options"] = options_from_config(config)
        elsif file_config?(stored, config)
          public["file"] = file_from_config(config)
        end
      end

      def selection_config?(stored, config)
        SELECTION_TYPES.include?(stored["html_type"].to_s) && config.present?
      end

      def file_config?(stored, config)
        FILE_TYPES.include?(stored["html_type"].to_s) && (config.key?("accept") || config.key?("multiple"))
      end

      def options_from_config(config)
        if config["source"].to_s == "constant" || config["constant_name"].present? || config["constant_id"].present?
          { "source" => "constant", "constant" => config["constant_name"] }
        elsif config["options_source"].to_s == Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE || config["options_entity_name"].present?
          options = { "source" => "entity_entries", "entity" => config["options_entity_name"] }
          options["label_field"] = config["label_field"] if config.key?("label_field")
          options
        else
          { "source" => "static", "values" => public_option_values(config["options"]) }
        end
      end

      def public_option_values(options)
        Array(options).filter_map do |option|
          case option
          when String then option.strip.presence
          when Hash
            option = stringify(option)
            label = option["label"].to_s.strip
            value = option["value"].to_s.strip
            next if label.blank? && value.blank?

            value = value.presence || label
            label = label.presence || value
            default = option["default"]
            if label == value && default != true
              value
            else
              row = { "label" => label, "value" => value }
              row["default"] = default if option.key?("default")
              row
            end
          end
        end
      end

      def file_from_config(config)
        file = {}
        file["accept"] = config["accept"] if config.key?("accept")
        file["multiple"] = config["multiple"] if config.key?("multiple")
        file
      end

      def kind_of(stored)
        case stored["type"].to_s
        when "Calculated" then "calculated"
        when Entity::COMPUTED_TYPE then "computed"
        else "input"
        end
      end

      def sync_inclusion!(stored)
        return unless SELECTION_TYPES.include?(stored["html_type"].to_s)

        config = stored["config"]
        return unless config.is_a?(Hash)
        return unless static_or_constant?(config)

        values = inclusion_values(config)
        validators = Array(stored["validators"]).map { |validator| normalize_validator(validator) }
        validators.reject! { |validator| validator["type"].to_s == "inclusion" }
        validators << { "type" => "inclusion", "config" => { "values" => values } } if values.any?
        stored["validators"] = validators
      end

      def static_or_constant?(config)
        source = config["source"].to_s
        source == "manual" || source == "constant" || (source.blank? && config["options"].present? && config["options_entity_name"].blank?)
      end

      def inclusion_values(config)
        Array(config["options"]).filter_map do |option|
          case option
          when String then option.strip.presence
          when Hash
            option = stringify(option)
            option["value"].to_s.strip.presence || option["label"].to_s.strip.presence
          end
        end
      end

      def normalize_validator(validator)
        validator.is_a?(Hash) ? stringify(validator) : { "type" => validator.to_s }
      end

      def echo_computed_config(entity, config)
        config = (config || {}).stringify_keys
        if config["target_entity_name"].blank? && config["bridge_entity_id"].present?
          config["target_entity_name"] = related_entity_name(entity, config)
        end
        config.except("bridge_entity_id")
      end

      def related_entity_name(entity, config)
        assoc = Array(entity.associations_list).find { |row| row["bridge_entity_id"].to_s == config["bridge_entity_id"].to_s }
        return assoc["target_entity_name"] if assoc

        related_name_from_bridge(config["bridge_entity_id"])
      end

      def related_name_from_bridge(bridge_id)
        return if customer.blank? || bridge_id.blank?

        bridge = Entity.where(customer_id: customer.id, category: :bridge).find_by(id: bridge_id.to_i)
        return unless bridge

        source_ref = Array(bridge.property_schema_json)[0]
        return unless source_ref.is_a?(Hash)

        Entity.where(customer_id: customer.id).find_by(id: source_ref["entity_id"].to_i)&.name || source_ref["name"]
      end
    end
  end
end
