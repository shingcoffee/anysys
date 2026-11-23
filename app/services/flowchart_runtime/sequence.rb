# frozen_string_literal: true

module FlowchartRuntime
  # Tenant-scoped monotonic counter for next_sequence_number. last_value is the
  # allocation count (not the displayed number) so start_at/step stay column-free.
  # Increment is an UPDATE of last_value followed by a read, so a rolled-back run
  # returns the number. First use inserts on the unique (customer, name, period) index.
  module Sequence
    class Error < StandardError; end

    PERIODS = %w[never year month day week quarter].freeze
    DATE_SEGMENTS = %w[none year year_month date].freeze
    MIN_PADDING = 1
    MAX_PADDING = 12
    DEFAULT_PADDING = 6
    NEVER_PERIOD = "never"
    DEFAULT_START_AT = 1
    DEFAULT_STEP = 1
    DEFAULT_SEPARATOR = "-"

    module_function

    def next(ctx, name:, period:, prefix: "", padding: DEFAULT_PADDING, suffix: "",
             start_at: DEFAULT_START_AT, step: DEFAULT_STEP, date_segment: "none",
             separator: DEFAULT_SEPARATOR)
      customer_id = ctx && ctx[:customer_id]
      raise Error, "customer_id is required" if customer_id.blank?
      raise Error, "name is required" if name.to_s.strip.empty?

      bucket = period_key(period)
      origin = positive_int(start_at, DEFAULT_START_AT)
      stride = positive_int(step, DEFAULT_STEP)
      value = nil
      FlowchartSequence.transaction do
        row = FlowchartSequence.create_or_find_by!(customer_id: customer_id, name: name.to_s, period: bucket) do |seq|
          seq.last_value = 0
        end
        FlowchartSequence.where(id: row.id).update_all("last_value = last_value + 1")
        count = FlowchartSequence.where(id: row.id).pick(:last_value)
        value = origin + ((count.to_i - 1) * stride)
      end
      format_value(
        value,
        prefix: prefix,
        padding: padding,
        suffix: suffix,
        date_segment: date_segment,
        separator: separator
      )
    end

    def period_key(period)
      now = Time.current
      case period.to_s
      when "year" then now.strftime("%Y")
      when "month" then now.strftime("%Y-%m")
      when "day" then now.strftime("%Y-%m-%d")
      when "week" then now.strftime("%G-W%V")
      when "quarter" then "#{now.year}-Q#{((now.month - 1) / 3) + 1}"
      else NEVER_PERIOD
      end
    end

    def format_value(value, prefix:, padding:, suffix: "", date_segment: "none", separator: DEFAULT_SEPARATOR)
      width = Integer(padding, exception: false)
      width = DEFAULT_PADDING unless width&.between?(MIN_PADDING, MAX_PADDING)
      number = value.to_i.to_s.rjust(width, "0")
      segment = date_segment_text(date_segment)
      middle = segment ? "#{segment}#{separator}#{number}" : number
      "#{prefix}#{middle}#{suffix}"
    end

    def date_segment_text(segment)
      now = Time.current
      case segment.to_s
      when "year" then now.strftime("%Y")
      when "year_month" then now.strftime("%Y-%m")
      when "date" then now.strftime("%Y-%m-%d")
      end
    end

    def positive_int(value, fallback)
      number = Integer(value, exception: false)
      number&.positive? ? number : fallback
    end
    private_class_method :period_key, :format_value, :date_segment_text, :positive_int
  end
end
