# frozen_string_literal: true

require "csv"

module FlowchartRuntime
  # JSON / CSV / XML / YAML / TOML parsing with a byte cap.
  module Parse
    class Error < StandardError; end

    FORMATS = %w[json csv xml yaml toml].freeze
    COL_TYPES = %w[string integer float bool date].freeze
    MAX_BYTES = 1_048_576
    YAML_PERMITTED = [Date, Time].freeze

    module_function

    def apply(source, format:, csv_headers: true, csv_delimiter: ",", xml_root: "",
              symbolize_keys: false, quote_char: '"', skip_rows: 0, encoding: "utf-8",
              col_types: nil)
      name = format.to_s
      raise Error, "unsupported format" unless FORMATS.include?(name)

      guard_size!(source)
      value = case name
      when "json" then parse_json(source)
      when "csv" then parse_csv(source, csv_headers: csv_headers, csv_delimiter: csv_delimiter,
                                        quote_char: quote_char, skip_rows: skip_rows,
                                        encoding: encoding, col_types: col_types)
      when "xml" then parse_xml(source, xml_root)
      when "yaml" then parse_yaml(source)
      when "toml" then parse_toml(source)
      end
      symbolize_keys && value.respond_to?(:transform_keys) ? value.transform_keys(&:to_sym) : value
    end

    def guard_size!(source)
      raise Error, "payload exceeds maximum bytes" if source.to_s.bytesize > MAX_BYTES
    end

    def parse_json(source)
      FlowchartRuntime::Json.parse(source, max_bytes: MAX_BYTES)
    rescue FlowchartRuntime::Json::Error => error
      raise Error, error.message
    end

    def parse_csv(source, csv_headers:, csv_delimiter:, quote_char:, skip_rows:, encoding:, col_types:)
      text = source.to_s
      skip = skip_rows.to_i
      text = text.lines.drop(skip).join if skip.positive?
      text = text.dup.force_encoding(encoding.to_s) if encoding.to_s.present?
      rows = CSV.parse(
        text,
        headers: csv_headers,
        col_sep: csv_delimiter.to_s.presence || ",",
        quote_char: quote_char.to_s.presence || '"',
        encoding: encoding.to_s.presence || "utf-8"
      )
      parsed = csv_headers ? rows.map(&:to_h) : rows.to_a
      cast_columns(parsed, col_types)
    rescue CSV::MalformedCSVError, ArgumentError, Date::Error => error
      raise Error, error.message
    end

    def parse_xml(source, xml_root)
      parsed = Hash.from_xml(source.to_s)
      root = xml_root.to_s.strip
      return parsed if root.empty?

      parsed[root] || parsed
    rescue RuntimeError, ArgumentError, TypeError => error
      raise Error, error.message
    end

    def parse_yaml(source)
      YAML.safe_load(source.to_s, permitted_classes: YAML_PERMITTED, aliases: false)
    rescue Psych::Exception, ArgumentError => error
      raise Error, error.message
    end

    def parse_toml(source)
      FlowchartRuntime::Toml.parse(source)
    rescue FlowchartRuntime::Toml::Error => error
      raise Error, error.message
    end

    def cast_columns(rows, col_types)
      types = normalize_col_types(col_types)
      return rows if types.empty?

      rows.map do |row|
        next row unless row.is_a?(Hash)

        types.each do |column, type|
          key = row.key?(column) ? column : (row.key?(column.to_sym) ? column.to_sym : nil)
          next unless key

          row[key] = cast_value(row[key], type)
        end
        row
      end
    end

    def normalize_col_types(raw)
      case raw
      when Hash then raw.transform_keys(&:to_s)
      when Array
        raw.each_with_object({}) do |entry, acc|
          next unless entry.is_a?(Hash)

          key = entry["key"] || entry[:key]
          value = entry["value"] || entry[:value]
          acc[key.to_s] = value if key.present?
        end
      else
        {}
      end
    end

    def cast_value(value, type)
      case type.to_s
      when "integer" then Integer(value.to_s, exception: false) || value.to_s.to_i
      when "float" then Float(value.to_s, exception: false) || value.to_s.to_f
      when "bool" then %w[true 1 yes].include?(value.to_s.downcase.strip)
      when "date" then Date.parse(value.to_s)
      else value.to_s
      end
    end
  end
end
