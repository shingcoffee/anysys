# frozen_string_literal: true

# ContractGenerator
#
# Generates code that dynamically configures EntityEntryContract for an
# Entity using Ruby metaprogramming (class_eval + property_accessor).
#
# No new class is defined -- EntityEntryContract itself is extended with
# properties and validations derived from the entity's property_schema.
#
# @example
#   ContractGenerator.new(entity).generate
#   # => "# frozen_string_literal: true\n\nEntityEntryContract.class_eval do\n  ..."
#
class ContractGenerator
  include ValidatorRegistry

  attr_reader :entity, :attributes

  def initialize(entity, writable_slugs: nil)
    @entity = entity
    @attributes = entity.property_schema_json || []
    @writable_slugs = writable_slugs&.map(&:to_s)
  end

  def generate
    return nil if entity.name.blank? || attributes.empty?

    [header, class_eval_block].join("\n")
  end

  private

  def header
    <<~RUBY.chomp
      # frozen_string_literal: true
      #
      # EntityEntryContract configuration for: #{entity.name}
      # Dynamically extends EntityEntryContract with properties and validations
    RUBY
  end

  def class_eval_block
    <<~RUBY

      EntityEntryContract.class_eval do
      #{property_declarations.indent(2)}
      end
    RUBY
  end

  def property_declarations
    attributes.map { |attr| build_property_accessor(attr) }.join("\n")
  end

  def build_property_accessor(attr)
    slug = attr["name_slug"]
    validates_hash = build_validates_hash(attr)

    parts = ["property_accessor :#{slug}"]
    parts << "validates: { #{validates_hash} }" if validates_hash
    EntityEntryContract.schema_property_options(attr, writable_slugs: @writable_slugs).each do |key, value|
      parts << "#{key}: #{value.inspect}"
    end
    parts.join(", ")
  end

  def build_validates_hash(attr)
    raw_validators = attr["validators"] || []
    return nil if raw_validators.empty?

    options = raw_validators
      .filter_map { |v| build_validator_option(v) }
      .then { |opts| merge_options(opts) }
      .map { |opt| allow_blank_source(opt) }

    return nil if options.empty?

    audiences = EntityAttributeAudience.applying_audiences(attr)
    return nil if audiences.empty?

    options += [EntityAttributeAudience.contract_guard_source(audiences)] unless
      EntityAttributeAudience.every_audience?(audiences)

    options.join(", ")
  end

  def build_validator_option(validator)
    # Handle both old format (string) and new format (hash with type and config)
    if validator.is_a?(String)
      # Old format: "presence", "length_minimum", etc.
      validator_key = validator.to_sym
      VALIDATORS_CODE[validator_key]&.call
    elsif validator.is_a?(Hash)
      # New format: {"type": "presence"} or {"type": "length_in_range", "config": {"min": 1, "max": 20}}
      validator_type = validator["type"]&.to_sym
      config = validator["config"]

      return nil unless validator_type && VALIDATORS_CODE[validator_type]

      # Handle validators that need configuration parameters
      case validator_type
      when :length_in_range
        if config && config["min"] && config["max"]
          range = config["min"]..config["max"]
          VALIDATORS_CODE[validator_type].call(range)
        else
          VALIDATORS_CODE[validator_type].call
        end
      when :greater_than_or_equal_to, :less_than_or_equal_to, :equal_to, :not_equal_to, :greater_than, :less_than
        if config && config["value"]
          VALIDATORS_CODE[validator_type].call(config["value"])
        else
          VALIDATORS_CODE[validator_type].call
        end
      when :length_minimum, :length_maximum
        if config && config["value"]
          VALIDATORS_CODE[validator_type].call(config["value"])
        else
          VALIDATORS_CODE[validator_type].call
        end
      when :format_custom
        if config && config["pattern"]
          # Embed the pattern as a String literal (`String#inspect`) and let
          # Regexp.new compile it at load time. Without this a pattern
          # containing `/` would terminate the regex literal early, and a
          # pattern containing `#{...}` would inject Ruby into the
          # generated contract source.
          "format: { with: Regexp.new(#{config["pattern"].to_s.inspect}) }"
        else
          VALIDATORS_CODE[validator_type].call
        end
      when :inclusion, :exclusion
        if config && config["values"]
          values_array = config["values"].is_a?(Array) ? config["values"] : config["values"].split("\n").map(&:strip)
          "#{validator_type}: { in: #{values_array.inspect} }"
        else
          VALIDATORS_CODE[validator_type]&.call
        end
      else
        VALIDATORS_CODE[validator_type].call
      end
    else
      nil
    end
  end

  # Source twin of EntityEntryContract.allow_blank_values.
  def allow_blank_source(option)
    return option if REQUIRING_VALIDATIONS.include?(option[/\A\w+/].to_sym)
    return option.sub(/: true\z/, ": { allow_blank: true }") if option.end_with?(": true")

    option.sub(/\s*\}\z/, ", allow_blank: true }")
  end

  def merge_options(options)
    grouped = options.group_by { |opt| opt[/\A\w+/] }

    grouped.flat_map do |type, opts|
      next opts if opts.size == 1 || !MERGEABLE_VALIDATORS.include?(type)

      merge_hash_validator(type, opts)
    end
  end

  def merge_hash_validator(type, opts)
    merged = opts.each_with_object({}) do |opt, hash|
      next if opt == "#{type}: true"

      if opt =~ /\{\s*(.+)\s*\}/
        $1.split(",").each do |pair|
          key, value = pair.split(":").map(&:strip)
          hash[key] = value if key && value
        end
      end
    end

    return ["#{type}: true"] if merged.empty?

    inner = merged.map { |k, v| "#{k}: #{v}" }.join(", ")
    ["#{type}: { #{inner} }"]
  end
end
