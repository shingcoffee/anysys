# frozen_string_literal: true

# Shared validator definitions used across:
# - EntityEntryContract (runtime validation)
# - ContractGenerator (code generation)
# - ApplicationHelper / ValidatorDisplayHelper (display labels)
#
# Single source of truth for all validator metadata.
#
module ValidatorRegistry
  extend ActiveSupport::Concern

  # Validations that may reject a blank value; every other check also gets
  # allow_blank, so only presence makes a field required.
  REQUIRING_VALIDATIONS = %i[presence acceptance].freeze

  # User-friendly display labels for validators.
  #
  # This constant is evaluated once at class-load time, so worded labels
  # cannot bake in I18n.t (that would freeze under the boot-time locale).
  # Instead it maps each validator key to a STABLE symbol resolved at call
  # time by `validator_label` via config/locales/maint_core.*.yml
  # (`maint_core.validators.*`). Pure comparison operators (">=", "<", etc.)
  # are left as literal strings — they are notation, not translatable text.
  VALIDATOR_LABELS = {
    "presence" => :required,
    "greater_than_or_equal_to" => ">=",
    "less_than_or_equal_to" => "<=",
    "equal_to" => "==",
    "not_equal_to" => "!=",
    "greater_than" => ">",
    "less_than" => "<",
    "format_email" => :email,
    "format_url" => :url,
    "format_phone" => :phone,
    "format_custom" => :regex,
    "length_minimum" => :min_len,
    "length_maximum" => :max_len,
    "length_in_range" => :len_range,
    "numericality" => :numeric,
    "numericality_integer" => :integer,
    "inclusion" => :in_list,
    "exclusion" => :not_in,
    "acceptance" => :accepted
  }.freeze

  # Runtime validation rules: validator keys to Rails validation options
  VALIDATORS = {
    presence: -> { { presence: true } },

    # Comparison (numericality constraints)
    greater_than_or_equal_to: ->(v = 0) { { numericality: { greater_than_or_equal_to: v } } },
    less_than_or_equal_to:    ->(v = 0) { { numericality: { less_than_or_equal_to: v } } },
    equal_to:                 ->(v = 0) { { numericality: { equal_to: v } } },
    not_equal_to:             ->(v = 0) { { numericality: { other_than: v } } },
    greater_than:             ->(v = 0) { { numericality: { greater_than: v } } },
    less_than:                ->(v = 0) { { numericality: { less_than: v } } },

    # Format
    format_email:  -> { { format: { with: URI::MailTo::EMAIL_REGEXP } } },
    format_url:    -> { { format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) } } },
    format_phone:  -> { { format: { with: /\A[\d\s\-\+\(\)]+\z/ } } },
    format_custom: -> { { format: { with: // } } },

    # Length
    length_minimum:  ->(v = 1)     { { length: { minimum: v } } },
    length_maximum:  ->(v = 255)   { { length: { maximum: v } } },
    length_in_range: ->(r = 1..255) { { length: { in: r } } },

    # Numeric
    numericality:         -> { { numericality: true } },
    numericality_integer: -> { { numericality: { only_integer: true } } },

    # Inclusion/Exclusion
    inclusion: ->(values = []) { { inclusion: { in: values } } },
    exclusion: ->(values = []) { { exclusion: { in: values } } },

    # Acceptance
    acceptance: -> { { acceptance: true } }
  }.freeze

  # Code-generation validation DSL: maps validator keys to string representations
  VALIDATORS_CODE = {
    presence: -> { "presence: true" },

    greater_than_or_equal_to: ->(v = 0) { "numericality: { greater_than_or_equal_to: #{v} }" },
    less_than_or_equal_to:    ->(v = 0) { "numericality: { less_than_or_equal_to: #{v} }" },
    equal_to:                 ->(v = 0) { "numericality: { equal_to: #{v} }" },
    not_equal_to:             ->(v = 0) { "numericality: { other_than: #{v} }" },
    greater_than:             ->(v = 0) { "numericality: { greater_than: #{v} }" },
    less_than:                ->(v = 0) { "numericality: { less_than: #{v} }" },

    format_email:  -> { "format: { with: URI::MailTo::EMAIL_REGEXP }" },
    format_url:    -> { "format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }" },
    format_phone:  -> { 'format: { with: /\A[\d\s\-\+\(\)]+\z/ }' },
    format_custom: -> { "format: { with: // }" },

    length_minimum:  ->(v = 1)     { "length: { minimum: #{v} }" },
    length_maximum:  ->(v = 255)   { "length: { maximum: #{v} }" },
    length_in_range: ->(r = 1..255) { "length: { in: #{r} }" },

    numericality:         -> { "numericality: true" },
    numericality_integer: -> { "numericality: { only_integer: true }" },

    inclusion: ->(values = []) { "inclusion: { in: #{values.inspect} }" },
    exclusion: ->(values = []) { "exclusion: { in: #{values.inspect} }" },

    acceptance: -> { "acceptance: true" }
  }.freeze

  # Validators whose options can be merged (e.g., multiple numericality constraints)
  MERGEABLE_VALIDATORS = %w[numericality length].freeze

  # Validator configuration types for the UI
  VALIDATOR_CONFIG_TYPES = {
    "greater_than_or_equal_to" => "single_value",
    "less_than_or_equal_to" => "single_value",
    "equal_to" => "single_value",
    "not_equal_to" => "single_value",
    "greater_than" => "single_value",
    "less_than" => "single_value",
    "length_minimum" => "single_value",
    "length_maximum" => "single_value",
    "length_in_range" => "range",
    "format_custom" => "pattern",
    "inclusion" => "list",
    "exclusion" => "list"
  }.freeze

  # Maps each HTML input type to its semantically valid validators
  HTML_TYPE_VALIDATORS = {
    # Text group
    "text"     => %w[presence length_minimum length_maximum length_in_range format_custom inclusion exclusion],
    "textarea" => %w[presence length_minimum length_maximum length_in_range format_custom],
    "search"   => %w[presence length_minimum length_maximum length_in_range format_custom],
    "password" => %w[presence length_minimum length_maximum length_in_range format_custom],
    "hidden"   => %w[presence format_custom inclusion exclusion],

    # Selection group
    "select"       => %w[presence inclusion exclusion],
    "multi-select" => %w[presence inclusion exclusion length_minimum length_maximum],
    "radio"        => %w[presence inclusion exclusion],
    "checkbox"     => %w[presence acceptance inclusion exclusion],
    "switch"       => %w[presence acceptance],

    # Numeric group
    "number"   => %w[presence numericality numericality_integer greater_than_or_equal_to less_than_or_equal_to equal_to not_equal_to greater_than less_than inclusion exclusion],
    "currency" => %w[presence numericality greater_than_or_equal_to less_than_or_equal_to greater_than less_than],
    "range"    => %w[presence numericality greater_than_or_equal_to less_than_or_equal_to],
    "rating"   => %w[presence numericality numericality_integer greater_than_or_equal_to less_than_or_equal_to],

    # Date & Time group
    "date"           => %w[presence],
    "time"           => %w[presence],
    "datetime-local" => %w[presence],
    "month"          => %w[presence],
    "week"           => %w[presence],

    # Contact group
    "email" => %w[presence format_email length_minimum length_maximum length_in_range format_custom],
    "tel"   => %w[presence format_phone length_minimum length_maximum format_custom],
    "url"   => %w[presence format_url length_minimum length_maximum length_in_range format_custom],

    # Rich Content group
    "rich-text" => %w[presence length_minimum length_maximum length_in_range],
    "signature" => %w[presence],

    # Media & File group
    "file"  => %w[presence],
    "image" => %w[presence],
    "color" => %w[presence format_custom inclusion exclusion]
  }.freeze

  class_methods do
    delegate :validator_label, :build_validator_display_label, to: ValidatorRegistry
  end

  # Module-level methods callable as ValidatorRegistry.validator_label(...)
  class << self
    def validator_label(validator)
      raw = VALIDATOR_LABELS[validator.to_s]
      return validator.to_s if raw.nil?

      raw.is_a?(Symbol) ? I18n.t("maint_core.validators.#{raw}") : raw
    end

    # JS validator types (presence, format_email, …) → translated short labels
    # for the entity-form Stimulus overlay. Call-time so locale is not frozen.
    def labels_for_js
      VALIDATOR_LABELS.keys.index_with { |k| validator_label(k) }
    end

    def build_validator_display_label(validator_type, config)
      base_label = validator_label(validator_type)
      return base_label unless config

      case validator_type.to_s
      when "length_in_range"
        config["min"] && config["max"] ? "#{base_label} (#{config["min"]}-#{config["max"]})" : base_label
      when "greater_than_or_equal_to", "less_than_or_equal_to", "equal_to", "not_equal_to", "greater_than", "less_than",
           "length_minimum", "length_maximum"
        config["value"] ? "#{base_label} #{config["value"]}" : base_label
      when "format_custom"
        config["pattern"] ? "#{base_label} (#{config["pattern"]})" : base_label
      when "inclusion", "exclusion"
        if config["values"]
          values_count = config["values"].is_a?(Array) ? config["values"].length : config["values"].split("\n").length
          "#{base_label} (#{values_count} items)"
        else
          base_label
        end
      else
        base_label
      end
    end
  end
end
