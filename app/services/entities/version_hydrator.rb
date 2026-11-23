# frozen_string_literal: true

module Entities
  # Applies an entity-version definition snapshot onto an in-memory Entity
  # without saving. Used so page generation can bind fields to a historical
  # version rather than the live head.
  class VersionHydrator
    def self.snapshot_hash(version)
      raw = version&.payload
      return {} if raw.blank?

      parsed = raw.is_a?(String) ? JSON.parse(raw) : raw
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def self.apply!(entity, version)
      snap = snapshot_hash(version)
      entity.property_schema_json    = snap["property_schema"]    || []
      entity.associations_json       = snap["associations"]       || []
      entity.attribute_groups_json   = snap["attribute_groups"]   || []
      entity.default_properties_json = snap["default_properties"] || {}
      entity.icon                    = snap.fetch("icon", entity.icon)
      entity.color                   = snap.fetch("color", entity.color)
      entity.description             = snap["description"] if snap.key?("description")
      entity
    end

    def self.hydrate(entity, version)
      copy = entity.class.find(entity.id)
      apply!(copy, version)
    end
  end
end
