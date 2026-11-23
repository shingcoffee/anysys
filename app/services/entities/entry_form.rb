# frozen_string_literal: true

require "date"

module Entities
  # Primary-entry input boundary. Reform owns configured validation; this service
  # only describes supported controls and checks their request shapes/literals.
  class EntryForm
    Group = Struct.new(:key, :label, :fields, keyword_init: true)
    Field = Struct.new(:slug, :label, :help_text, :html_type, :required, :options,
                       :constraints, :full_width, :invalid_literal, :reference, keyword_init: true)
    # The referenced entity (nil when unusable) and its display field slug.
    Reference = Struct.new(:entity, :label_field, keyword_init: true)

    HTML_TYPES = %w[text search tel url email textarea number date datetime-local select multi-select radio checkbox switch].freeze
    CHOICE_TYPES = %w[select multi-select radio].freeze
    BOOLEAN_TYPES = %w[checkbox switch].freeze
    NUMBER_LITERAL = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/
    # HTML number inputs sanitize leading '+' and trailing decimal points.
    HTML_NUMBER_LITERAL = /\A-?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?\z/
    ERROR_SCOPE = "admin_misc.entities.entry_form"

    attr_reader :entity, :customer, :entry, :groups, :writable_slugs, :filtered_input, :values, :errors, :blockers, :links

    # +entry+ edits an existing record: its stored data stands in for the
    # definition defaults, both for the GET prefill and for keys a submission omits.
    # +links+ ({ slug => id }) makes this a bridge row form: those participant
    # references are written as given and never shown, and the bridge's other
    # participant references become dropdowns.
    def initialize(entity:, customer:, params: nil, entry: nil, links: {})
      @customer = customer
      @entry = entry
      @links = links.to_h.transform_keys(&:to_s).freeze
      @errors = {}
      @blockers = []
      @values = {}
      @filtered_input = {}
      Current.set(customer: customer, shared_resources_mode: false) do
        # A fresh read discards stale/global hydration and submitted definition edits.
        @entity = Entity.find(entity.id)
        build_groups
        @writable_slugs = (groups.flat_map { |group| group.fields.map(&:slug) } + @links.keys).freeze
        add_readiness_errors
        build_input(params)
      end
    end

    def available? = blockers.empty? && (writable_slugs - links.keys).any?
    def persisted? = entry.present?
    def value_for(slug) = values[slug.to_s]
    def errors_for(slug) = errors.fetch(slug.to_s, [])

    def add_errors!(messages)
      messages.each_pair do |slug, entries|
        errors[slug.to_s] = (errors_for(slug) + Array(entries)).uniq
      end
      self
    end

    private

    def build_groups
      internal = EntityEntry.column_names + %w[entity customer]
      @groups = entity.grouped_property_schema.filter_map do |section|
        attributes = section[:attributes]
        attributes = BridgeParticipants.pickers(attributes, customer_id: customer.id) if entity.bridge_entity?
        fields = attributes.filter_map do |attribute|
          next unless EntityAttributeAudience.editable_by?(attribute, "admin")
          next if %w[Calculated Computed].include?(attribute["type"])
          next if attribute["type"] == Entity::ENTITY_REFERENCE_TYPE && !association_target?(attribute)
          next if attribute["storage"] == "computed" || attribute["readonly"] == true
          next if internal.include?(attribute["name_slug"])

          field = describe(attribute)
          if supported?(attribute, field)
            field
          else
            blockers << field
            nil
          end
        end
        next if fields.empty?

        group = section[:group]
        Group.new(key: group && group["id"], label: group && group["name"], fields: fields)
      end
    end

    def describe(attribute)
      validators = Array(attribute["validators"]).select { |validator| validator.is_a?(Hash) }
      applies = EntityAttributeAudience.applying_audiences(attribute).include?("admin")
      html_type = attribute["html_type"].presence || "text"
      options = attribute.dig("config", "options")
      if Entities::ReferenceLabels.reference?(attribute)
        source = reference_source(attribute)
        reference = Reference.new(entity: (source.target if source.usable?), label_field: attribute.dig("config", "label_field").to_s)
      end
      Field.new(
        slug: attribute["name_slug"], label: attribute["display_label"].presence || attribute["name"],
        help_text: attribute["description"], html_type: html_type,
        required: applies && validators.any? { |validator| validator["type"] == "presence" },
        options: reference ? reference_source(attribute).options : (options.is_a?(Array) ? options.filter_map { |option| option_pair(option) } : []),
        constraints: constraints_for(html_type, applies ? validators : []),
        full_width: %w[textarea radio multi-select].include?(html_type), invalid_literal: false,
        reference: reference
      )
    end

    def supported?(attribute, field)
      return false unless HTML_TYPES.include?(field.html_type)

      # A checkbox without options reads as a boolean here, so a reference
      # must be a select, radio or multi-select.
      return CHOICE_TYPES.include?(field.html_type) && reference_source(attribute).usable? if field.reference

      config = attribute["config"] || {}
      return false if config["entity_id"].present? || config["options_entity_name"].present?
      return false if config["options_source"].present? && !%w[static manual].include?(config["options_source"])
      return false if config["source"].present? && !%w[static manual constant].include?(config["source"])
      return false if attribute["dynamic_options"].present?
      return false if BOOLEAN_TYPES.include?(field.html_type) && config["options"].present?
      return true unless CHOICE_TYPES.include?(field.html_type)
      return false unless config["options"].is_a?(Array) && config["options"].all? { |option| option_pair(option) }

      # A single-choice default cannot arbitrarily select one of several flags.
      field.html_type == "multi-select" || entity.default_properties_json.key?(field.slug) ||
        default_options(attribute).size <= 1
    end

    def association_target?(attribute)
      links.any? && !links.key?(attribute["name_slug"].to_s) && Entities::ReferenceLabels.reference?(attribute)
    end

    def reference_source(attribute)
      (@reference_sources ||= {})[attribute["name_slug"]] ||= ReferenceOptions.new(
        entity_id: attribute.dig("config", "entity_id"), label_field: attribute.dig("config", "label_field"),
        customer_id: @customer.id, audience: EntityAttributeAudience::ADMIN
      )
    end

    def option_pair(option)
      if option.is_a?(Hash)
        return unless scalar?(option["value"])

        [option["label"].to_s, option["value"].to_s]
      elsif scalar?(option)
        [option.to_s, option.to_s]
      end
    end

    def constraints_for(html_type, validators)
      constraints = {}
      if html_type == "number"
        constraints[:step] = validators.any? { |validator| validator["type"] == "numericality_integer" } ? 1 : "any"
      end
      validators.each do |validator|
        config = validator["config"] || {}
        type = validator["type"]
        if html_type == "number" && %w[greater_than_or_equal_to less_than_or_equal_to].include?(type)
          value = config.fetch("value", 0)
          constraints[type == "greater_than_or_equal_to" ? :min : :max] = value if number?(value)
        elsif %w[text search tel url email textarea].include?(html_type)
          case type
          when "length_minimum" then constraints[:minlength] = config.fetch("value", 1).to_i
          when "length_maximum" then constraints[:maxlength] = config.fetch("value", 255).to_i
          when "length_in_range"
            constraints[:minlength] = config.fetch("min", 1).to_i
            constraints[:maxlength] = config.fetch("max", 255).to_i
          end
        end
      end
      constraints
    end

    def add_readiness_errors
      if blockers.any?
        add_errors!("base" => [I18n.t("#{ERROR_SCOPE}.unsupported_fields", fields: blockers.map(&:label).join(", "))])
      elsif (writable_slugs - links.keys).empty?
        add_errors!("base" => [I18n.t("#{ERROR_SCOPE}.no_fields")])
      end
    end

    def build_input(params)
      unless params.nil? || params.is_a?(Hash) || params.is_a?(ActionController::Parameters)
        add_error("base", "invalid_shape")
        return
      end

      defaults = entry ? stored_values : entity.default_properties_json
      readiness_errors = errors.deep_dup
      attributes = entity.input_fields.index_by { |attribute| attribute["name_slug"] }
      groups.flat_map(&:fields).each do |field|
        slug = field.slug
        if params && (params.key?(slug) || params.key?(slug.to_sym))
          raw = params.key?(slug) ? params[slug] : params[slug.to_sym]
        elsif defaults.key?(slug)
          raw = defaults[slug]
        else
          next if entry || !CHOICE_TYPES.include?(field.html_type)

          selected = default_options(attributes.fetch(slug))
          next if selected.empty?

          raw = field.html_type == "multi-select" ? selected : selected.first
        end
        normalize_input(field, raw)
      end
      filtered_input.merge!(links)
      # Opening an edit form shows the record as stored; its values are only
      # judged once the admin submits them.
      @errors = readiness_errors if entry && params.nil?
    end

    def stored_values
      data = entry.data_json
      data.is_a?(Hash) ? data.compact : {}
    end

    def default_options(attribute) = AttributeDefaults.flagged(attribute)

    def normalize_input(field, raw)
      multiple = field.html_type == "multi-select"
      valid_shape = multiple ? raw.is_a?(Array) && raw.all? { |value| scalar?(value) } : scalar?(raw)
      unless valid_shape
        add_error(field.slug, "invalid_shape")
        return
      end

      values[field.slug] = multiple ? raw.reject { |value| empty_literal?(value) } : raw
      normalized = values[field.slug]
      if CHOICE_TYPES.include?(field.html_type)
        normalized = multiple ? normalized.map(&:to_s) : normalized.nil? ? nil : normalized.to_s
        choices = field.options.map(&:last)
        attempted = multiple ? normalized : [normalized]
        if !field.reference && attempted.any? { |value| !empty_literal?(value) && !choices.include?(value) }
          add_error(field.slug, "invalid_choice")
        end
      elsif BOOLEAN_TYPES.include?(field.html_type)
        normalized = boolean_literal(raw)
        values[field.slug] = normalized unless normalized.nil?
        add_error(field.slug, "invalid_boolean") if normalized.nil?
      elsif field.html_type == "number"
        field.invalid_literal = !raw.nil? && raw != "" && (!number?(raw) || !raw.to_s.match?(HTML_NUMBER_LITERAL))
        add_error(field.slug, "invalid_number") if !empty_literal?(raw) && !number?(raw)
      elsif field.html_type == "date"
        field.invalid_literal = !raw.nil? && raw != "" && !date?(raw)
        add_error(field.slug, "invalid_date") if !empty_literal?(raw) && !date?(raw)
      elsif field.html_type == "datetime-local"
        field.invalid_literal = !raw.nil? && raw != "" && !datetime?(raw)
        add_error(field.slug, "invalid_datetime") if !empty_literal?(raw) && !datetime?(raw)
      end
      filtered_input[field.slug] = normalized
    end

    def scalar?(value)
      value.nil? || value.is_a?(String) || value.is_a?(TrueClass) || value.is_a?(FalseClass) ||
        value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
    end

    def empty_literal?(value) = value.nil? || (value.is_a?(String) && value.blank?)

    def boolean_literal(value)
      case value
      when true, 1, "1", "true", "on" then "1"
      when false, 0, "0", "false", "off" then "0"
      end
    end

    def number?(value)
      value.to_s.match?(NUMBER_LITERAL) && Float(value.to_s, exception: false)&.finite? == true
    end

    def date?(value)
      value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(value).year.positive?
    rescue Date::Error
      false
    end

    # The naive wall-clock literal a datetime-local input posts (seconds optional).
    def datetime?(value)
      return false unless value.is_a?(String)

      match = value.match(/\A(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,3})?)?\z/)
      match.present? && date?(match[1]) && match[2].to_i < 24 && match[3].to_i < 60 && match[4].to_i < 60
    end

    def add_error(slug, key)
      add_errors!(slug => [I18n.t("#{ERROR_SCOPE}.errors.#{key}")])
    end
  end
end
