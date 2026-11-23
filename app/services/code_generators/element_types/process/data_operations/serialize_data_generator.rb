# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class SerializeDataGenerator < BaseGenerator
          FORMATS = FlowchartRuntime::Serialize::FORMATS

          generator_metadata do
            description "Serializes a Hash or Array to JSON, XML, YAML, CSV, or TOML text. Reads " \
                        "sourceVariable. Writes resultVar as a string. CSV treats an array of hashes as " \
                        "rows with a header line. Use parse_data to read those formats back and format_value " \
                        "for a single display value. Fails with serialize_data.failed when the value cannot " \
                        "be represented in the chosen format."
            category :data_operations
            version "2.0.0"
            presentation icon: "M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4",
                         color: "green", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "order",
              description: "Context path of the Hash or Array to serialize (e.g. order or line_items)."
            output :resultVar, default: "serialized",
              description: "Context variable that receives the serialized string."
            enum :format, FORMATS, default: "json",
              description: "Output format: json, xml, yaml, csv (array of hashes becomes a headered table), or toml."
            flag :pretty, default: false, visible: { format: "json" },
              description: "Indent JSON with JSON.pretty_generate. Off writes a compact one-line object."
            integer :jsonMaxDepth, min: 0, max: 100, default: 0, visible: { format: "json" }, group: :advanced,
              description: "Maximum JSON nesting (1-100). 0 uses the JSON gem default (unlimited). Deep trees fail the step."
            flag :includeRoot, default: false, visible: { format: "xml" },
              description: "Keep ActiveSupport XML type attributes on elements. Off writes skip_types XML."
            literal :rootElement, default: "data", placeholder: true, visible: { format: "xml" },
              description: "XML root element name. Example: order. Default data."
            flag :excludeNils, default: false,
              description: "Drop nil values with compact before serializing a Hash or Array."
          end

          def generate_body
            body(
              attempt('"serialize_data.failed"', FlowchartRuntime::Serialize::Error) do
                [
                  assign(:resultVar, serialize_call),
                  "true"
                ]
              end
            )
          end

          private

          def serialize_call
            "FlowchartRuntime::Serialize.apply(#{serialize_args})"
          end

          def serialize_args
            format = value(:format).to_s
            args = [read(:sourceVariable), "format: #{read(:format)}"]
            if format == "json"
              args << "pretty: true" if value(:pretty)
              args << "json_max_depth: #{read(:jsonMaxDepth)}" unless value(:jsonMaxDepth).to_i.zero?
            end
            if format == "xml"
              args << "include_root: true" if value(:includeRoot)
              args << "root_element: #{read(:rootElement)}" unless value(:rootElement) == "data"
            end
            args << "exclude_nils: true" if value(:excludeNils)
            args.join(", ")
          end
        end
      end
    end
  end
end
