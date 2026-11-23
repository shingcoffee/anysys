# frozen_string_literal: true

module Emails
  # ActionMailer delivery interceptor: signs outgoing Email-module mail with
  # DKIM before it hits the transport. Scoped by the X-Anysys-Mode header so it
  # never touches BillingMailer / Devise / other app mail. Signing itself stays
  # in Email::DkimSigner (the `dkim`-gem wrapper); this only resolves the right
  # per-mode credential and invokes it.
  class DkimInterceptor
    def self.delivering_email(mail)
      mode = mail["X-Anysys-Mode"]&.value
      return if mode.blank?

      credential_id = mail["X-Anysys-Credential-Id"]&.value
      credential = if credential_id.present?
                     Email::CredentialResolver.for_recorded(credential_id: credential_id, mode: mode, provider: "smtp")
                   else
                     Email::CredentialResolver.call(mode: mode, provider: "smtp")
                   end
      Email::DkimSigner.sign!(mail, credential)
    rescue Email::Errors::CredentialsMissing
      # No active credential for this mode — leave the mail unsigned rather than
      # blocking delivery; the missing-credential condition surfaces upstream.
      nil
    ensure
      # These headers are internal routing/correlation only — never ship them to
      # the recipient. X-Anysys-Message-Id would otherwise leak our sequential
      # internal message id (a volume/enumeration signal) in every SMTP email.
      mail.header["X-Anysys-Mode"] = nil if mail["X-Anysys-Mode"]
      mail.header["X-Anysys-Message-Id"] = nil if mail["X-Anysys-Message-Id"]
      mail.header["X-Anysys-Credential-Id"] = nil if mail["X-Anysys-Credential-Id"]
    end
  end
end
