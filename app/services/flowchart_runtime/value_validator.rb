# frozen_string_literal: true

require "ipaddr"
require "phonelib"
require "addressable/uri"

module FlowchartRuntime
  # Business-format checks for the validate_value step.
  module ValueValidator
    class Error < StandardError; end

    RULES = %w[
      email phone cn_mobile url uuid regex length range in_list luhn iban
      cn_resident_id postal_code ip_address date date_range required
    ].freeze

    IP_VERSIONS = %w[any v4 v6].freeze
    UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
    CN_WEIGHTS = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2].freeze
    CN_CHECK = %w[1 0 X 9 8 7 6 5 4 3 2].freeze
    POSTAL_PATTERNS = {
      "US" => /\A\d{5}(?:-\d{4})?\z/,
      "CN" => /\A\d{6}\z/,
      "GB" => /\A[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\z/i,
      "CA" => /\A[A-Z]\d[A-Z]\s*\d[A-Z]\d\z/i,
      "DE" => /\A\d{5}\z/,
      "FR" => /\A\d{5}\z/,
      "JP" => /\A\d{3}-?\d{4}\z/,
      "AU" => /\A\d{4}\z/,
      "NL" => /\A\d{4}\s*[A-Z]{2}\z/i,
      "IN" => /\A\d{6}\z/,
      "BR" => /\A\d{5}-?\d{3}\z/,
      "IT" => /\A\d{5}\z/,
      "ES" => /\A\d{5}\z/,
      "KR" => /\A\d{5}\z/,
      "SG" => /\A\d{6}\z/
    }.freeze

    module_function

    def supported_postal_country?(code)
      POSTAL_PATTERNS.key?(code.to_s.upcase)
    end

    def valid_phone_country?(code)
      text = code.to_s
      return true if text.empty?

      text.match?(/\A[A-Z]{2}\z/) && Phonelib.phone_data.key?(text)
    end

    def check(value, rule:, phone_country: "", pattern: "", min_length: 1, max_length: 255,
              min_value: nil, max_value: nil, allowed_values: [], case_sensitive: true,
              postal_country: "US", url_schemes: %w[https http], date_format: "%Y-%m-%d",
              ip_version: "any", allow_blank: false, min_date: "", max_date: "",
              error_field: "", message: nil)
      rule_name = rule.to_s
      raise Error, "unsupported rule" unless RULES.include?(rule_name)

      if blank?(value)
        return result(false, nil) if rule_name == "required"
        return result(allow_blank, allow_blank ? "" : nil)
      end
      return result(true, value.to_s) if rule_name == "required"

      ok, normalized = validate_rule(
        value, rule_name,
        phone_country: phone_country, pattern: pattern,
        min_length: min_length, max_length: max_length,
        min_value: min_value, max_value: max_value,
        allowed_values: allowed_values, case_sensitive: case_sensitive,
        postal_country: postal_country, url_schemes: url_schemes,
        date_format: date_format, ip_version: ip_version,
        min_date: min_date, max_date: max_date
      )
      result(ok, ok ? normalized : nil)
    end

    def result(valid, normalized)
      { valid: valid, normalized: normalized }
    end
    private_class_method :result

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?) || value.to_s.strip.empty?
    end
    private_class_method :blank?

    def validate_rule(value, rule, **opts)
      case rule
      when "email" then email(value)
      when "phone" then phone(value, opts[:phone_country])
      when "cn_mobile" then cn_mobile(value)
      when "url" then url(value, opts[:url_schemes])
      when "uuid" then uuid(value)
      when "regex" then regex_match(value, opts[:pattern])
      when "length" then length_in(value, opts[:min_length], opts[:max_length])
      when "range" then range_in(value, opts[:min_value], opts[:max_value])
      when "in_list" then in_list(value, opts[:allowed_values], opts[:case_sensitive])
      when "luhn" then luhn(value)
      when "iban" then iban(value)
      when "cn_resident_id" then cn_resident_id(value)
      when "postal_code" then postal_code(value, opts[:postal_country])
      when "ip_address" then ip_address(value, opts[:ip_version])
      when "date" then date_value(value, opts[:date_format])
      when "date_range" then date_range(value, opts[:min_date], opts[:max_date], opts[:date_format])
      end
    end
    private_class_method :validate_rule

    def email(value)
      text = value.to_s.strip
      [URI::MailTo::EMAIL_REGEXP.match?(text), text.downcase]
    end
    private_class_method :email

    def phone(value, country)
      text = value.to_s.strip
      parsed = Phonelib.parse(text, country.to_s.presence)
      ok = parsed.valid? && parsed.extension.to_s.empty?
      ok &&= text.start_with?("+", "00") if country.to_s.empty?
      [ok, ok ? parsed.e164 : nil]
    end
    private_class_method :phone

    def cn_mobile(value)
      text = value.to_s.strip
      parsed = Phonelib.parse(text, "CN")
      ok = parsed.valid? && parsed.types.include?(:mobile) && parsed.extension.to_s.empty?
      [ok, ok ? parsed.e164 : nil]
    end
    private_class_method :cn_mobile

    def url(value, schemes)
      uri = Addressable::URI.parse(value.to_s.strip)
      allowed = Array(schemes).map { |item| item.to_s.downcase }
      ok = uri&.scheme.present? && uri.host.present? && allowed.include?(uri.scheme.downcase)
      [ok, ok ? uri.normalize.to_s : nil]
    rescue Addressable::URI::InvalidURIError, TypeError
      [false, nil]
    end
    private_class_method :url

    def uuid(value)
      text = value.to_s.strip
      [UUID_RE.match?(text), text.downcase]
    end
    private_class_method :uuid

    def regex_match(value, pattern)
      [Regex.apply(value, pattern: pattern, operation: "test"), value.to_s]
    end
    private_class_method :regex_match

    def length_in(value, min_length, max_length)
      size = value.to_s.length
      min = min_length.nil? ? 0 : min_length.to_i
      max = max_length.nil? ? size : max_length.to_i
      [size.between?(min, max), value.to_s]
    end
    private_class_method :length_in

    def range_in(value, min_value, max_value)
      number = Float(value)
      ok = (min_value.nil? || number >= min_value.to_f) && (max_value.nil? || number <= max_value.to_f)
      [ok, number]
    rescue ArgumentError, TypeError
      [false, nil]
    end
    private_class_method :range_in

    def in_list(value, allowed, case_sensitive)
      items = Array(allowed).map(&:to_s)
      text = value.to_s
      ok = if case_sensitive
        items.include?(text)
      else
        items.map(&:downcase).include?(text.downcase)
      end
      [ok, text]
    end
    private_class_method :in_list

    def luhn(value)
      digits = value.to_s.gsub(/\D/, "")
      return [false, nil] if digits.empty?

      sum = digits.reverse.chars.each_with_index.sum do |char, index|
        n = char.to_i
        n *= 2 if index.odd?
        n > 9 ? n - 9 : n
      end
      [(sum % 10).zero?, digits]
    end
    private_class_method :luhn

    def iban(value)
      parsed = Ibandit::IBAN.new(value.to_s)
      parsed.valid? ? [true, parsed.iban] : [false, nil]
    end
    private_class_method :iban

    def cn_resident_id(value)
      text = value.to_s.upcase
      return [false, nil] unless text.match?(/\A\d{17}[\dX]\z/)

      sum = CN_WEIGHTS.each_with_index.sum { |weight, index| text[index].to_i * weight }
      [CN_CHECK[sum % 11] == text[17], text]
    end
    private_class_method :cn_resident_id

    def postal_code(value, country)
      pattern = POSTAL_PATTERNS[country.to_s.upcase]
      return [false, nil] unless pattern

      text = value.to_s.strip
      [pattern.match?(text), text]
    end
    private_class_method :postal_code

    def ip_address(value, version)
      addr = IPAddr.new(value.to_s.strip)
      ok = case version.to_s
      when "v4" then addr.ipv4?
      when "v6" then addr.ipv6?
      else true
      end
      [ok, addr.to_s]
    rescue IPAddr::Error, ArgumentError
      [false, nil]
    end
    private_class_method :ip_address

    def date_value(value, format)
      parsed = Date.strptime(value.to_s.strip, format.to_s.presence || "%Y-%m-%d")
      [true, parsed.iso8601]
    rescue Date::Error, ArgumentError, TypeError
      [false, nil]
    end
    private_class_method :date_value

    def date_range(value, min_date, max_date, format)
      ok, iso = date_value(value, format)
      return [false, nil] unless ok

      date = Date.iso8601(iso)
      lo = parse_date_bound(min_date)
      hi = parse_date_bound(max_date)
      in_range = (lo.nil? || date >= lo) && (hi.nil? || date <= hi)
      [in_range, in_range ? iso : nil]
    end
    private_class_method :date_range

    def parse_date_bound(value)
      text = value.to_s.strip
      return nil if text.empty?
      return Date.current if text.casecmp("today").zero?
      return Date.current + 1 if text.casecmp("tomorrow").zero?

      Date.iso8601(text)
    rescue Date::Error, ArgumentError
      begin
        Date.parse(text)
      rescue Date::Error, ArgumentError, TypeError
        raise Error, "invalid date bound"
      end
    end
    private_class_method :parse_date_bound
  end
end
