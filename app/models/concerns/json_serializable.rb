# frozen_string_literal: true

# Provides JSON serialization helpers for ActiveRecord attributes.
#
# This concern adds memoized JSON parsing with automatic cache invalidation.
#
# Usage:
#   class MyModel < ApplicationRecord
#     include JsonSerializable
#     json_attribute :configuration
#     json_attribute :property_schema, default: {}
#   end
#
module JsonSerializable
  extend ActiveSupport::Concern

  included do
    # Nothing needed here — see reload override below.
  end

  # Override reload to clear memoized JSON attribute caches so that a
  # subsequent call to e.g. `entity_json` re-parses from the freshly
  # loaded column value instead of returning stale in-memory data.
  def reload(*)
    result = super
    self.class.json_attribute_names.each do |attr|
      %W[@#{attr}_json @#{attr}_json_raw].each do |ivar|
        remove_instance_variable(ivar) if instance_variable_defined?(ivar)
      end
    end
    result
  end

  class_methods do
    # Track all registered json_attribute names for cache invalidation
    def json_attribute_names
      @json_attribute_names ||= []
    end

    # Define a JSON-serialized attribute with automatic parsing and memoization
    #
    # @param attribute [Symbol] The attribute name
    # @param default [Object] Default value when parsing fails or attribute is blank
    def json_attribute(attribute, default: nil)
      json_attribute_names << attribute

      # Getter method - parses JSON and memoizes result. The memo is keyed by the
      # current raw value so a direct `attribute=` write (e.g. mass-assignment on
      # a virtual attribute) invalidates it instead of returning a stale parse.
      define_method("#{attribute}_json") do
        ivar     = "@#{attribute}_json"
        raw_ivar = "@#{attribute}_json_raw"
        value = send(attribute)
        if instance_variable_defined?(ivar) && instance_variable_get(raw_ivar) == value
          return instance_variable_get(ivar)
        end

        instance_variable_set(raw_ivar, value)
        parsed =
          if value.is_a?(String)
            value.present? ? JSON.parse(value) : (default.is_a?(Array) || default.is_a?(Hash) ? default.deep_dup : default)
          elsif value.nil?
            default.is_a?(Array) || default.is_a?(Hash) ? default.deep_dup : default
          else
            value
          end
        instance_variable_set(ivar, parsed)
      rescue JSON::ParserError
        instance_variable_set(ivar, default.is_a?(Array) || default.is_a?(Hash) ? default.deep_dup : default)
      end

      # Setter method - converts to JSON and clears memoized value
      define_method("#{attribute}_json=") do |value|
        send("#{attribute}=", value.to_json)
        remove_instance_variable("@#{attribute}_json") if instance_variable_defined?("@#{attribute}_json")
      end
    end
  end
end
