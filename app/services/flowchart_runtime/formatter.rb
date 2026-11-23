# frozen_string_literal: true

require "phonelib"

module FlowchartRuntime
  # Locale-aware display formatting for the format_value step.
  module Formatter
    class Error < StandardError; end

    FORMAT_TYPES = %w[
      number currency percentage delimited human_size human_number phone date datetime
    ].freeze
    PHONE_STYLES = %w[international national e164].freeze
    DATE_STYLES = %w[default short long iso8601 custom].freeze
    NUMERIC_TYPES = %w[number currency percentage delimited human_size human_number].freeze

    module_function

    def apply(value, ctx: {}, format_type: "number", locale: "", precision: 2,
              currency_unit: "", delimiter: "", separator: "", strip_insignificant_zeros: false,
              phone_country: "", phone_style: "international", date_style: "default",
              custom_format: "", timezone: "", fallback_value: "")
      type = format_type.to_s
      raise Error, "unsupported format" unless FORMAT_TYPES.include?(type)

      return fallback_value.to_s if value.nil?

      locale_name = locale.to_s.presence || ctx[:locale].presence || I18n.locale
      I18n.with_locale(locale_name) do
        formatted = format_value(
          value, type,
          precision: precision, currency_unit: currency_unit,
          delimiter: delimiter, separator: separator,
          strip_insignificant_zeros: strip_insignificant_zeros,
          phone_country: phone_country, phone_style: phone_style,
          date_style: date_style, custom_format: custom_format, timezone: timezone
        )
        formatted.nil? ? fallback_value.to_s : formatted
      end
    rescue ArgumentError, TypeError, TZInfo::InvalidTimezoneIdentifier => error
      raise Error, error.message
    end

    def format_value(value, type, **opts)
      case type
      when "number" then number_with_precision(value, opts)
      when "currency" then currency(value, opts)
      when "percentage" then percentage(value, opts)
      when "delimited" then delimited(value, opts)
      when "human_size" then human_size(value, opts)
      when "human_number" then human_number(value, opts)
      when "phone" then phone(value, opts[:phone_country], opts[:phone_style])
      when "date" then date(value, opts[:date_style], opts[:custom_format])
      when "datetime" then datetime(value, opts[:date_style], opts[:custom_format], opts[:timezone])
      end
    end
    private_class_method :format_value

    def number_options(opts, extra = {})
      extra.merge(
        precision: opts[:precision].to_i,
        strip_insignificant_zeros: opts[:strip_insignificant_zeros],
        delimiter: opts[:delimiter].to_s.empty? ? I18n.t("number.format.delimiter") : opts[:delimiter],
        separator: opts[:separator].to_s.empty? ? I18n.t("number.format.separator") : opts[:separator]
      )
    end
    private_class_method :number_options

    def number_with_precision(value, opts)
      ActiveSupport::NumberHelper.number_to_rounded(to_number(value), **number_options(opts))
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :number_with_precision

    def currency(value, opts)
      extra = {}
      extra[:unit] = opts[:currency_unit] if opts[:currency_unit].to_s != ""
      ActiveSupport::NumberHelper.number_to_currency(to_number(value), **number_options(opts, extra))
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :currency

    def percentage(value, opts)
      ActiveSupport::NumberHelper.number_to_percentage(to_number(value), **number_options(opts))
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :percentage

    def delimited(value, opts)
      ActiveSupport::NumberHelper.number_to_delimited(
        to_number(value),
        delimiter: opts[:delimiter].to_s.empty? ? I18n.t("number.format.delimiter") : opts[:delimiter],
        separator: opts[:separator].to_s.empty? ? I18n.t("number.format.separator") : opts[:separator]
      )
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :delimited

    def human_size(value, opts)
      ActiveSupport::NumberHelper.number_to_human_size(
        to_number(value),
        precision: opts[:precision].to_i,
        strip_insignificant_zeros: opts[:strip_insignificant_zeros]
      )
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :human_size

    def human_number(value, opts)
      ActiveSupport::NumberHelper.number_to_human(
        to_number(value),
        precision: opts[:precision].to_i,
        strip_insignificant_zeros: opts[:strip_insignificant_zeros]
      )
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :human_number

    def phone(value, country, style)
      parsed = Phonelib.parse(value.to_s, country.to_s.presence)
      return nil unless parsed.valid?

      case style.to_s
      when "national" then parsed.national
      when "e164" then parsed.e164
      else parsed.international
      end
    end
    private_class_method :phone

    def date(value, style, custom_format)
      parsed = coerce_date(value)
      return nil unless parsed

      format_time_like(parsed, style, custom_format)
    end
    private_class_method :date

    def datetime(value, style, custom_format, timezone)
      parsed = coerce_time(value, timezone)
      return nil unless parsed

      format_time_like(parsed, style, custom_format)
    end
    private_class_method :datetime

    def format_time_like(value, style, custom_format)
      case style.to_s
      when "iso8601" then value.iso8601
      when "custom"
        format = custom_format.to_s
        return nil if format.empty?

        value.strftime(format)
      when "short" then I18n.l(value, format: :short)
      when "long" then I18n.l(value, format: :long)
      else I18n.l(value, format: :default)
      end
    end
    private_class_method :format_time_like

    def to_number(value)
      return value if value.is_a?(Numeric)

      BigDecimal(value.to_s)
    end
    private_class_method :to_number

    def coerce_date(value)
      return value.to_date if value.respond_to?(:to_date)

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError, Date::Error
      nil
    end
    private_class_method :coerce_date

    def coerce_time(value, timezone)
      zone = timezone.to_s.presence
      time = if value.respond_to?(:in_time_zone)
        value
      else
        Time.zone.parse(value.to_s)
      end
      return nil unless time

      zone ? time.in_time_zone(zone) : time.in_time_zone
    rescue ArgumentError, TypeError, TZInfo::InvalidTimezoneIdentifier
      nil
    end
    private_class_method :coerce_time
  end
end
