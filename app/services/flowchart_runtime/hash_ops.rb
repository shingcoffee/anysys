# frozen_string_literal: true

module FlowchartRuntime
  # Hash reshape operations for hash_manipulate (including former merge_data
  # and transform hash modes).
  module HashOps
    class Error < StandardError; end

    module_function

    def apply(operation, source, other: nil, keys: [], rename_map: {}, transform: nil,
              case_insensitive: false, merge_strategy: "shallow", array_merge_mode: "concat",
              on_conflict: "last", computed: {}, flatten_separator: "_")
      hash = coerce_hash(source)
      case operation.to_s
      when "pick" then pick(hash, Array(keys), case_insensitive: case_insensitive)
      when "omit" then omit(hash, Array(keys), case_insensitive: case_insensitive)
      when "keys" then hash.keys
      when "values" then hash.values
      when "deep_merge" then hash.deep_merge(coerce_hash(other))
      when "merge" then merge(hash, coerce_hash(other), merge_strategy, array_merge_mode, on_conflict)
      when "diff" then diff(hash, coerce_hash(other))
      when "rename_keys" then rename_keys(hash, rename_map || {})
      when "invert" then hash.invert
      when "deep_dup" then hash.deep_dup
      when "symbolize_keys" then hash.deep_symbolize_keys
      when "stringify_keys" then hash.deep_stringify_keys
      when "transform_keys" then hash.transform_keys(&callable(transform, :keys))
      when "transform_values" then hash.transform_values(&callable(transform, :values))
      when "compact" then hash.compact
      when "set_keys" then hash.merge(stringify_computed(computed))
      when "flatten" then flatten(hash, flatten_separator.to_s.presence || "_")
      else raise Error, "unsupported operation: #{operation}"
      end
    end

    def coerce_hash(value)
      return {} if value.nil?
      return value if value.is_a?(Hash)
      return value.to_liquid if value.is_a?(EntityEntry)
      return value.to_h if value.respond_to?(:to_h)

      raise Error, "not a hash"
    end

    def pick(hash, keys, case_insensitive:)
      return nested_pick(hash, keys) if keys.any? { |key| key.to_s.include?(".") }

      if case_insensitive
        wanted = keys.map { |key| key.to_s.downcase }
        hash.each_with_object({}) { |(key, val), acc| acc[key] = val if wanted.include?(key.to_s.downcase) }
      else
        hash.slice(*matching_keys(hash, keys))
      end
    end

    def omit(hash, keys, case_insensitive:)
      if case_insensitive
        banned = keys.map { |key| key.to_s.downcase }
        hash.each_with_object({}) { |(key, val), acc| acc[key] = val unless banned.include?(key.to_s.downcase) }
      else
        hash.except(*matching_keys(hash, keys))
      end
    end

    def nested_pick(hash, keys)
      keys.each_with_object({}) do |path, acc|
        parts = path.to_s.split(".")
        acc[parts.last] = parts.reduce(hash) { |current, part| Step.dig(current, part.to_sym) }
      end
    end

    def matching_keys(hash, keys)
      keys.flat_map { |key| [key, key.to_s, key.to_s.to_sym] }.uniq.select { |key| hash.key?(key) }
    end

    def rename_keys(hash, rename_map)
      map = rename_map.to_h.transform_keys(&:to_s).transform_values(&:to_s)
      hash.transform_keys { |key| map[key.to_s] || key }
    end

    def diff(left, right)
      {
        added: right.except(*left.keys),
        removed: left.except(*right.keys),
        changed: left.each_with_object({}) { |(key, val), acc|
          acc[key] = { from: val, to: right[key] } if right.key?(key) && right[key] != val
        }
      }
    end

    def merge(left, right, strategy, array_mode, on_conflict)
      case strategy.to_s
      when "replace" then right
      when "append" then append_merge(left, right, array_mode, on_conflict)
      when "deep" then deep_merge(left, right, array_mode, on_conflict)
      else shallow_merge(left, right, on_conflict)
      end
    end

    def shallow_merge(left, right, on_conflict)
      on_conflict.to_s == "first" ? right.merge(left) : left.merge(right)
    end

    def append_merge(left, right, array_mode, on_conflict)
      left.merge(right) do |_key, first, second|
        if first.is_a?(Array) && second.is_a?(Array)
          combine_arrays(first, second, array_mode)
        elsif first.is_a?(Array)
          first + [second]
        elsif second.is_a?(Array)
          [first] + second
        else
          on_conflict.to_s == "first" ? first : second
        end
      end
    end

    def deep_merge(left, right, array_mode, on_conflict)
      first, second = on_conflict.to_s == "first" ? [right, left] : [left, right]
      first.deep_merge(second) do |_key, left_val, right_val|
        if left_val.is_a?(Array) && right_val.is_a?(Array)
          combine_arrays(left_val, right_val, array_mode)
        else
          on_conflict.to_s == "first" ? left_val : right_val
        end
      end
    end

    def combine_arrays(left, right, mode)
      case mode.to_s
      when "concat" then left + right
      when "unique_union" then (left + right).uniq
      else right
      end
    end

    def flatten(hash, separator, prefix = nil)
      hash.each_with_object({}) do |(key, val), acc|
        path = prefix ? "#{prefix}#{separator}#{key}" : key.to_s
        if val.is_a?(Hash)
          acc.merge!(flatten(val, separator, path))
        else
          acc[path] = val
        end
      end
    end

    def stringify_computed(computed)
      (computed || {}).to_h.transform_keys { |key| key.is_a?(Symbol) ? key : key.to_s.to_sym }
    end

    def callable(transform, kind)
      return ->(item) { item } if transform.nil?
      return transform if transform.respond_to?(:call)
      return transform.to_proc if transform.respond_to?(:to_proc) && kind == :keys

      ->(_item) { transform }
    end
  end
end
