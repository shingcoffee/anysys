# frozen_string_literal: true

module FlowchartRuntime
  # Order / invoice / quote totals from line items.
  module Pricing
    class Error < StandardError; end

    DISCOUNT_TYPES = %w[none percent amount].freeze
    TAX_MODES = %w[exclusive inclusive none].freeze
    ROUND_PER = %w[line total].freeze
    HUNDRED = BigDecimal("100")

    module_function

    def calculate(ctx, lines:, quantity_field:, unit_price_field:, line_discount_field: "",
                  line_tax_rate_field: "", discount_type: "none", discount_value: 0,
                  discount_override: nil, tax_mode: "exclusive", tax_rate: 0,
                  shipping_amount: 0, shipping_override: nil, shipping_taxable: false, precision: 2,
                  rounding_mode: "half_up", round_per: "line", currency: "")
      raise Error, "unsupported discount type" unless DISCOUNT_TYPES.include?(discount_type.to_s)
      raise Error, "unsupported tax mode" unless TAX_MODES.include?(tax_mode.to_s)
      raise Error, "unsupported round_per" unless ROUND_PER.include?(round_per.to_s)

      items = normalize_lines(lines)
      return Step.fail(ctx, :"calculate_pricing.invalid_line", line: 0) if items == :invalid

      parsed = []
      items.each_with_index do |item, index|
        row = parse_line(ctx, item, index: index, quantity_field: quantity_field,
                         unit_price_field: unit_price_field,
                         line_discount_field: line_discount_field,
                         line_tax_rate_field: line_tax_rate_field,
                         tax_rate: tax_rate)
        return false unless row

        parsed << row
      end

      apply_order_discount!(parsed, discount_type, discount_value, discount_override, precision)
      apply_tax!(parsed, tax_mode, rounding_mode, precision, round_per)
      shipping = shipping_breakdown(shipping_amount, shipping_taxable, tax_mode, tax_rate,
                                    rounding_mode, precision, round_per, shipping_override: shipping_override)
      assemble(parsed, shipping, currency, precision, rounding_mode)
    end

    def normalize_lines(raw)
      case raw
      when nil then []
      when Array then raw
      when Hash, ActiveRecord::Base then [raw]
      when ActiveRecord::Relation then raw.to_a
      else :invalid
      end
    end

    def parse_line(ctx, item, index:, quantity_field:, unit_price_field:, line_discount_field:,
                   line_tax_rate_field:, tax_rate:)
      unless item.is_a?(Hash) || item.is_a?(ActiveRecord::Base)
        return Step.fail(ctx, :"calculate_pricing.invalid_line", line: index + 1)
      end

      quantity = Money.decimal(lookup(item, quantity_field))
      unit_price = Money.decimal(lookup(item, unit_price_field))
      if quantity.nil? || unit_price.nil? || quantity.negative? || unit_price.negative?
        return Step.fail(ctx, :"calculate_pricing.invalid_line", line: index + 1)
      end

      gross = quantity * unit_price
      line_discount = extract_amount(item, line_discount_field)
      line_discount = clamp(line_discount, Money.zero, gross)
      {
        quantity: quantity,
        unit_price: unit_price,
        gross: gross,
        line_discount: line_discount,
        net_after_line: gross - line_discount,
        tax_rate: extract_rate(item, line_tax_rate_field, tax_rate),
        order_discount: Money.zero
      }
    end

    def lookup(item, key)
      Collections.dig_item(item, key.to_s)
    end

    def extract_amount(item, field)
      return Money.zero if field.to_s.strip.empty?

      amount = Money.decimal(lookup(item, field))
      amount.nil? || amount.negative? ? Money.zero : amount
    end

    def extract_rate(item, field, fallback)
      fallback_rate = Money.decimal(fallback)
      fallback_rate = Money.zero if fallback_rate.nil? || fallback_rate.negative?
      return fallback_rate if field.to_s.strip.empty?

      rate = Money.decimal(lookup(item, field))
      rate.nil? || rate.negative? ? fallback_rate : rate
    end

    def clamp(value, min, max)
      return min if value < min
      return max if value > max

      value
    end

    def apply_order_discount!(parsed, discount_type, discount_value, discount_override, precision)
      nets = parsed.map { |row| row[:net_after_line] }
      available = nets.reduce(Money.zero, :+)
      order_discount = order_discount_total(discount_type, discount_value, discount_override, available)
      order_discount = clamp(order_discount, Money.zero, available)
      allocated = if order_discount.zero? || available.zero?
        Array.new(parsed.size, Money.zero)
      else
        Allocation.shares(order_discount, nets, precision: precision, remainder_strategy: "largest_remainder")
      end
      parsed.each_with_index do |row, index|
        share = clamp(allocated[index] || Money.zero, Money.zero, row[:net_after_line])
        row[:order_discount] = share
        row[:discount] = row[:line_discount] + share
        row[:payable] = row[:net_after_line] - share
      end
    end

    def order_discount_total(type, value, override, available)
      return Money.zero if type.to_s == "none"

      amount = Money.decimal(override.nil? ? value : override) || Money.zero
      amount = Money.zero if amount.negative?
      type.to_s == "percent" ? available * amount / HUNDRED : amount
    end

    def apply_tax!(parsed, tax_mode, rounding_mode, precision, round_per)
      parsed.each do |row|
        pretax, tax, total = tax_components(row[:payable], row[:tax_rate], tax_mode)
        if round_per.to_s == "line"
          pretax = Money.round(pretax, precision, rounding_mode)
          tax = Money.round(tax, precision, rounding_mode)
          total = Money.round(total, precision, rounding_mode)
        end
        row[:net] = pretax
        row[:tax] = tax
        row[:total] = total
      end
    end

    def tax_components(payable, rate, tax_mode)
      mode = tax_mode.to_s
      return [payable, Money.zero, payable] if mode == "none" || rate.zero?

      if mode == "inclusive"
        tax = payable * rate / (HUNDRED + rate)
        [payable - tax, tax, payable]
      else
        tax = payable * rate / HUNDRED
        [payable, tax, payable + tax]
      end
    end

    def shipping_breakdown(shipping_amount, taxable, tax_mode, tax_rate, rounding_mode, precision, round_per,
                           shipping_override: nil)
      amount = Money.decimal(shipping_override.nil? ? shipping_amount : shipping_override) || Money.zero
      amount = Money.zero if amount.negative?
      rate = Money.decimal(tax_rate) || Money.zero
      pretax, tax, _charged = if !taxable || tax_mode.to_s == "none" || rate.zero?
        [amount, Money.zero, amount]
      else
        tax_components(amount, rate, tax_mode)
      end
      if round_per.to_s == "line"
        pretax = Money.round(pretax, precision, rounding_mode)
        tax = Money.round(tax, precision, rounding_mode)
      end
      { pretax: pretax, tax: tax }
    end

    def assemble(parsed, shipping, currency, precision, rounding_mode)
      line_rows = parsed.map { |row| serialize_line(row, precision, rounding_mode) }
      subtotal = Money.round(parsed.reduce(Money.zero) { |sum, row| sum + row[:net] }, precision, rounding_mode)
      discount = Money.round(parsed.reduce(Money.zero) { |sum, row| sum + row[:discount] }, precision, rounding_mode)
      tax = Money.round(parsed.reduce(Money.zero) { |sum, row| sum + row[:tax] } + shipping[:tax], precision, rounding_mode)
      shipping_out = Money.round(shipping[:pretax], precision, rounding_mode)
      total = Money.round(subtotal + tax + shipping_out, precision, rounding_mode)

      {
        "lines" => line_rows,
        "subtotal" => Money.format_decimal(subtotal, precision),
        "discount" => Money.format_decimal(discount, precision),
        "tax" => Money.format_decimal(tax, precision),
        "shipping" => Money.format_decimal(shipping_out, precision),
        "total" => Money.format_decimal(total, precision),
        "currency" => currency.to_s
      }
    end

    def serialize_line(row, precision, rounding_mode)
      {
        "quantity" => Money.serialize(row[:quantity], precision, rounding_mode),
        "unit_price" => Money.serialize(row[:unit_price], precision, rounding_mode),
        "gross" => Money.serialize(row[:gross], precision, rounding_mode),
        "discount" => Money.serialize(row[:discount], precision, rounding_mode),
        "net" => Money.serialize(row[:net], precision, rounding_mode),
        "tax" => Money.serialize(row[:tax], precision, rounding_mode),
        "total" => Money.serialize(row[:total], precision, rounding_mode)
      }
    end
  end
end
