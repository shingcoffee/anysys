# frozen_string_literal: true

require "openssl"
require "dkim"
require "mail/dkim_field"

module Email
  # Signs an outgoing Mail::Message with a DKIM-Signature header using the
  # platform credential's RSA key.
  #
  # Thin wrapper over the mature `dkim` gem (RFC 6376) — we do NOT hand-roll
  # canonicalization or signing. Per-credential config (domain/selector/key)
  # is passed per call rather than via the gem's global config, so the single
  # platform credential drives signing without process-global state. The
  # `sign!(mail, credential)` interface is the only public surface; swapping
  # the underlying library is a change confined to this file.
  #
  # No-op unless the credential has DKIM fully configured.
  class DkimSigner
    SIGNING_ALGORITHM = "rsa-sha256"

    def self.sign!(mail, credential)
      return mail unless credential.respond_to?(:dkim_configured?) && credential.dkim_configured?

      new(mail, credential).sign!
      mail
    rescue OpenSSL::PKey::PKeyError => e
      # A corrupt stored key must not block delivery — leave the mail unsigned,
      # consistent with Emails::Credential#dkim_dns_txt_record's own rescue.
      Rails.logger.warn("[email.dkim] skipped signing — unparseable key: #{e.message}")
      mail
    end

    def initialize(mail, credential)
      @mail = mail
      @credential = credential
    end

    def sign!
      # Drop any pre-existing signature so we never emit two.
      @mail.header["DKIM-Signature"] = nil if @mail["DKIM-Signature"]

      header_value = Dkim::SignedMail.new(@mail.encoded, dkim_options).dkim_header.value
      @mail.header.fields.unshift(Mail::DkimField.new(header_value))
      @mail
    end

    private

    def dkim_options
      {
        domain:            @credential.dkim_domain,
        selector:          @credential.dkim_selector,
        # Pass a key object (not the raw PEM) so options-hash merge bypasses the
        # gem's string-coercing setter.
        private_key:       OpenSSL::PKey::RSA.new(@credential.dkim_private_key),
        signing_algorithm: SIGNING_ALGORITHM,
        signable_headers:  (Dkim::DefaultHeaders + %w[List-Unsubscribe List-Unsubscribe-Post]).uniq,
        time:              Time.current
      }
    end
  end
end
