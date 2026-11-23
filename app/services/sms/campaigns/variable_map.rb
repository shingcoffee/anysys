# frozen_string_literal: true

module Sms
  module Campaigns
    class VariableMap
      FIELDS = %w[name phone_e164 country_code timezone unsubscribe_url].freeze
      PLACEHOLDER = /\{\{([a-zA-Z0-9_]+)\}\}/

      def self.valid?(map:, required_vars:, customer:, complete: false, frozen_fields: false)
        return false unless map.is_a?(Hash) && map.size <= SendStandards::MAX_VARIABLES
        return false unless map.keys.all? { |key| key.is_a?(String) && key.present? && key.bytesize <= 128 }
        return false if required_vars && (map.keys - required_vars).any?
        return false if complete && map.keys.sort != Array(required_vars).sort
        return false if JSON.generate(map).bytesize > 16.kilobytes

        catalog = Sms::Audience::FieldCatalog.new(customer: customer) unless frozen_fields
        map.all? do |_key, rule|
          next false unless rule.is_a?(Hash) && rule.keys.all? { |key| key.is_a?(String) }
          case rule["source"]
          when "literal"
            rule.keys.sort == %w[source value] && scalar?(rule["value"])
          when "field"
            (rule.keys - %w[source field fallback]).empty? && rule.key?("field") &&
              (FIELDS.include?(rule["field"]) || (rule["field"].is_a?(String) &&
                rule["field"].match?(/\Aattributes\.[a-z][a-z0-9_]{0,63}\z/) && (frozen_fields || catalog.resolve(rule["field"])))) &&
              (!rule.key?("fallback") || scalar?(rule["fallback"]))
          else false
          end
        end
      rescue JSON::GeneratorError, EncodingError
        false
      end

      def self.scalar?(value)
        SendStandards.vars_valid?({ "value" => value })
      end

      def self.resolve(map:, snapshot:, customer:, contact:)
        vars = map.to_h.transform_values do |rule|
          if rule["source"] == "literal"
            rule["value"]
          else
            field = rule["field"]
            value = if field == "unsubscribe_url"
              Unsubscribe.url_for(customer: customer, contact: contact, phone_e164: snapshot.fetch("phone_e164"))
            elsif field.start_with?("attributes.")
              snapshot.fetch("custom_attributes", {})[field.delete_prefix("attributes.")]
            else
              snapshot[field]
            end
            value = rule["fallback"] if value.nil? || (value.is_a?(String) && value.blank?)
            value == true || value == false ? value.to_s : value
          end
        end
        SendStandards.vars_valid?(vars) ? vars : nil
      end

      def self.render(body, vars)
        return nil if body.nil? || vars.nil?
        body.gsub(PLACEHOLDER) { vars.fetch(Regexp.last_match(1)).to_s }
      end

      def self.valid_body?(body, required)
        return true if body.nil?
        body.is_a?(String) && body.valid_encoding? && body.bytesize <= 4.kilobytes &&
          (body.scan(PLACEHOLDER).flatten - required).empty? &&
          !body.gsub(PLACEHOLDER, "").match?(/\{\{|\}\}/)
      end
    end
  end
end
