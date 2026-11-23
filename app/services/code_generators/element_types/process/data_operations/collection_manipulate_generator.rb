# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class CollectionManipulateGenerator < BaseGenerator
          OPERATIONS = %w[map pluck group sort unique flatten].freeze
          SORT_DIRECTIONS = %w[asc desc].freeze
          SORT_GROUPS = %w[none key_asc key_desc count_asc count_desc].freeze
          KEEP_STRATEGIES = %w[first last].freeze

          generator_metadata do
            description "Rewrites a list of hashes or EntityEntry records: map (rename fields), pluck (extract a column such as emails), group (bucket by status), sort, unique (de-duplicate by field), or flatten nested arrays. Use filter_collection to keep or drop rows, calculate to sum a field, and hash_manipulate for a single hash. Reads sourceVariable; writes resultVar. Record fields are read via flowchart_value. Does not fail unless the operation input is invalid."
            category :data_operations
            version "2.0.0"
            presentation icon: "M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7",
                         color: "indigo", single_use: false, privileged: false
          end

          config_schema do
            enum :operation, OPERATIONS, default: "map",
                 description: "How to rewrite the list. map reshapes each item via fieldMappings; pluck extracts fields (one field returns a flat list); group buckets by groupField; sort orders by sortField; unique drops duplicates; flatten unwraps nested arrays."
            input :sourceVariable, required: true, example: "items",
                  description: "Ctx path of the list to rewrite. Example: line_items or items."
            output :resultVar, default: "collection",
                   description: "Ctx variable later steps read. Example: emails or grouped_orders."
            mapping :fieldMappings, key: :literal, value: :literal,
                    example: [{ "key" => "name", "value" => "label" }], visible: { operation: "map" },
                    description: "Source field path to target key for each mapped item. Example: name -> label. Keys on the result are symbols."
            flag :compactResult, default: false, visible: { operation: "map" }, group: :advanced,
                 description: "Drop nil items from the mapped list. Default false keeps them."
            mapping :fields, key: :literal, value: :literal,
                    example: [{ "key" => "name", "value" => "label" }], visible: { operation: "pluck" },
                    description: "Field paths to extract. One field returns a flat list of values (e.g. emails); several fields return a list of hashes with optional aliases."
            literal :groupField, example: "category", visible: { operation: "group" },
                    description: "Item field used as the group key. Example: status or category."
            flag :includeCount, default: false, visible: { operation: "group" }, group: :advanced,
                 description: "Store each group as {items, count} instead of just the rows. Default false."
            enum :sortGroups, SORT_GROUPS, default: "none", visible: { operation: "group" }, group: :advanced,
                 description: "Order of keys in the grouped hash. none keeps insertion order; key_asc/key_desc sort by key; count_asc/count_desc sort by group size."
            literal :sortField, example: "name", visible: { operation: "sort" },
                    description: "Item field used to sort. Example: amount or created_at."
            enum :sortDirection, SORT_DIRECTIONS, default: "asc", visible: { operation: "sort" },
                 description: "Sort order. asc is low to high (A-Z, oldest first); desc is high to low."
            flag :nullsFirst, default: false, visible: { operation: "sort" }, group: :advanced,
                 description: "Place items with a nil sort field before the others. Default false leaves them where Ruby sort_by puts them."
            literal :uniqField, default: "", visible: { operation: "unique" },
                    description: "Item field used to decide uniqueness. Leave blank to compare whole items. Example: email."
            enum :keepStrategy, KEEP_STRATEGIES, default: "first", visible: { operation: "unique" }, group: :advanced,
                 description: "Which duplicate to keep. first keeps the earliest item; last keeps the latest. Default first."
            integer :depth, min: 0, default: 1, visible: { operation: "flatten" },
                    description: "How many array levels to unwrap. 1 flattens one nesting; 0 flattens all the way. Default 1."
            flag :removeNilElements, default: false, visible: { operation: "flatten" }, group: :advanced,
                 description: "Drop nils after flattening. Default false keeps them."
            requires :fieldMappings, when: { operation: "map" }
            requires :fields, when: { operation: "pluck" }
            requires :sortField, when: { operation: "sort" }

            validate do |cfg, errors|
              op = cfg["operation"].to_s
              op = "map" if op.empty?
              if op == "group" && cfg["groupField"].to_s.strip.empty?
                errors.add(:groupField, :required)
              end
            end
          end

          def generate_body
            body(
              assign("resultVar", manipulate_call),
              "true"
            )
          end

          private

          def manipulate_call
            case value("operation").to_s
            when "map" then map_call
            when "pluck" then pluck_call
            when "group" then group_call
            when "sort" then sort_call
            when "unique" then unique_call
            else flatten_call
            end
          end

          def source_array
            "Array(#{read("sourceVariable")})"
          end

          def map_call
            compact = read("compactResult")
            args = [source_array, "mappings: #{read("fieldMappings")}"]
            args << "compact: true" if compact == "true"
            "FlowchartRuntime::Collections.map(#{args.join(", ")})"
          end

          def pluck_call
            args = [source_array, "fields: #{read("fields")}"]
            args << "flatten: true" if single_pluck_field?
            "FlowchartRuntime::Collections.pluck(#{args.join(", ")})"
          end

          def single_pluck_field?
            rows = Array(value("fields"))
            pairs = rows.count { |row| row.is_a?(Hash) && (row["key"] || row[:key]).to_s.present? }
            pairs <= 1
          end

          def group_call
            count = read("includeCount")
            sort = read("sortGroups")
            args = [source_array, "field: #{read("groupField")}"]
            args << "include_count: true" if count == "true"
            args << "sort_groups: #{sort}" unless sort == '"none"'
            "FlowchartRuntime::Collections.group(#{args.join(", ")})"
          end

          def sort_call
            direction = read("sortDirection")
            nulls = read("nullsFirst")
            args = [source_array, "field: #{read("sortField")}"]
            args << "direction: #{direction}" unless direction == '"asc"'
            args << "nulls_first: true" if nulls == "true"
            "FlowchartRuntime::Collections.sort(#{args.join(", ")})"
          end

          def unique_call
            field = read("uniqField")
            keep = read("keepStrategy")
            args = [source_array]
            args << "field: #{field}" unless field == '""'
            args << "keep: #{keep}" unless keep == '"first"'
            "FlowchartRuntime::Collections.unique(#{args.join(", ")})"
          end

          def flatten_call
            depth = read("depth")
            compact = read("removeNilElements")
            args = [source_array]
            args << "depth: #{depth}" unless depth == "1"
            args << "compact: true" if compact == "true"
            "FlowchartRuntime::Collections.flatten(#{args.join(", ")})"
          end
        end
      end
    end
  end
end
