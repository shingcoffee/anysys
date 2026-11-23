# frozen_string_literal: true

module EntityDefinitions
  module Api
    # Registry-backed enum values and English descriptions for the public
    # entity vocabulary. Descriptions are model-facing API documentation and
    # stay English-only by design.
    class Vocabulary
      ATTRIBUTE_KINDS = %w[input calculated computed].freeze
      OPTION_SOURCES = %w[static constant entity_entries].freeze
      AGGREGATE_DIRECTIONS = %w[source target].freeze

      HTML_TYPE_DESCRIPTIONS = {
        "text" => "Single-line plain text input for short free-form values.",
        "textarea" => "Multi-line text area for longer free-form prose.",
        "search" => "Search-styled text input used to filter or query.",
        "password" => "Masked text input for secrets that should not be shown.",
        "hidden" => "Hidden input stored with the record but not shown on the form.",
        "select" => "Dropdown that picks one value from a choice list.",
        "radio" => "Radio buttons that pick one value from a choice list.",
        "checkbox" => "Checkboxes that pick one or more values from a choice list.",
        "number" => "Numeric input for quantities, amounts, and other numbers.",
        "range" => "Slider control for a numeric value within a bounded range.",
        "date" => "Date picker for a calendar day.",
        "time" => "Time picker for a clock time of day.",
        "datetime-local" => "Combined date and time picker for a local timestamp.",
        "month" => "Month picker for a year-month value.",
        "week" => "Week picker for a year-week value.",
        "email" => "Email input that expects an email address.",
        "tel" => "Telephone input that expects a phone number.",
        "url" => "URL input that expects an http or https link.",
        "file" => "File upload control for arbitrary documents.",
        "image" => "Image upload control restricted to picture files.",
        "color" => "Color picker for a hex color value."
      }.freeze

      ATTRIBUTE_KIND_DESCRIPTIONS = {
        "input" => "A stored field the user fills in on the form.",
        "calculated" => "A derived field computed from a formula over sibling attributes.",
        "computed" => "A derived aggregate of a related entity through the association bridge."
      }.freeze

      RULE_MEANINGS = {
        "presence" => "Requires the field to have a value",
        "greater_than_or_equal_to" => "Requires the number to be at least the given bound",
        "less_than_or_equal_to" => "Requires the number to be at most the given bound",
        "equal_to" => "Requires the number to equal the given bound",
        "not_equal_to" => "Requires the number to differ from the given bound",
        "greater_than" => "Requires the number to be greater than the given bound",
        "less_than" => "Requires the number to be less than the given bound",
        "format_email" => "Requires the value to be a valid email address",
        "format_url" => "Requires the value to be a valid http or https URL",
        "format_phone" => "Requires the value to look like a phone number",
        "format_custom" => "Requires the value to match a regular expression",
        "length_minimum" => "Requires the text to be at least the given length",
        "length_maximum" => "Requires the text to be at most the given length",
        "length_in_range" => "Requires the text length to fall between the given bounds",
        "numericality" => "Requires the value to be numeric",
        "numericality_integer" => "Requires the value to be an integer",
        "inclusion" => "Requires the value to be one of the given list",
        "exclusion" => "Requires the value not to be one of the given list",
        "acceptance" => "Requires the value to be accepted (checked)"
      }.freeze

      RULE_VALUE_FIELDS = {
        "single_value" => "`value`",
        "range" => "`min` and `max`",
        "pattern" => "`pattern`",
        "list" => "`values`"
      }.freeze

      GROUP_ICON_DESCRIPTIONS = {
        "folder" => "Folder icon for a generic section of fields.",
        "user" => "User icon for identity or people fields.",
        "briefcase" => "Briefcase icon for work or organization fields.",
        "map-pin" => "Map-pin icon for address or location fields.",
        "mail" => "Mail icon for email or correspondence fields.",
        "phone" => "Phone icon for telephone or contact fields.",
        "calendar" => "Calendar icon for date or schedule fields.",
        "tag" => "Tag icon for labels, categories, or status fields.",
        "settings" => "Settings icon for configuration or preference fields.",
        "bell" => "Bell icon for alerts or notification fields.",
        "link" => "Link icon for URL or reference fields.",
        "file" => "File icon for document or attachment fields."
      }.freeze

      GROUP_COLOR_DESCRIPTIONS = {
        "slate" => "Neutral slate token for a subdued group header.",
        "indigo" => "Indigo token for a primary or default group header.",
        "sky" => "Sky-blue token for a cool group header.",
        "teal" => "Teal token for a calm group header.",
        "emerald" => "Emerald token for a success-toned group header.",
        "amber" => "Amber token for a warning-toned group header.",
        "rose" => "Rose token for an attention-toned group header.",
        "violet" => "Violet token for an accent group header."
      }.freeze

      OPTION_SOURCE_DESCRIPTIONS = {
        "static" => "A fixed list of values authored on the attribute.",
        "constant" => "A named customer or shared constant whose options fill the list.",
        "entity_entries" => "A live list drawn from another entity's entries."
      }.freeze

      AGGREGATE_FUNCTION_DESCRIPTIONS = {
        "avg" => "Average of the numeric source attribute across related rows.",
        "sum" => "Sum of the numeric source attribute across related rows.",
        "count" => "Count of related rows; the source attribute is optional.",
        "min" => "Minimum of the numeric source attribute across related rows.",
        "max" => "Maximum of the numeric source attribute across related rows."
      }.freeze

      FILTER_OPERATOR_DESCRIPTIONS = {
        "=" => "Keep related rows whose filter attribute equals the given value.",
        "!=" => "Keep related rows whose filter attribute differs from the given value.",
        ">" => "Keep related rows whose filter attribute is greater than the given value.",
        ">=" => "Keep related rows whose filter attribute is at least the given value.",
        "<" => "Keep related rows whose filter attribute is less than the given value.",
        "<=" => "Keep related rows whose filter attribute is at most the given value."
      }.freeze

      AGGREGATE_DIRECTION_DESCRIPTIONS = {
        "source" => "Aggregate through this entity's association to the related entity.",
        "target" => "Aggregate through the related entity's association that targets this entity."
      }.freeze

      class << self
        def resolve(name, context = nil)
          key = name.to_s
          return Entities::ComputedCompiler::MAX_PRECISION if key == "aggregate_max_precision"

          values = values_for(key, context)
          raise ArgumentError, "unknown vocabulary #{name}" if values.nil?

          { values: values, descriptions: descriptions_for(key, context) }
        end

        def descriptions_for(name, context = nil)
          key = name.to_s
          return {} if key == "aggregate_max_precision"

          values = values_for(key, context)
          raise ArgumentError, "unknown vocabulary #{name}" if values.nil?

          values.index_with { |value| description_for(key, value, context) }
        end

        def rule_config_kind(type)
          ValidatorRegistry::VALIDATOR_CONFIG_TYPES[type.to_s]
        end

        def html_type_values
          HtmlTypeOptions::GROUPED_HTML_TYPES.values.flatten(1).map(&:last)
        end

        def rule_type_values
          ValidatorRegistry::VALIDATOR_LABELS.keys
        end

        def rule_types_for(kind)
          ValidatorRegistry::VALIDATOR_CONFIG_TYPES.select { |_type, config_kind| config_kind == kind }.keys
        end

        private

        def values_for(name, context)
          case name
          when "html_types" then html_type_values
          when "selection_html_types" then HtmlTypeOptions::SELECTION_TYPES
          when "attribute_kinds" then ATTRIBUTE_KINDS
          when "rule_types" then rule_type_values
          when "rule_types_single_value" then rule_types_for("single_value")
          when "rule_types_range" then rule_types_for("range")
          when "rule_types_pattern" then rule_types_for("pattern")
          when "rule_types_list" then rule_types_for("list")
          when "group_icons" then EntityAttributeGroupOptions::ICONS.keys
          when "group_colors" then EntityAttributeGroupOptions::COLORS
          when "option_sources" then OPTION_SOURCES
          when "aggregate_functions" then Entities::ComputedCompiler::FUNCTIONS
          when "filter_operators" then Entities::ComputedCompiler::FILTER_OPS
          when "aggregate_directions" then AGGREGATE_DIRECTIONS
          when "extendable_models" then extendable_model_values(context)
          end
        end

        def description_for(name, value, context)
          case name
          when "html_types", "selection_html_types" then HTML_TYPE_DESCRIPTIONS[value]
          when "attribute_kinds" then ATTRIBUTE_KIND_DESCRIPTIONS[value]
          when "rule_types", "rule_types_single_value", "rule_types_range",
               "rule_types_pattern", "rule_types_list"
            rule_description(value)
          when "group_icons" then GROUP_ICON_DESCRIPTIONS[value]
          when "group_colors" then GROUP_COLOR_DESCRIPTIONS[value]
          when "option_sources" then OPTION_SOURCE_DESCRIPTIONS[value]
          when "aggregate_functions" then AGGREGATE_FUNCTION_DESCRIPTIONS[value]
          when "filter_operators" then FILTER_OPERATOR_DESCRIPTIONS[value]
          when "aggregate_directions" then AGGREGATE_DIRECTION_DESCRIPTIONS[value]
          when "extendable_models" then extendable_model_description(value, context)
          end
        end

        def rule_description(type)
          meaning = RULE_MEANINGS[type]
          return unless meaning

          fields = RULE_VALUE_FIELDS[rule_config_kind(type)] || "no value fields"
          allowed = allowed_html_types_for(type)
          where = allowed.sort == html_type_values.sort ? "every html_type" : join_list(allowed)
          "#{meaning}, takes #{fields}, and is allowed on #{where}."
        end

        # Only controls an attribute can be authored with: the validator
        # registry also lists controls the entity editor never offers.
        def allowed_html_types_for(type)
          html_type_values.select do |html_type|
            Array(ValidatorRegistry::HTML_TYPE_VALIDATORS[html_type]).include?(type)
          end
        end

        def join_list(values)
          return "(none)" if values.empty?
          return values.first if values.size == 1
          return values.join(" and ") if values.size == 2

          "#{values[0..-2].join(", ")}, and #{values.last}"
        end

        def extendable_model_values(context)
          extendable_models(context).map { |model| model[:class_name] }
        end

        def extendable_model_description(class_name, context)
          model = extendable_models(context).find { |row| row[:class_name] == class_name }
          return unless model

          "#{model[:label]} from the #{model[:module_key]} module."
        end

        def extendable_models(context)
          customer_id = context&.customer&.id
          return [] if customer_id.blank?

          ExtendableModelRegistry.for_customer(customer_id)
        end
      end
    end
  end
end
