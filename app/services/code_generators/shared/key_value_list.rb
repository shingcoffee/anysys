# frozen_string_literal: true

module CodeGenerators
  module Shared
    # Normalizes flowchart UI `key_value_list` wire shapes into keys / pairs.
    # UI emits Array<{ "key" => ..., "value" => ... }>; legacy configs may use
    # Hash or Array<String>.
    module KeyValueList
      module_function

      def keys(raw)
        case raw
        when Hash
          raw.keys.map(&:to_s).reject(&:empty?)
        when Array
          raw.filter_map do |entry|
            case entry
            when Hash
              (entry["key"] || entry[:key] || entry["value"] || entry[:value]).to_s.presence
            when String, Symbol
              entry.to_s.presence
            end
          end
        else
          []
        end
      end

      def pairs(raw)
        case raw
        when Hash
          raw.map { |k, v| [k.to_s, v] }
        when Array
          raw.filter_map do |entry|
            case entry
            when Hash
              key = (entry["key"] || entry[:key]).to_s.presence
              next nil if key.blank?

              [key, entry.key?("value") ? entry["value"] : entry[:value]]
            when String, Symbol
              [entry.to_s, nil]
            end
          end
        else
          []
        end
      end

      def to_hash(raw)
        pairs(raw).to_h
      end
    end
  end
end
