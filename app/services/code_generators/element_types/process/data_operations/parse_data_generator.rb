# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class ParseDataGenerator < BaseGenerator
          FORMATS = FlowchartRuntime::Parse::FORMATS
          ENCODINGS = %w[utf-8 utf-16 ascii iso-8859-1].freeze
          CSV_FIELDS = %w[csv].freeze
          KEYED_FORMATS = %w[json yaml toml].freeze

          generator_metadata do
            description "Parses a JSON, CSV, XML, YAML, or TOML string into structured data. Reads " \
                        "sourceVariable. Writes resultVar as a Hash or Array. YAML uses YAML.safe_load " \
                        "(Date and Time only, no aliases). Use serialize_data to go the other way and " \
                        "regex_extract for a single capture from text. Fails with parse_data.failed " \
                        "when the payload is malformed or larger than 1 MB."
            category :data_operations
            version "2.0.0"
            presentation icon: "M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12",
                         color: "blue", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "payload",
              description: "Context path of the raw string to parse (e.g. params.body or a webhook payload)."
            output :resultVar, default: "data",
              description: "Context variable that receives the parsed Hash or Array of rows."
            enum :format, FORMATS, default: "json",
              description: "Payload format: json, csv (rows of hashes when csvHeaders is on), xml, yaml " \
                           "(safe_load), or toml."
            flag :csvHeaders, default: true, visible: { format: "csv" },
              description: "Treat the first CSV row as column names and return an array of hashes. Off returns arrays of cells."
            literal :csvDelimiter, default: ",", placeholder: true, visible: { format: "csv" },
              description: "CSV column separator. Example: , or ; or a tab character."
            literal :quoteChar, default: '"', placeholder: true, visible: { format: "csv" },
              description: "CSV quote character wrapping cells that contain the delimiter. Example: \"."
            integer :skipRows, min: 0, max: 10_000, default: 0, visible: { format: "csv" },
              description: "Number of leading lines to drop before parsing (0-10000). Example: 1 to skip a title row."
            enum :encoding, ENCODINGS, default: "utf-8", visible: { format: "csv" },
              description: "Character encoding of the CSV bytes: utf-8 (default), utf-16, ascii, or iso-8859-1."
            mapping :colTypes, key: :literal, value: :literal, default: [], visible: { format: "csv" },
              description: "Named CSV columns to cast. Keys are header names; values are string, integer, float, bool, or date."
            literal :xmlRoot, default: "", placeholder: true, visible: { format: "xml" },
              description: "Optional XML root key to unwrap from Hash.from_xml (e.g. order). Blank keeps the full hash."
            flag :symbolizeKeys, default: false, visible: { format: KEYED_FORMATS },
              description: "Convert top-level hash keys to symbols for json, yaml, and toml. Leave off for string keys."
          end

          def generate_body
            body(
              attempt('"parse_data.failed"', FlowchartRuntime::Parse::Error) do
                [assign(:resultVar, parse_call), "true"]
              end
            )
          end

          private

          def parse_call
            "FlowchartRuntime::Parse.apply(#{parse_args})"
          end

          def parse_args
            format = value(:format).to_s
            args = [read(:sourceVariable), "format: #{read(:format)}"]
            if format == "csv"
              args << "csv_headers: false" unless value(:csvHeaders)
              args << "csv_delimiter: #{read(:csvDelimiter)}" unless value(:csvDelimiter) == ","
              args << "quote_char: #{read(:quoteChar)}" unless value(:quoteChar) == '"'
              args << "skip_rows: #{read(:skipRows)}" unless value(:skipRows).to_i.zero?
              args << "encoding: #{read(:encoding)}" unless value(:encoding) == "utf-8"
              args << "col_types: #{read(:colTypes)}" if value(:colTypes).present?
            end
            args << "xml_root: #{read(:xmlRoot)}" if format == "xml" && value(:xmlRoot).to_s.present?
            args << "symbolize_keys: true" if KEYED_FORMATS.include?(format) && value(:symbolizeKeys)
            args.join(", ")
          end
        end
      end
    end
  end
end
