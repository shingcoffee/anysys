# frozen_string_literal: true

# Sluggable
#
# Provides automatic slug generation from a source attribute using Rails' parameterize method.
# Follows Rails 8 conventions for URL-friendly identifiers.
#
# Usage:
#   class Entity < ApplicationRecord
#     include Sluggable
#     sluggable source: :name, slug_column: :name_slug
#   end
#
#   entity = Entity.new(name: "My Entity Name")
#   entity.valid?
#   entity.name_slug # => "my_entity_name"
#
# Options:
#   source:      The attribute to generate the slug from (default: :name)
#   slug_column: The column to store the slug in (default: :slug)
#   separator:   The separator character (default: "_")
#   scope:       Uniqueness scope for validation (default: nil)
#   uniqueness_conditions: extra uniqueness relation (e.g. active-only)
#
module Sluggable
  extend ActiveSupport::Concern

  class_methods do
    # Configure slug generation for the model
    #
    # @param source [Symbol] the attribute to generate slug from
    # @param slug_column [Symbol] the column to store the slug
    # @param separator [String] separator for words (default: "_")
    # @param scope [Symbol, Array<Symbol>] scope for uniqueness validation
    # @param uniqueness_conditions [Proc, nil] extra uniqueness relation
    def sluggable(source: :name, slug_column: :slug, separator: "_", scope: nil,
                  uniqueness_conditions: nil)
      # Store configuration
      class_attribute :slug_source, default: source
      class_attribute :slug_column_name, default: slug_column
      class_attribute :slug_separator, default: separator
      class_attribute :slug_scope, default: scope

      # Add callback
      before_validation :generate_slug

      uniqueness = {}
      uniqueness[:scope] = scope if scope
      uniqueness[:conditions] = uniqueness_conditions if uniqueness_conditions
      validates slug_column, uniqueness: uniqueness.presence || true, allow_blank: true

      # Define instance methods
      include InstanceMethods
    end

    # Generate a slug from a string using Rails conventions
    #
    # @param value [String] the string to slugify
    # @param separator [String] separator character (default: "_")
    # @return [String] the slugified string
    def slugify(value, separator: "_")
      return nil if value.blank?

      value.to_s
           .strip
           .parameterize(separator: separator)
    end
  end

  module InstanceMethods
    private

    # Generate slug from source attribute
    def generate_slug
      source_value = send(slug_source)
      return if source_value.blank?

      self[slug_column_name] = self.class.slugify(source_value, separator: slug_separator)
    end
  end
end
