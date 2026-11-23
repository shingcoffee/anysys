# frozen_string_literal: true

module Authentication
  # Records and reads "this session has cleared the second factor".
  #
  # The flag is bound to a digest of the TOTP secret it was granted against.
  # A bare boolean outlived the credential it stood for: after an admin MFA
  # reset, or a self-service disable-and-re-enrol from another device, the old
  # session still asserted a second factor it had never presented for the
  # *current* secret. Binding makes any change of secret re-challenge every
  # session that was verified against the old one.
  module MfaSessionVerification
    extend ActiveSupport::Concern

    VERIFIED_KEY = :mfa_verified
    SECRET_KEY   = :mfa_secret_digest

    # Digest rather than the secret itself. The session cookie is encrypted,
    # but a credential should not be copied into a second store regardless,
    # and a digest is all the comparison needs.
    def self.secret_digest(user)
      secret = user&.otp_secret
      return nil if secret.blank?

      Digest::SHA256.hexdigest(secret)
    end

    private

    def mark_mfa_verified!(user = current_user, verified: true)
      session[VERIFIED_KEY] = verified
      session[SECRET_KEY]   = MfaSessionVerification.secret_digest(user)
    end

    def clear_mfa_verification!
      session.delete(VERIFIED_KEY)
      session.delete(SECRET_KEY)
    end

    def mfa_session_verified?(user = current_user)
      return false unless session[VERIFIED_KEY]

      session[SECRET_KEY] == MfaSessionVerification.secret_digest(user)
    end
  end
end
