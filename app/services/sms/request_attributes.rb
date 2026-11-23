# frozen_string_literal: true

require "json"
require "tzinfo"

module Sms
  # HTTP-only normalization. Domain validation remains in the Reform contracts.
  class RequestAttributes
    MAX_BYTES = 64 * 1024
    INPUTS = {
      contact: %i[phone name country_code timezone status custom_attributes_json lock_version],
      consent_event: %i[action occurred_at reference statement notes event_key],
      entity_sync: %i[entity_id phone_field name_field country_code timezone attribute_map_json after_entry_id through_entry_id],
      segment: %i[name description segment_rules_json lock_version],
      campaign: %i[name template_id segment_id variable_map_json send_timing scheduled_local timezone quiet_hours_start quiet_hours_end frequency_window_hours send_rate_per_minute deadline_hours lock_version]
    }.freeze
    JSON_FIELDS = {
      custom_attributes_json: [:custom_attributes, 8 * 1024],
      segment_rules_json: [:segment_rules, 32 * 1024],
      variable_map_json: [:variable_map, 16 * 1024],
      attribute_map_json: [:attribute_map, 8 * 1024]
    }.freeze
    INTEGERS = %i[lock_version after_entry_id through_entry_id quiet_hours_start quiet_hours_end frequency_window_hours send_rate_per_minute deadline_hours].freeze
    IDS = %i[entity_id template_id segment_id preview_contact_id].freeze
    TRANSPORT_KEYS = %w[authenticity_token _method locale commit].freeze

    class Invalid < StandardError
      attr_reader :errors, :form_values, :code, :key

      def initialize(field, key, form_values: {}, code: :invalid_parameters)
        @errors = { field.to_sym => [I18n.t("sms_campaign_http.errors.#{key}")] }
        @form_values = form_values
        @code = code
        @key = key
        super(@errors.values.flatten.join(" "))
      end
    end

    attr_reader :form_values

    def self.check_body!(request)
      raise Invalid.new(:base, :payload_too_large) if request.content_length.to_i > MAX_BYTES

      input = request.body
      body = input.read(MAX_BYTES + 1).to_s
      input.rewind
      raise Invalid.new(:base, :payload_too_large) if body.bytesize > MAX_BYTES

      if request.media_type == "application/json" && body.present?
        value = JSON.parse(body, allow_duplicate_key: false, max_nesting: 32)
        raise Invalid.new(:base, :object_required) unless value.is_a?(Hash)
      end
    rescue JSON::ParserError, EncodingError
      raise Invalid.new(:base, :invalid_json)
    end

    def self.integer(value, field:, optional: false, minimum: 0)
      return nil if optional && (value.nil? || value == "")
      valid = value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d{1,19}\z/))
      raise Invalid.new(field, :integer_required) unless valid

      number = Integer(value, 10) if value.is_a?(String)
      number ||= value
      raise Invalid.new(field, :integer_required) unless number.between?(minimum, 9_223_372_036_854_775_807)

      number
    end

    def self.action_inputs(request, allowed:)
      raw = request.query_parameters.merge(request.request_parameters).stringify_keys
      reject_unknown!(raw, allowed.map(&:to_s))
      raw.slice(*allowed.map(&:to_s)).symbolize_keys
    end

    def self.reject_unknown!(raw, allowed)
      raise Invalid.new(:base, :unknown_parameters) if (raw.keys - allowed - TRANSPORT_KEYS).any?
    end

    def initialize(request:, kind:, timezone: "Asia/Shanghai", extras: [])
      @request, @kind, @timezone, @extras = request, kind, timezone, extras
      @form_values = {}
    end

    def call
      root = "sms_#{@kind}"
      supplied = @request.query_parameters.merge(@request.request_parameters)[root]
      permitted = INPUTS.fetch(@kind)
      @form_values = supplied.slice(*permitted.map(&:to_s)).symbolize_keys if supplied.is_a?(Hash)
      raw = self.class.action_inputs(@request, allowed: [root.to_sym, *@extras])
      supplied = raw[root.to_sym]
      raise Invalid.new(:base, :object_required) unless supplied.is_a?(Hash)

      raise Invalid.new(:base, :unknown_parameters) if (supplied.keys.map(&:to_sym) - permitted).any?

      attributes = @form_values.each_with_object({}) do |(field, value), result|
        if (json = JSON_FIELDS[field])
          result[json.first] = parse_object(value, field, json.last)
        elsif IDS.include?(field)
          result[field] = self.class.integer(value, field: field, optional: field != :entity_id, minimum: 1)
        elsif INTEGERS.include?(field)
          result[field] = self.class.integer(value, field: field, optional: field == :through_entry_id)
        else
          raise Invalid.new(field, :string_required) unless value.nil? || (value.is_a?(String) && value.valid_encoding?)

          result[field] = value
        end
      end
      normalize_schedule!(attributes) if @kind == :campaign
      normalize_consent!(attributes) if @kind == :consent_event
      attributes
    rescue Invalid => error
      raise Invalid.new(error.errors.keys.first, error.key, form_values: @form_values, code: error.code)
    end

    private

    def parse_object(raw, field, limit)
      raise Invalid.new(field, :string_required) unless raw.is_a?(String) && raw.valid_encoding?
      raise Invalid.new(field, :json_too_large) if raw.bytesize > limit

      parsed = JSON.parse(raw, allow_duplicate_key: false, max_nesting: 16)
      raise Invalid.new(field, :object_required) unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError, EncodingError
      raise Invalid.new(field, :invalid_json)
    end

    def normalize_schedule!(attributes)
      return unless attributes.key?(:scheduled_local)

      local = attributes.delete(:scheduled_local)
      if local.nil? || local == ""
        attributes[:scheduled_at] = nil
        return
      end
      raise Invalid.new(:scheduled_local, :invalid_schedule) unless local.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/)

      date = DateTime.strptime(local, "%Y-%m-%dT%H:%M")
      wall = Time.utc(date.year, date.month, date.day, date.hour, date.minute)
      zone = TZInfo::Timezone.get(attributes.fetch(:timezone, @timezone))
      periods = zone.periods_for_local(wall)
      raise Invalid.new(:scheduled_local, :invalid_schedule) unless periods.one?

      attributes[:scheduled_at] = (wall - periods.first.utc_total_offset).utc
    rescue ArgumentError, TypeError, TZInfo::InvalidTimezoneIdentifier
      raise Invalid.new(:scheduled_local, :invalid_schedule)
    end

    def normalize_consent!(attributes)
      value = attributes[:occurred_at]
      unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})\z/)
        raise Invalid.new(:occurred_at, :offset_required)
      end
      # Time.iso8601 normalizes invalid calendar dates/hours; DateTime rejects
      # those, while Time additionally validates the explicit UTC offset.
      DateTime.iso8601(value)
      attributes[:occurred_at] = Time.iso8601(value).utc
    rescue ArgumentError
      raise Invalid.new(:occurred_at, :offset_required)
    end
  end
end
