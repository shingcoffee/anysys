# frozen_string_literal: true

module Sms
  module Campaigns
    class Snapshot
      CONTACT_FIELDS = %w[name phone_e164 country_code timezone custom_attributes status consent_status consent_changed_at].freeze

      def self.contact(contact, eligibility: nil)
        result = contact.attributes.slice(*CONTACT_FIELDS)
        result["consent_changed_at"] = Support.iso(contact.consent_changed_at)
        result["eligibility_at_start"] = { "eligible" => eligibility[:eligible], "reason" => eligibility[:reason]&.to_s } if eligibility
        result
      end

      def self.template(template, credential)
        { "id" => template.id, "key" => template.key, "purpose" => template.purpose,
          "provider_code" => template.provider_code(credential.provider),
          "required_vars" => template.required_vars.map(&:to_s), "body_template" => template.body_template }
      end

      def self.audience(customer, segment)
        rules = segment&.segment_rules || {}
        identifiers = referenced_fields(rules)
        catalog = Sms::Audience::FieldCatalog.new(customer: customer)
        specs = identifiers.grep(/\Aattributes\./).sort.to_h do |field|
          entry = catalog.resolve(field)
          [field, entry && entry[:type].to_s]
        end
        { "schema_version" => 1, "kind" => segment ? "segment" : "all_contacts",
          "segment_id" => segment&.id, "segment_name" => segment&.name,
          "segment_rules" => rules.deep_dup, "field_specs" => specs }
      end

      def self.referenced_fields(node)
        return [] unless node.is_a?(Hash)
        return [node["field"]].compact if node.key?("field")
        Array(node["conditions"]).flat_map { |child| referenced_fields(child) }.uniq
      end

      def self.settings(campaign, template:, credential:, at:)
        start = Support.intended_start(campaign, at)
        campaign.attributes.slice(*%w[name send_timing timezone quiet_hours_start quiet_hours_end
          frequency_window_hours send_rate_per_minute deadline_hours variable_map]).merge(
          "schema_version" => 1, "draft_lock_version" => campaign.lock_version,
          "intended_start_at" => Support.iso(start), "expires_at" => Support.iso(start + campaign.deadline_hours.hours),
          "provider" => credential.provider, "credential_id" => credential.id, "credential_mode" => credential.mode,
          "account_rate_per_second_at_launch" => DispatchLimiter.rate_for(credential),
          "template" => self.template(template, credential)
        )
      end

      def self.valid?(campaign)
        settings = campaign.settings_snapshot
        audience = campaign.audience_snapshot
        return false unless settings.is_a?(Hash) && audience.is_a?(Hash) && settings["schema_version"] == 1 && audience["schema_version"] == 1
        template = settings["template"]
        return false unless template.is_a?(Hash) && template["purpose"] == "marketing" &&
          template["id"].is_a?(Integer) && SendStandards.template_key_valid?(template["key"]) &&
          template["provider_code"].is_a?(String) && template["provider_code"].present? &&
          template["required_vars"].is_a?(Array) && template["required_vars"].all? { |key| key.is_a?(String) } &&
          template["required_vars"].uniq == template["required_vars"] &&
          settings["variable_map"].is_a?(Hash) && settings["variable_map"].keys.sort == template["required_vars"].sort &&
          settings["credential_id"].is_a?(Integer) && Sms::Credential::MODES.include?(settings["credential_mode"]) &&
          settings["provider"].is_a?(String) && Schedule.valid_zone?(settings["timezone"])
        return false unless %w[quiet_hours_start quiet_hours_end].all? { |key| settings[key].is_a?(Integer) && settings[key].between?(0, 23) } &&
          settings["quiet_hours_start"] != settings["quiet_hours_end"] &&
          { "frequency_window_hours" => 1..168, "send_rate_per_minute" => 1..60, "deadline_hours" => 1..168 }.all? { |key, range| settings[key].is_a?(Integer) && range.cover?(settings[key]) }
        return false unless VariableMap.valid?(map: settings["variable_map"], required_vars: template["required_vars"],
          customer: nil, complete: true, frozen_fields: true) && VariableMap.valid_body?(template["body_template"], template["required_vars"])
        expiry = Time.iso8601(settings.fetch("expires_at"))
        start = Time.iso8601(settings.fetch("intended_start_at"))
        expiry == campaign.expires_at && expiry == start + settings["deadline_hours"].hours && campaign.launched_at.present? &&
          %w[all_contacts segment].include?(audience["kind"]) && audience["field_specs"].is_a?(Hash) &&
          audience["segment_rules"].is_a?(Hash)
      rescue ArgumentError, KeyError, TypeError
        false
      end
    end
  end
end
