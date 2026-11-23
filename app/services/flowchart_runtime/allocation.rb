# frozen_string_literal: true

module FlowchartRuntime
  # Splits an amount into parts that sum exactly to the (rounded) input.
  module Allocation
    class Error < StandardError; end

    METHODS = %w[even ratio percent].freeze
    REMAINDER_STRATEGIES = %w[largest_remainder first last largest_share].freeze
    PERCENT_TOTAL = BigDecimal("100")
    HASH_WEIGHT_KEYS = %w[weight value ratio percent share].freeze

    module_function

    def split(ctx, amount:, method:, parts: 2, weights: nil, weight_field: nil,
              precision: 2, remainder_strategy: "largest_remainder")
      name = method.to_s
      raise Error, "unsupported method" unless METHODS.include?(name)
      raise Error, "unsupported remainder strategy" unless REMAINDER_STRATEGIES.include?(remainder_strategy.to_s)

      total = Money.decimal(amount)
      return Step.fail(ctx, :"allocate_amount.invalid_amount") if total.nil?

      weight_list = weights_for(name, parts, weights, weight_field)
      return Step.fail(ctx, :"allocate_amount.invalid_weights") if weight_list.nil?

      if name == "percent"
        percent_sum = weight_list.reduce(Money.zero, :+)
        unless Money.round(percent_sum, 8, "half_up") == PERCENT_TOTAL
          return Step.fail(ctx, :"allocate_amount.percent_total", total: Money.format_decimal(percent_sum, 2))
        end
      end

      shares(total, weight_list, precision: precision, remainder_strategy: remainder_strategy)
        .map { |share| Money.format_decimal(share, precision) }
    end

    def shares(amount, weights, precision:, remainder_strategy:)
      total = amount.is_a?(BigDecimal) ? amount : Money.decimal(amount)
      raise Error, "invalid amount" if total.nil?

      list = Array(weights).map { |weight| weight.is_a?(BigDecimal) ? weight : Money.decimal(weight) }
      raise Error, "invalid weights" if list.empty? || list.any?(&:nil?) || list.any?(&:negative?)

      weight_sum = list.reduce(Money.zero, :+)
      raise Error, "invalid weights" if weight_sum.zero?

      places = precision.to_i
      target = Money.round(total, places, "half_up")
      return Array.new(list.size, Money.zero) if target.zero?

      sign = target.negative? ? -1 : 1
      abs_target = target.abs
      exact = list.map { |weight| abs_target * weight / weight_sum }
      distribute(abs_target, exact, places, remainder_strategy.to_s).map { |share| share * sign }
    end

    def weights_for(method, parts, weights, weight_field)
      return Array.new([[Integer(parts), 1].max, 1000].min, BigDecimal("1")) if method == "even"

      raw = case weights
      when nil then nil
      when Array then weights
      when Hash then [weights]
      else
        return nil
      end
      return nil if raw.nil? || raw.empty?

      extracted = raw.map { |item| weight_of(item, weight_field) }
      return nil if extracted.any?(&:nil?) || extracted.any?(&:negative?) || extracted.all?(&:zero?)

      extracted
    rescue ArgumentError, TypeError
      nil
    end

    def weight_of(item, field)
      return Money.decimal(item) unless item.is_a?(Hash) || item.is_a?(ActiveRecord::Base)

      key = field.to_s.strip
      keys = key.empty? ? HASH_WEIGHT_KEYS : [key]
      Money.decimal(keys.lazy.filter_map { |name| Collections.dig_item(item, name) }.first)
    end

    def distribute(target, exact, places, strategy)
      unit = Money.unit(places)
      floored = exact.map { |value| value.round(places, BigDecimal::ROUND_FLOOR) }
      leftover = ((target - floored.reduce(Money.zero, :+)) / unit).to_i
      order = remainder_order(strategy, exact, floored)
      leftover.times do |index|
        floored[order[index % order.size]] += unit
      end
      floored
    end

    def remainder_order(strategy, exact, floored)
      size = exact.size
      case strategy
      when "first" then (0...size).to_a
      when "last" then (0...size).to_a.reverse
      when "largest_share"
        (0...size).sort_by { |index| [-exact[index], index] }
      else
        (0...size).sort_by { |index| [-(exact[index] - floored[index]), index] }
      end
    end
  end
end
