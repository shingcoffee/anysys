# frozen_string_literal: true

require "digest"
require "uri"

module Sms
  module Campaigns
    class Unsubscribe
      PURPOSE = "sms_marketing_unsubscribe"
      LIFETIME = 365.days

      def self.token_for(customer:, contact:, phone_e164:)
        unless Support.scoped?(customer, contact) && Sms::PhoneNumber.normalize(phone_e164) == phone_e164
          raise ArgumentError, I18n.t("sms_campaigns.errors.invalid_input")
        end
        verifier.generate({ "customer_id" => customer.id, "contact_id" => contact.id, "phone_e164" => phone_e164,
                            "expires_at" => Support.iso(Time.current + LIFETIME) },
                          purpose: PURPOSE, expires_in: LIFETIME)
      end

      def self.url_for(customer:, contact:, phone_e164:)
        token = token_for(customer: customer, contact: contact, phone_e164: phone_e164)
        options = Rails.application.config.x.canonical_url_options.presence || Rails.application.default_url_options
        canonical = CanonicalUrlOptions.validate(options, production: Rails.env.production?)
        URI::Generic.build(scheme: canonical.fetch(:protocol), host: canonical.fetch(:host), port: canonical[:port],
                           path: "/sms/unsubscribes/#{token}").to_s
      end

      def self.preview(token:, at: Time.current)
        resolved = resolve(token, at)
        return Support.failure(:not_found) unless resolved
        _customer, contact, phone = resolved
        Support.success(masked_phone: "#{phone[0, 3]}#{'•' * [phone.length - 5, 1].max}#{phone[-2, 2]}",
          already_unsubscribed: Sms::OptOut.opted_out?(customer_id: contact.customer_id, phone_e164: phone))
      end

      def self.call(token:, at: Time.current)
        resolved = resolve(token, at)
        return Support.failure(:not_found) unless resolved
        customer, contact, phone = resolved
        key = "unsubscribe:#{Digest::SHA256.hexdigest(token)}"
        Quota.synchronize(customer) do
          contact.lock!
          existing = Sms::ConsentEvent.find_by(customer_id: customer.id, event_key: key)
          next Support.success(already_unsubscribed: true) if existing
          already = Sms::OptOut.opted_out?(customer_id: customer.id, phone_e164: phone)
          recorded = Sms::Contacts::EvidenceWriter.call(customer: customer, contact: contact, phone_e164: phone, action: "revoked",
            source: "recipient_unsubscribe", occurred_at: at, actor_user_id: nil,
            evidence: { "token_digest" => Digest::SHA256.hexdigest(token) }, event_key: key)
          next recorded unless recorded.success?
          Support.success(already_unsubscribed: already)
        end
      end

      def self.resolve(token, at)
        return nil unless token.is_a?(String) && token.bytesize <= 8.kilobytes
        payload = verifier.verified(token, purpose: PURPOSE)
        return nil unless payload.is_a?(Hash) && payload["customer_id"].is_a?(Integer) && payload["contact_id"].is_a?(Integer) &&
          payload["phone_e164"].is_a?(String) && Sms::PhoneNumber.normalize(payload["phone_e164"]) == payload["phone_e164"] &&
          Time.iso8601(payload.fetch("expires_at")) > at
        contact = Sms::Contact.find_by(customer_id: payload["customer_id"], id: payload["contact_id"])
        customer = contact && Customer.find_by(id: payload["customer_id"])
        [customer, contact, payload["phone_e164"]] if customer
      rescue KeyError, ArgumentError, TypeError
        nil
      end
      private_class_method :resolve

      def self.verifier
        Rails.application.message_verifier(PURPOSE)
      end
    end
  end
end
