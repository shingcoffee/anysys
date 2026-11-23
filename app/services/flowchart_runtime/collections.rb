# frozen_string_literal: true

module FlowchartRuntime
  # Collection algorithms used by ported data-operation step actions.
  # Generators emit a single call so `generate_body` stays within BodyLint.
  module Collections
    class Error < StandardError; end

    RETURNS = %w[items split first last index count any all none].freeze
    FILTER_OPERATORS = %w[eq ne gt lt gte lte includes blank present].freeze
    AGGREGATES = %w[sum count avg min max product concat custom].freeze
    MANIPULATE = %w[map pluck group sort unique chunk flatten zip].freeze
    PREDICATES = %w[nil blank false_or_nil].freeze
    BLANK_DEFINITIONS = %w[nil empty whitespace].freeze
    ROUNDING_MODES = %w[half_up half_even floor ceiling].freeze
    CHUNK_MODES = %w[size predicate field].freeze
    ZIP_STRATEGIES = %w[strict longest shortest].freeze
    RESULT_SHAPES = %w[tuples hashes].freeze
    SORT_GROUPS = %w[none key_asc key_desc count_asc count_desc].freeze

    module_function

    def filter(items, returns:, field: nil, operator: "eq", compare: nil, conditions: [],
               join: "AND", reject: false, nil_handling: "treat_as_false", extra: nil, default: nil,
               limit: 0)
      mode = returns.to_s
      raise Error, "unknown returns #{returns.inspect}" unless RETURNS.include?(mode)

      list = Array(items)
      list = list.compact if nil_handling.to_s == "exclude"
      pred = lambda { |item| apply_nil_handling(item, nil_handling) { match_item?(item, field, operator, compare, conditions, join, extra) } }
      pred = invert(pred) if reject

      result = case mode
      when "items" then list.select { |item| pred.call(item) }
      when "split" then list.partition { |item| pred.call(item) }
      when "first" then list.find { |item| pred.call(item) } || default
      when "last" then list.reverse_each.find { |item| pred.call(item) } || default
      when "index" then idx = list.index { |item| pred.call(item) }; idx.nil? ? default : idx
      when "count" then list.count { |item| pred.call(item) }
      when "any" then list.any? { |item| pred.call(item) }
      when "all" then list.empty? ? true : list.all? { |item| pred.call(item) }
      when "none" then list.none? { |item| pred.call(item) }
      end
      apply_limit(result, mode, limit)
    end

    def aggregate(items, operation:, field: nil, ignore_nils: true, empty_behavior: "zero",
                  empty_default: nil, precision: 0, rounding_mode: "half_up", separator: "")
      op = operation.to_s
      raise Error, "unknown operation #{operation.inspect}" unless AGGREGATES.include?(op)

      list = Array(items)
      list = list.compact if ignore_nils
      return empty_aggregate(empty_behavior, empty_default) if list.empty?

      values = field.to_s.strip.empty? ? list : list.map { |item| dig_item(item, field) }
      values = values.compact if ignore_nils
      return empty_aggregate(empty_behavior, empty_default) if values.empty? && op != "count"

      result = case op
      when "sum" then numeric_values(values).sum
      when "count" then field.to_s.strip.empty? ? list.size : values.size
      when "avg" then nums = numeric_values(values); nums.empty? ? 0 : nums.sum.to_f / nums.size
      when "min" then field.to_s.strip.empty? ? list.min : values.min
      when "max" then field.to_s.strip.empty? ? list.max : values.max
      when "product" then numeric_values(values).inject(1) { |acc, n| acc * n }
      when "concat" then values.join(separator.to_s)
      else
        raise Error, "custom aggregation must be emitted by the generator"
      end

      round_aggregate(result, precision, rounding_mode, op)
    end

    def random(type, length = 0)
      size = length.to_i
      case type.to_s
      when "uuid" then SecureRandom.uuid
      when "hex" then size.positive? ? SecureRandom.hex(size) : SecureRandom.hex
      when "int" then size.positive? ? SecureRandom.random_number(size) : SecureRandom.random_number(2**31)
      when "float" then SecureRandom.random_number
      else
        raise Error, "unknown random type #{type.inspect}"
      end
    end

    def first_present_from_ctx(ctx, paths, literals: [], predicate: "blank", blank_definition: "whitespace")
      values = Array(paths).map { |path| read_path(ctx, path) } + Array(literals)
      first_present(values, predicate: predicate, blank_definition: blank_definition)
    end

    def first_present(values, predicate: "blank", blank_definition: "whitespace")
      Array(values).find { |value| !skip_present?(value, predicate, blank_definition) }
    end

    def map(items, mappings:, key_format: "symbol", compact: false, preserve_nils: true)
      pairs = mapping_pairs(mappings)
      result = Array(items).map do |item|
        next nil if item.nil? && !preserve_nils
        next item if pairs.empty?

        pairs.each_with_object({}) do |(from, to), hash|
          key = key_format.to_s == "string" ? to.to_s : to.to_s.to_sym
          hash[key] = dig_item(item, from)
        end
      end
      compact ? result.compact : result
    end

    def pluck(items, fields:, flatten: false, include_index: false)
      entries = mapping_pairs(fields)
      Array(items).each_with_index.map do |item, idx|
        if entries.length == 1 && flatten && !include_index
          dig_item(item, entries.first.first)
        else
          row = entries.each_with_object({}) do |(path, key), hash|
            hash[key.to_s.to_sym] = dig_item(item, path)
          end
          row[:source_index] = idx if include_index
          row
        end
      end
    end

    def group(items, field: nil, expression: nil, include_count: false, sort_groups: "none")
      raise Error, "unknown sort_groups #{sort_groups.inspect}" unless SORT_GROUPS.include?(sort_groups.to_s)

      grouped = Array(items).group_by do |item|
        expression.respond_to?(:call) ? expression.call(item) : dig_item(item, field.presence || "id")
      end
      grouped = sort_grouped(grouped, sort_groups)
      return grouped unless include_count

      grouped.transform_values { |rows| { items: rows, count: rows.size } }
    end

    def sort(items, field: nil, direction: "asc", fields: nil, nulls_first: false)
      list = Array(items)
      specs = normalize_sort_fields(fields, field, direction)
      keyed = list.sort_by { |item| sort_key(item, specs) }
      keyed = keyed.reverse if specs.all? { |spec| spec[:direction] == "desc" }
      return keyed unless nulls_first

      primary = specs.first
      nils, rest = keyed.partition { |item| dig_item(item, primary[:field]).nil? }
      nils + rest
    end

    def unique(items, field: nil, keep: "first")
      list = Array(items)
      list = list.reverse if keep.to_s == "last"
      result = if field.to_s.strip.empty?
        list.uniq
      else
        list.uniq { |item| dig_item(item, field) }
      end
      keep.to_s == "last" ? result.reverse : result
    end

    def chunk(items, mode: "size", size: 100, remainder: true, field: nil, predicate: nil)
      list = Array(items)
      case mode.to_s
      when "size"
        width = [size.to_i, 1].max
        slices = list.each_slice(width).to_a
        remainder ? slices : slices.select { |slice| slice.size == width }
      when "predicate"
        test = predicate.respond_to?(:call) ? predicate : ->(*) { false }
        list.chunk_while { |left, right| !test.call(left, right) }.to_a
      when "field"
        list.chunk { |item| dig_item(item, field) }.map { |_key, group| group }
      else
        raise Error, "unknown chunk mode #{mode.inspect}"
      end
    end

    def flatten(items, depth: 1, compact: false)
      list = Array(items)
      levels = depth.to_i
      flat = levels.positive? ? list.flatten(levels) : list.flatten
      compact ? flat.compact : flat
    end

    def zip(collections, strategy: "shortest", shape: "tuples", fill: nil, keys: [])
      lists = Array(collections).map { |col| Array(col) }
      raise Error, "zip needs at least two collections" if lists.size < 2
      raise Error, "unknown zip strategy #{strategy.inspect}" unless ZIP_STRATEGIES.include?(strategy.to_s)
      raise Error, "unknown result shape #{shape.inspect}" unless RESULT_SHAPES.include?(shape.to_s)
      raise Error, "collection lengths do not match" if strategy.to_s == "strict" && lists.map(&:size).uniq.size > 1

      aligned = align_zip(lists, strategy, fill)
      tuples = aligned[0].zip(*aligned[1..])
      return tuples unless shape.to_s == "hashes"

      names = Array(keys).map { |key| key.to_s.to_sym }
      names = lists.each_index.map { |idx| :"col_#{idx}" } if names.size < lists.size
      tuples.map { |group| names.first(group.size).zip(group).to_h }
    end

    def dig_item(item, field)
      return item if field.nil? || field.to_s.strip.empty?
      return nil if item.nil?

      parts = field.to_s.split(".").map(&:strip).reject(&:empty?)
      return item if parts.empty?

      parts.reduce(item) { |current, part| dig_part(current, part) }
    end

    # Records expose flowchart_value (id, stored, derived), never arbitrary methods.
    def dig_part(current, part)
      case current
      when nil then nil
      when EntityEntry then current.flowchart_value(part)
      when Hash then Step.dig(current, integer_or_key(part))
      when Array then Step.dig(current, part.to_s.match?(/\A\d+\z/) ? part.to_i : part)
      else
        nil
      end
    end

    def integer_or_key(part)
      text = part.to_s
      text.match?(/\A\d+\z/) ? text.to_i : text.to_sym
    end

    def read_path(ctx, path)
      root, *rest = path.to_s.split(".")
      return nil if root.to_s.empty?

      current = ctx[root.to_s]
      current = ctx[root.to_sym] if current.nil? && ctx.respond_to?(:[])
      return current if rest.empty?

      keys = rest.map { |segment| segment.match?(/\A\d+\z/) ? segment.to_i : segment.to_sym }
      Step.dig(current, *keys)
    end

    def mapping_pairs(raw)
      case raw
      when Hash
        raw.map { |key, value| [key.to_s, (value.presence || key).to_s] }
      when Array
        raw.filter_map do |entry|
          next unless entry.is_a?(Hash)

          from = entry["from"] || entry[:from] || entry["key"] || entry[:key]
          to = entry["to"] || entry[:to] || entry["value"] || entry[:value]
          next if from.to_s.empty?

          [from.to_s, (to.presence || from).to_s]
        end
      else
        []
      end
    end

    def match_item?(item, field, operator, compare, conditions, join, extra)
      clauses = []
      rows = Array(conditions).select { |row| row.is_a?(Hash) && (row["field"] || row[:field]).to_s.present? }
      if rows.any?
        clauses.concat(rows.map { |row| compare_field(item, row["field"] || row[:field], row["operator"] || row[:operator], row["value"] || row[:value]) })
      elsif field.to_s.present?
        clauses << compare_field(item, field, operator, compare)
      end
      clauses << extra.call(item) if extra.respond_to?(:call)
      return present_item?(item) if clauses.empty?

      join.to_s == "OR" ? clauses.any? : clauses.all?
    end

    def compare_field(item, field, operator, compare)
      actual = dig_item(item, field)
      op = FILTER_OPERATORS.include?(operator.to_s) ? operator.to_s : "eq"
      case op
      when "ne" then actual != typed_compare(compare)
      when "gt" then ordered?(actual, typed_compare(compare), :>)
      when "lt" then ordered?(actual, typed_compare(compare), :<)
      when "gte" then ordered?(actual, typed_compare(compare), :>=)
      when "lte" then ordered?(actual, typed_compare(compare), :<=)
      when "includes" then includes_value?(actual, compare)
      when "blank" then actual.respond_to?(:blank?) ? actual.blank? : actual.nil?
      when "present" then actual.respond_to?(:present?) ? actual.present? : !actual.nil?
      else actual == typed_compare(compare)
      end
    end

    def apply_nil_handling(item, policy)
      case policy.to_s
      when "include" then item.nil? || yield
      when "exclude" then yield
      else
        item.nil? ? false : yield
      end
    end

    def invert(pred)
      ->(item) { !pred.call(item) }
    end

    def apply_limit(result, mode, limit)
      cap = limit.to_i
      return result unless cap.positive?

      case mode
      when "items" then result.first(cap)
      when "split" then [result[0].first(cap), result[1].first(cap)]
      else result
      end
    end

    def present_item?(item)
      item.respond_to?(:present?) ? item.present? : !item.nil?
    end

    def typed_compare(value)
      return value if value.nil? || value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
      text = value.to_s
      return text.to_i if text.match?(/\A-?\d+\z/)
      return text.to_f if text.match?(/\A-?\d+\.\d+\z/)

      text
    end

    def numeric_compare(value)
      value.is_a?(Numeric) ? value : value.to_f
    end

    def comparable(value)
      value.is_a?(Numeric) ? value : value.to_f
    end

    def skip_present?(value, predicate, blank_definition)
      case predicate.to_s
      when "blank" then value.blank?
      when "false_or_nil" then !value
      when "nil" then value.nil?
      else value.blank?
      end
    end

    def includes_value?(actual, compare)
      if actual.is_a?(Array)
        actual.include?(typed_compare(compare)) || actual.map(&:to_s).include?(compare.to_s)
      else
        actual.to_s.include?(compare.to_s)
      end
    end

    def ordered?(left, right, operator)
      if left.respond_to?(:<=>) && !left.is_a?(String) && (left <=> right)
        left.public_send(operator, right)
      else
        comparable(left).public_send(operator, numeric_compare(right))
      end
    end

    def blank?(value, definition)
      case definition.to_s
      when "empty" then value.nil? || (value.respond_to?(:empty?) && value.empty?)
      when "whitespace" then value.is_a?(String) ? value.strip.empty? : value.nil?
      else value.nil?
      end
    end

    def empty_aggregate(behavior, default)
      return default unless default.nil? || default.to_s == ""
      behavior.to_s == "nil" ? nil : 0
    end

    def numeric_values(values)
      values.filter_map do |value|
        next value if value.is_a?(Numeric)
        next value.to_f if value.to_s.match?(/\A-?\d+(\.\d+)?\z/)

        nil
      end
    end

    def round_aggregate(result, precision, rounding_mode, operation)
      places = precision.to_i
      return result unless places.positive? && %w[sum avg min max product].include?(operation.to_s)
      return result unless result.is_a?(Numeric)

      case rounding_mode.to_s
      when "half_even" then result.round(places, half: :even)
      when "floor" then result.floor(places)
      when "ceiling" then result.ceil(places)
      else result.round(places, half: :up)
      end
    end

    def sort_grouped(grouped, mode)
      case mode.to_s
      when "key_asc" then grouped.sort_by { |key, _| key }.to_h
      when "key_desc" then grouped.sort_by { |key, _| key }.reverse.to_h
      when "count_asc" then grouped.sort_by { |_key, rows| rows.size }.to_h
      when "count_desc" then grouped.sort_by { |_key, rows| rows.size }.reverse.to_h
      else grouped
      end
    end

    def normalize_sort_fields(fields, field, direction)
      if fields.is_a?(Array) && fields.any?
        fields.map { |spec| { field: (spec[:field] || spec["field"]).to_s, direction: (spec[:direction] || spec["direction"] || "asc").to_s } }
      else
        [{ field: (field.presence || "id").to_s, direction: (direction.presence || "asc").to_s }]
      end
    end

    def sort_key(item, specs)
      keys = specs.map do |spec|
        value = dig_item(item, spec[:field])
        spec[:direction] == "desc" && value.is_a?(Numeric) ? -value : value
      end
      keys.size == 1 ? keys.first : keys
    end

    def align_zip(lists, strategy, fill)
      case strategy.to_s
      when "longest"
        width = lists.map(&:size).max
        lists.map { |list| list + Array.new([width - list.size, 0].max, fill) }
      when "shortest"
        width = lists.map(&:size).min
        lists.map { |list| list.first(width) }
      else
        lists
      end
    end
  end
end
