# frozen_string_literal: true

require "digest"

module Sms
  module Campaigns
    class ReviewToken
      PURPOSE = "sms_campaign_review"
      LIFETIME = 15.minutes

      def self.binding(customer:, campaign:, template:, audience:, credential_id:, credential_mode:, provider:)
        { "customer_id" => customer.id, "campaign_id" => campaign.id,
          "lock_version" => campaign.status == "draft" ? campaign.lock_version : campaign.settings_snapshot["draft_lock_version"],
          "draft_digest" => digest(campaign.attributes.slice(*Contracts::Draft::FIELDS.map(&:to_s))),
          "template_digest" => digest(template.merge("provider" => provider)), "audience_digest" => digest(audience),
          "credential_id" => credential_id, "credential_mode" => credential_mode, "provider" => provider }
      end

      def self.issue(binding, at:)
        verifier.generate(binding.merge("valid_until" => Support.iso(at + LIFETIME)), purpose: PURPOSE, expires_at: at + LIFETIME)
      end

      def self.read(token, at:)
        payload = verifier.verified(token, purpose: PURPOSE) if token.is_a?(String) && token.bytesize <= 16.kilobytes
        return nil unless payload.is_a?(Hash) && Time.iso8601(payload.fetch("valid_until")) > at
        payload.except("valid_until")
      rescue KeyError, ArgumentError, TypeError
        nil
      end

      def self.digest(value)
        Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
      end

      def self.canonical(value)
        case value
        when Hash then value.stringify_keys.sort.to_h.transform_values { |item| canonical(item) }
        when Array then value.map { |item| canonical(item) }
        when Time, ActiveSupport::TimeWithZone then Support.iso(value)
        else value
        end
      end

      def self.verifier
        Rails.application.message_verifier(PURPOSE)
      end
    end
  end
end
