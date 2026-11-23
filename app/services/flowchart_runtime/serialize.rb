# frozen_string_literal: true

require "csv"

module FlowchartRuntime
  # JSON / XML / YAML / CSV / TOML serialization.
  module Serialize
    class Error < StandardError; end

    FORMATS = %w[json xml yaml csv toml].freeze

    module_function

    def apply(source, format:, pretty: false, json_max_depth: 0, include_root: false,
              root_element: "data", exclude_nils: false)
      name = format.to_s
      raise Error, "unsupported format" unless FORMATS.include?(name)

      payload = exclude_nils ? compact_nils(source) : source
      case name
      when "json" then json(payload, pretty: pretty, max_depth: json_max_depth.to_i)
      when "yaml" then payload.to_yaml
      when "xml" then xml(payload, include_root: include_root, root_element: root_element)
      when "csv" then csv(payload)
      when "toml" then toml(payload)
      end
    rescue JSON::GeneratorError, TypeError, ArgumentError, NoMethodError => error
      raise Error, error.message
    end

    def compact_nils(source)
      if source.respond_to?(:compact)
        source.compact
      else
        source
      end
    end

    def json(payload, pretty:, max_depth:)
      opts = max_depth.positive? ? { max_nesting: max_depth } : {}
      if pretty
        opts.empty? ? JSON.pretty_generate(payload) : JSON.pretty_generate(payload, opts)
      elsif opts.empty?
        payload.to_json
      else
        JSON.generate(payload, opts)
      end
    end

    def xml(payload, include_root:, root_element:)
      opts = { root: (root_element.presence || "data") }
      opts[:skip_types] = true unless include_root
      payload.to_xml(opts)
    end

    def csv(payload)
      rows = Array(payload)
      return "" if rows.empty?

      if rows.first.is_a?(Hash)
        headers = rows.flat_map { |row| row.keys.map(&:to_s) }.uniq
        CSV.generate do |out|
          out << headers
          rows.each do |row|
            next unless row.is_a?(Hash)

            out << headers.map { |header| row[header] || row[header.to_sym] }
          end
        end
      else
        CSV.generate do |out|
          rows.each { |row| out << Array(row) }
        end
      end
    end

    def toml(payload)
      hash = payload.is_a?(Hash) ? payload : { "value" => payload }
      FlowchartRuntime::Toml.generate(hash.transform_keys(&:to_s))
    rescue FlowchartRuntime::Toml::Error => error
      raise Error, error.message
    end
  end
end
