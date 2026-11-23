# frozen_string_literal: true

module FlowchartRuntime
  # DMN-style decision table for evaluate_rules. Condition/result rows are
  # lambdas so `first` can stop without evaluating later results.
  module RulesTable
    class Error < StandardError; end

    HIT_POLICIES = %w[first collect sum count min max any].freeze

    module_function

    def evaluate(ctx, rules, hit_policy:, default_value: nil, on_no_match: "default",
                 unique_results: false)
      policy = hit_policy.to_s
      raise Error, "unknown hit policy #{hit_policy.inspect}" unless HIT_POLICIES.include?(policy)

      matched = []
      results = []
      Array(rules).each_with_index do |row, index|
        condition, result = unpack(row)
        next unless invoke(condition)

        matched << index + 1
        if policy == "first"
          return pack(invoke(result), matched)
        elsif policy != "count"
          results << invoke(result)
        end
      end

      return no_match(ctx, default_value, on_no_match) if matched.empty?

      finish(ctx, policy, results, matched, unique_results)
    end

    def unpack(row)
      case row
      when Array then [row[0], row[1]]
      when Hash then [row[:condition] || row["condition"] || row[:key] || row["key"],
                      row[:result] || row["result"] || row[:value] || row["value"]]
      else
        raise Error, "rule row must be a pair"
      end
    end

    def invoke(value)
      value.respond_to?(:call) ? value.call : value
    end

    def finish(ctx, policy, results, matched, unique_results)
      case policy
      when "collect"
        pack(unique_results ? results.uniq : results, matched)
      when "count"
        pack(matched.size, matched)
      when "sum"
        nums = try_numbers(results)
        nums ? pack(nums.sum, matched) : Step.fail(ctx, :"evaluate_rules.non_numeric")
      when "min"
        nums = try_numbers(results)
        nums ? pack(nums.min, matched) : Step.fail(ctx, :"evaluate_rules.non_numeric")
      when "max"
        nums = try_numbers(results)
        nums ? pack(nums.max, matched) : Step.fail(ctx, :"evaluate_rules.non_numeric")
      when "any"
        if results.uniq.size > 1
          Step.fail(ctx, :"evaluate_rules.any_conflict")
        else
          pack(results.first, matched)
        end
      else
        pack(results.first, matched)
      end
    end

    def try_numbers(results)
      nums = results.map { |value| Money.decimal(value) }
      nums.all? ? nums : nil
    end

    def no_match(ctx, default_value, on_no_match)
      if on_no_match.to_s == "fail"
        return Step.fail(ctx, :"evaluate_rules.no_match")
      end

      pack(default_value, [])
    end

    def pack(result, matched)
      { result: result, matched: matched }
    end

    private_class_method :unpack, :invoke, :finish, :try_numbers, :no_match, :pack
  end
end
