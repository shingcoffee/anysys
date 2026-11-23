# frozen_string_literal: true

module FlowchartRuntime
  # Haversine distance for the geolocation_lookup step. The platform does not
  # configure Google Maps or Mapbox credentials, so this action does not call
  # those vendors.
  module Geolocation
    class Error < StandardError; end

    EARTH_KM = 6371.0
    LAT_KEYS = %w[lat latitude].freeze
    LNG_KEYS = %w[lng lon longitude].freeze

    module_function

    def lookup(ctx, source:, other:)
      src = coordinate_hash(source)
      dst = coordinate_hash(other)
      if [src[:lat], src[:lng], dst[:lat], dst[:lng]].any? { |value| value.nil? }
        return Step.fail(ctx, :"geolocation_lookup.invalid_coordinates")
      end

      distance(src, dst)
    end

    def distance(src, dst)
      lat1 = src[:lat].to_f * Math::PI / 180
      lng1 = src[:lng].to_f * Math::PI / 180
      lat2 = dst[:lat].to_f * Math::PI / 180
      lng2 = dst[:lng].to_f * Math::PI / 180
      dlat = lat2 - lat1
      dlng = lng2 - lng1
      arc = Math.sin(dlat / 2)**2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dlng / 2)**2
      km = EARTH_KM * 2 * Math.atan2(Math.sqrt(arc), Math.sqrt(1 - arc))
      { km: km.round(4), miles: (km * 0.621371).round(4) }
    end

    def coordinate_hash(value)
      if value.is_a?(EntityEntry)
        return {
          lat: numeric(value.flowchart_value("lat") || value.flowchart_value("latitude")),
          lng: numeric(value.flowchart_value("lng") || value.flowchart_value("lon") || value.flowchart_value("longitude"))
        }
      end
      return {} unless value.is_a?(Hash)

      {
        lat: numeric(lookup_key(value, LAT_KEYS)),
        lng: numeric(lookup_key(value, LNG_KEYS))
      }
    end

    def lookup_key(hash, keys)
      keys.each do |key|
        return hash[key] if hash.key?(key)
        return hash[key.to_sym] if hash.key?(key.to_sym)
      end
      nil
    end

    def numeric(value)
      return value if value.is_a?(Numeric)
      return nil if value.nil?

      text = value.to_s.strip
      return nil if text.empty?

      Float(text)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :distance, :coordinate_hash, :lookup_key, :numeric
  end
end
