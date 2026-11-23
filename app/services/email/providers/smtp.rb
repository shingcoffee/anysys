# frozen_string_literal: true

require_relative "../providers"

module Email
  module Providers
    # SMTP delivery via ActionMailer (Emails::DeliveryMailer). This is the
    # self-hosted MTA vendor: talk SMTP to Postfix/Exim/OpenSMTPD (or any SMTP
    # relay). It keeps the credential's typed SMTP columns (host, port, username,
    # auth, ssl, starttls, domain) + gem-based DKIM signing via the interceptor.
    # `:none` delivery mechanism — SMTP gives no async delivery receipt, so
    # status stops at `sent`.
    class Smtp < Base
      class << self
        def key                  = "smtp"
        def default_display_name = "SMTP"
        def delivery_mechanism   = :none

        # SMTP uses typed columns rather than the JSON config blob.
        def config_fields = []

        def configured?(credential)
          credential.host.present? && credential.username.present? && credential.password.present?
        end
      end

      register!
      default!

      # Delivers synchronously within Emails::DeliverMessageJob (deliver_now), so
      # a raise propagates to the job which owns status + retries. Returns no
      # provider message id (SMTP has none).
      def deliver(message:)
        Emails::DeliveryMailer.with(message_id: message.id, mode: credential.mode, credential_id: credential.id)
                              .deliver_email.deliver_now
        { provider_message_id: nil, raw: {} }
      end
    end
  end
end
