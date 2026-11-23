# frozen_string_literal: true

module Pages
  class FormulaEvaluator
    # Coercion and comparison helpers shared between the binary evaluator and
    # the built-in function library. Included as private instance methods on
    # FormulaEvaluator so existing call-sites (including specs that use #send)
    # need no changes.
    module CoercionHelpers
      private

      def num(value)
        case value
        when Numeric then value.to_f
        when true    then 1.0
        when false, nil then 0.0
        else
          begin
            Float(value.to_s)
          rescue ArgumentError, TypeError
            0.0
          end
        end
      end

      # JS truthiness: false, 0, "" and nil are falsey ("0" string is truthy).
      def truthy?(value)
        return false if value.nil? || value == false
        return false if value.is_a?(Numeric) && value.zero?
        return false if value == ""

        true
      end

      # JS loose equality (==) for our value domain (strings / numbers).
      def loose_eq(a, b)
        return true if a == b
        return true if a.to_s == b.to_s

        numeric_string?(a) && numeric_string?(b) && a.to_f == b.to_f
      end

      def numeric_string?(value)
        return true if value.is_a?(Numeric)

        Float(value.to_s)
        true
      rescue ArgumentError, TypeError
        false
      end

      def stringify(value)
        return "" if value.nil?
        return (value == value.to_i ? value.to_i.to_s : value.to_s) if value.is_a?(Float)

        value.to_s
      end

      def right_str(str, n)
        return "" if n <= 0

        str[[str.length - n, 0].max..] || ""
      end

      def switch(value, cases)
        i = 0
        while i < cases.length - 1
          return cases[i + 1] if loose_eq(value, cases[i])

          i += 2
        end
        cases.length.odd? ? cases.last : nil
      end

      def to_date(value)
        return value if value.is_a?(Date)
        return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def date_diff(d1, d2, unit)
        a = to_date(d1)
        b = to_date(d2)
        return nil unless a && b

        case unit.to_s
        when "months" then (a.year - b.year) * 12 + (a.month - b.month)
        when "years"  then a.year - b.year
        else (a - b).to_i # days
        end
      end

      def date_add(date, amount, unit)
        d = to_date(date)
        return nil unless d

        case unit.to_s
        when "months" then d >> amount
        when "years"  then d >> (amount * 12)
        else d + amount # days
        end
      end
    end
  end
end
