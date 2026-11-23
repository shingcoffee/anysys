# frozen_string_literal: true

module Emails
  module SendActivities
    # Generates and verifies signed one-click unsubscribe tokens for campaign mail.
    # Uses Rails MessageVerifier so the token is tamper-proof without a DB lookup.
    # Unsubscribing records a tenant-scoped suppression that campaign delivery honors.
    class SendActivityUnsubscribe
      PURPOSE = "campaign_unsubscribe"

      def self.verifier
        Rails.application.message_verifier(PURPOSE)
      end

      def self.token_for(user, email: user.email, customer_id: user.customer_id)
        token_for_recipient(user_id: user.id, email: email, customer_id: customer_id)
      end

      def self.token_for_recipient(user_id:, email:, customer_id:)
        verifier.generate(
          { "user_id" => user_id, "email" => Emails::Suppression.normalize(email), "customer_id" => customer_id },
          purpose: PURPOSE
        )
      end

      # Absolute unsubscribe URL for a user — used both inside rendered bodies
      # ({{unsubscribe_url}}) and for the RFC 8058 List-Unsubscribe header.
      # Uses the real path-segment route (`/unsubscribe/:token`); the signed
      # token is URL-safe base64, so it is valid in a path segment.
      def self.url_for(user, email: user.email, customer_id: user.customer_id)
        url_for_token(token_for(user, email: email, customer_id: customer_id))
      end

      # The ledger's envelope is immutable; never re-read the profile address
      # or tenant while constructing a queued message's unsubscribe headers.
      def self.url_for_message(message)
        user_id = message.metadata&.dig("user_id")
        return nil if user_id.blank?

        url_for_token(token_for_recipient(user_id: user_id, email: message.to, customer_id: message.customer_id))
      end

      def self.url_for_token(token)
        options = (ActionMailer::Base.default_url_options || {}).symbolize_keys
        options[:host] ||= "localhost"
        Rails.application.routes.url_helpers.email_unsubscribe_url(**options.merge(token: token))
      end
      private_class_method :url_for_token

      def self.find_user(token)
        resolve(token)&.user
      end

      # Address the campaign was sent to — the token's email, not a later
      # profile change. Confirm/success pages must show this same address.
      def self.emailed_address(token)
        resolve(token)&.email
      end

      def self.unsubscribe(token)
        resolved = resolve(token)
        return nil unless resolved

        Emails::Suppression.record_for_customer!(
          customer_id: resolved.customer_id, email: resolved.email, reason: "unsubscribe"
        )
        resolved.user
      end

      Resolved = Struct.new(:user, :email, :customer_id, keyword_init: true)

      def self.resolve(token)
        payload = decode(token)
        return nil unless payload

        user = Authentication::User.find_by(id: payload["user_id"])
        return nil unless user

        email = payload["email"]
        customer_id = payload["customer_id"]
        return nil unless email.is_a?(String) && email.present? && customer_id.present?

        Resolved.new(user: user, email: email, customer_id: customer_id)
      end
      private_class_method :resolve

      def self.decode(token)
        payload = verifier.verify(token.to_s, purpose: PURPOSE)
        payload.is_a?(Hash) ? payload.stringify_keys : nil
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end
      private_class_method :decode

      # Removes only the user's tenant-scoped unsubscribe suppression.
      def self.resubscribe(user)
        Emails::Suppression.where(
          customer_id: user.customer_id,
          email:       Emails::Suppression.normalize(user.email),
          reason:      "unsubscribe"
        ).delete_all
        user
      end
    end
  end
end
