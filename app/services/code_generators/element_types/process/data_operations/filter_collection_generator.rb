# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class FilterCollectionGenerator < BaseGenerator
          RETURNS = %w[items split first last index count any all none].freeze
          NIL_HANDLING = %w[include exclude treat_as_false].freeze
          FILTER_MODES = %w[single multi].freeze
          CONDITION_OPERATORS = %w[AND OR].freeze
          FILTER_OPERATORS = %w[eq ne gt lt gte lte includes blank present].freeze
          DEFAULT_RETURNS = %w[first last index].freeze

          generator_metadata do
            description "Keeps, splits, or inspects items in a list of hashes or EntityEntry records by field comparison (eq, ne, gt, lt, gte, lte, includes, blank, present). Use collection_manipulate to sort, group, or pluck, and calculate to aggregate the result. Reads sourceVariable; writes resultVar (and rejectedVar when returns is split). returns can be the matching items, first/last match, index, count, or a boolean (any/all/none). Record fields are read via flowchart_value. Does not fail for an empty list."
            category :data_operations
            version "3.0.0"
            presentation icon: "M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z",
                         color: "blue", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "items",
                  description: "Ctx path of the list to filter. Example: orders or line_items."
            enum :returns, RETURNS, default: "items",
                 description: "What to store. items is the matching rows; split also fills rejectedVar; first/last/index pick one match; count is a number; any/all/none are booleans."
            output :resultVar, default: "filtered",
                   description: "Ctx variable later steps read. Example: open_orders."
            output :rejectedVar, default: "rejected", visible: { returns: "split" },
                   description: "Ctx variable that receives items that failed the predicate when returns is split. Example: closed_orders."
            enum :filterMode, FILTER_MODES, default: "single",
                 description: "single compares one field; multi joins a list of conditions with AND or OR."
            literal :filterField, example: "status", visible: { filterMode: "single" },
                    description: "Item field compared in single mode. Dotted paths allowed. Example: status or item.sku."
            enum :filterOperator, FILTER_OPERATORS, default: "eq", visible: { filterMode: "single" },
                 description: "Comparison against filterValue. eq/ne equality; gt/lt/gte/lte numeric or date order; includes substring or array membership; blank/present ignore filterValue."
            literal :filterValue, default: "", visible: { filterMode: "single" },
                    description: "Value compared to the field for eq/ne/gt/lt/gte/lte/includes. Example: active or 10. Unused for blank/present."
            list :conditions, example: [{ "field" => "status", "operator" => "eq", "value" => "active" }],
                 visible: { filterMode: "multi" },
                 description: "Rows of {field, operator, value} joined by conditionOperator. Example: status eq active."
            enum :conditionOperator, CONDITION_OPERATORS, default: "AND", visible: { filterMode: "multi" },
                 description: "How multiple conditions are joined. AND requires every row; OR requires any row. Default AND."
            flag :rejectMode, default: false, group: :advanced,
                 description: "Keep items that fail the predicate instead of those that match. Default false."
            enum :nilHandling, NIL_HANDLING, default: "treat_as_false", group: :advanced,
                 description: "How nil items are treated. treat_as_false skips them; include counts them as matches; exclude drops them before testing. Default treat_as_false."
            integer :limit, min: 0, max: 10_000, default: 0, group: :advanced,
                    description: "Maximum matched (and rejected, when splitting) items to keep. 0 keeps all. Example: 10."
            literal :defaultValue, default: "", visible: { returns: DEFAULT_RETURNS },
                    description: "Value stored when first, last, or index finds nothing. Example: none. Empty stores nil."
            requires :filterField, when: { filterMode: "single" }
            requires :conditions, when: { filterMode: "multi" }
          end

          def generate_body
            if value("returns").to_s == "split"
              body(
                "matched, rejected = #{filter_call}",
                assign("resultVar", "matched"),
                assign("rejectedVar", "rejected"),
                "true"
              )
            else
              body(
                assign("resultVar", filter_call),
                "true"
              )
            end
          end

          private

          def filter_call
            returns = read("returns")
            operator = read("filterOperator")
            join = read("conditionOperator")
            reject = read("rejectMode")
            nil_handling = read("nilHandling")
            limit = read("limit")
            args = ["Array(#{read("sourceVariable")})", "returns: #{returns}"]
            if value("filterMode").to_s == "multi"
              args << "operator: #{operator}" unless operator == '"eq"'
              args << "conditions: #{literal(Array(value("conditions")))}"
              args << "join: #{join}" unless join == '"AND"'
            else
              args << "field: #{read("filterField")}"
              args << "operator: #{operator}" unless operator == '"eq"'
              compare = read("filterValue")
              args << "compare: #{compare}" unless compare == "nil" || compare == '""'
            end
            args << "reject: true" if reject == "true"
            args << "nil_handling: #{nil_handling}" unless nil_handling == '"treat_as_false"'
            args.concat(default_args)
            args << "limit: #{limit}" unless limit == "0"
            "FlowchartRuntime::Collections.filter(#{args.join(", ")})"
          end

          def default_args
            raw = value("defaultValue").to_s
            return [] if raw.empty?
            return [] unless DEFAULT_RETURNS.include?(value("returns").to_s)

            ["default: #{read("defaultValue")}"]
          end
        end
      end
    end
  end
end
