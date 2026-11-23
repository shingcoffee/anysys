# frozen_string_literal: true

class MigrateFieldConfigurationsFormat < ActiveRecord::Migration[8.0]
  def up
    BaseModelConfiguration.find_each do |config|
      raw = config.field_configurations
      next if raw.blank?

      parsed = JSON.parse(raw)
      next if parsed.empty?

      # Skip if already in new format (first value is a Hash)
      sample_value = parsed.values.first
      next if sample_value.is_a?(Hash)

      # Convert old format {"field": "html_type"} to {"field": {"html_type": "...", "validators": []}}
      new_configs = parsed.transform_values do |html_type|
        { "html_type" => html_type.to_s, "validators" => [] }
      end

      config.update_column(:field_configurations, new_configs.to_json)
    rescue JSON::ParserError
      next
    end
  end

  def down
    BaseModelConfiguration.find_each do |config|
      raw = config.field_configurations
      next if raw.blank?

      parsed = JSON.parse(raw)
      next if parsed.empty?

      sample_value = parsed.values.first
      next unless sample_value.is_a?(Hash)

      old_configs = parsed.transform_values do |field_config|
        field_config["html_type"] || "text"
      end

      config.update_column(:field_configurations, old_configs.to_json)
    rescue JSON::ParserError
      next
    end
  end
end
