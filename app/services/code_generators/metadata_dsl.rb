# frozen_string_literal: true

module CodeGenerators
  class MetadataDSL
    FIELDS = %i[name description category version].freeze

    def initialize
      @data = {}
    end

    FIELDS.each do |field|
      define_method(field) { |val| @data[field] = val }
    end

    def presentation(icon: nil, color: nil, single_use: nil, privileged: nil, **unknown)
      raise ArgumentError, "unknown presentation option #{unknown.keys.inspect}" if unknown.any?

      @data[:presentation] = {
        icon: icon,
        color: color,
        single_use: single_use,
        privileged: privileged
      }.compact
    end

    def error_strategy_default(value)
      @data[:error_strategy_default] = value
    end

    # Return a frozen copy of the collected metadata. We `dup` first so a
    # second call from a DSL field method after `to_h` (rare but possible
    # during test setup) does not raise FrozenError on @data.
    def to_h
      @data.dup.freeze
    end

    def self.bump_patch(version_string)
      parts = version_string.to_s.split(".")
      parts = ["1", "0", "0"] if parts.size < 3
      parts[2] = (parts[2].to_i + 1).to_s
      parts.join(".")
    end
  end
end
