# frozen_string_literal: true

module FlowchartRuntime
  # Repayment / subscription / instalment schedules.
  module Installments
    class Error < StandardError; end

    METHODS = %w[annuity equal_principal interest_only flat].freeze
    FREQUENCIES = {
      "monthly" => { months: 1, divisor: 12 },
      "quarterly" => { months: 3, divisor: 4 },
      "semiannual" => { months: 6, divisor: 2 },
      "annual" => { months: 12, divisor: 1 },
      "weekly" => { days: 7, divisor: 52 },
      "biweekly" => { days: 14, divisor: 26 }
    }.freeze
    ROUNDING_MODES = Money::ROUNDING.keys.freeze
    PERIODS = (1..600)

    module_function

    def build(ctx, principal:, annual_rate: 0, rate_override: nil, periods: 12,
              frequency: "monthly", method: "annuity", start_date: nil,
              first_payment_offset: 1, down_payment: 0, precision: 2,
              rounding_mode: "half_up", final_payment_adjust: true)
      raise Error, "unsupported method" unless METHODS.include?(method.to_s)
      raise Error, "unsupported frequency" unless FREQUENCIES.key?(frequency.to_s)
      raise Error, "unsupported rounding" unless ROUNDING_MODES.include?(rounding_mode.to_s)

      head = Money.decimal(principal)
      return Step.fail(ctx, :"build_installment_plan.invalid_principal") if head.nil? || head.negative? || head.zero?

      down = Money.decimal(down_payment) || Money.zero
      down = Money.zero if down.negative?
      financed = head - down
      return Step.fail(ctx, :"build_installment_plan.down_payment_exceeds_principal") if financed <= 0

      rate = Money.decimal(rate_override.nil? ? annual_rate : rate_override) || Money.zero
      rate = Money.zero if rate.negative?
      count = Integer(periods, exception: false)
      unless count && PERIODS.cover?(count)
        return Step.fail(ctx, :"build_installment_plan.invalid_periods", max: PERIODS.max)
      end

      origin = parse_date(start_date)
      return Step.fail(ctx, :"build_installment_plan.invalid_start_date") if origin.nil?

      spec = FREQUENCIES.fetch(frequency.to_s)
      period_rate = rate / BigDecimal("100") / BigDecimal(spec[:divisor])
      rows = schedule_rows(method.to_s, financed, period_rate, count, rate, spec[:divisor],
                           precision, rounding_mode, final_payment_adjust)
      rows.each_with_index do |row, index|
        row[:due_date] = advance(origin, frequency, first_payment_offset.to_i + index)
      end
      serialize_plan(rows, precision, rounding_mode)
    end

    # Blank means today; anything unparseable is nil so the step fails instead of guessing.
    def parse_date(value)
      case value
      when Date then value
      when Time, DateTime, ActiveSupport::TimeWithZone then value.to_date
      when nil, "" then Time.zone.today
      when String then Date.iso8601(value.strip)
      end
    rescue Date::Error, ArgumentError, TypeError
      nil
    end

    def advance(date, frequency, periods)
      spec = FREQUENCIES.fetch(frequency.to_s)
      count = periods.to_i
      if spec[:months]
        date >> (spec[:months] * count)
      else
        date + (spec[:days] * count)
      end
    end

    def schedule_rows(method, financed, period_rate, count, annual_percent, divisor,
                      precision, rounding_mode, adjust)
      case method
      when "annuity"
        annuity_rows(financed, period_rate, count, precision, rounding_mode, adjust)
      when "equal_principal"
        equal_principal_rows(financed, period_rate, count, precision, rounding_mode, adjust)
      when "interest_only"
        interest_only_rows(financed, period_rate, count, precision, rounding_mode, adjust)
      else
        flat_rows(financed, annual_percent, count, divisor, precision, rounding_mode, adjust)
      end
    end

    def annuity_rows(financed, period_rate, count, precision, rounding_mode, adjust)
      payment = annuity_payment(financed, period_rate, count, precision, rounding_mode)
      walk_balance(financed, count, precision, rounding_mode, adjust) do |balance, _last|
        interest = Money.round(balance * period_rate, precision, rounding_mode)
        principal = clamp_principal(payment - interest, balance)
        [principal + interest, principal, interest]
      end
    end

    def equal_principal_rows(financed, period_rate, count, precision, rounding_mode, adjust)
      base = Money.round(financed / count, precision, rounding_mode)
      walk_balance(financed, count, precision, rounding_mode, adjust) do |balance, _last|
        interest = Money.round(balance * period_rate, precision, rounding_mode)
        principal = clamp_principal(base, balance)
        [principal + interest, principal, interest]
      end
    end

    def interest_only_rows(financed, period_rate, count, precision, rounding_mode, adjust)
      walk_balance(financed, count, precision, rounding_mode, adjust) do |balance, last|
        interest = Money.round(balance * period_rate, precision, rounding_mode)
        principal = last ? balance : Money.zero
        [principal + interest, principal, interest]
      end
    end

    def flat_rows(financed, annual_percent, count, divisor, precision, rounding_mode, adjust)
      years = BigDecimal(count) / BigDecimal(divisor)
      total_interest = financed * (annual_percent / BigDecimal("100")) * years
      interest_part = Money.round(total_interest / count, precision, rounding_mode)
      principal_part = Money.round(financed / count, precision, rounding_mode)
      interest_remaining = Money.round(total_interest, precision, rounding_mode)
      walk_balance(financed, count, precision, rounding_mode, adjust) do |balance, last|
        principal = clamp_principal(principal_part, balance)
        interest = last ? interest_remaining : interest_part
        interest_remaining -= interest unless last
        [principal + interest, principal, interest]
      end
    end

    def annuity_payment(financed, period_rate, count, precision, rounding_mode)
      return Money.round(financed / count, precision, rounding_mode) if period_rate.zero?

      factor = (1 + period_rate)**count
      Money.round(financed * period_rate * factor / (factor - 1), precision, rounding_mode)
    end

    def walk_balance(financed, count, precision, rounding_mode, adjust)
      balance = financed
      (1..count).map do |number|
        last = number == count
        payment, principal, interest = yield(balance, last)
        if last && adjust
          principal = balance
          payment = principal + interest
          balance = Money.zero
        else
          balance -= principal
        end
        {
          number: number,
          payment: Money.round(payment, precision, rounding_mode),
          principal: Money.round(principal, precision, rounding_mode),
          interest: Money.round(interest, precision, rounding_mode),
          balance: Money.round(balance, precision, rounding_mode)
        }
      end
    end

    def clamp_principal(value, balance)
      return Money.zero if value.negative?
      return balance if value > balance

      value
    end

    def serialize_plan(rows, precision, rounding_mode)
      schedule = rows.map do |row|
        {
          "number" => row[:number],
          "due_date" => row[:due_date].iso8601,
          "payment" => Money.format_decimal(row[:payment], precision),
          "principal" => Money.format_decimal(row[:principal], precision),
          "interest" => Money.format_decimal(row[:interest], precision),
          "balance" => Money.format_decimal(row[:balance], precision)
        }
      end
      totals = {
        "payment" => Money.serialize(rows.reduce(Money.zero) { |sum, row| sum + row[:payment] }, precision, rounding_mode),
        "principal" => Money.serialize(rows.reduce(Money.zero) { |sum, row| sum + row[:principal] }, precision, rounding_mode),
        "interest" => Money.serialize(rows.reduce(Money.zero) { |sum, row| sum + row[:interest] }, precision, rounding_mode)
      }
      { "schedule" => schedule, "totals" => totals }
    end
  end
end
