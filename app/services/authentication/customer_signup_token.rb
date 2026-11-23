# frozen_string_literal: true

module Authentication
  # Encrypted, self-expiring payload for public customer sign-up.
  # The email lives in the token; nothing is stored until confirm.
  class CustomerSignupToken
    PURPOSE = "customer_signup"
    TTL     = 3.days

    def self.generate(email)
      encryptor.encrypt_and_sign(
        { "email" => normalize(email) },
        purpose: PURPOSE,
        expires_in: TTL
      )
    end

    def self.verify(token)
      return nil if token.blank?

      payload = encryptor.decrypt_and_verify(token.to_s, purpose: PURPOSE)
      email = payload.is_a?(Hash) ? payload["email"].to_s : ""
      email.presence
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def self.normalize(email)
      email.to_s.strip.downcase
    end

    def self.encryptor
      secret = Rails.application.key_generator.generate_key(PURPOSE, 32)
      ActiveSupport::MessageEncryptor.new(secret, serializer: JSON)
    end
    private_class_method :encryptor
  end
end
