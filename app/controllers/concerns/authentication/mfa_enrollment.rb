# frozen_string_literal: true

module Authentication
  # Shared plumbing for the two TOTP enrolment surfaces
  # (Authentication::MfaSetupsController and Member::MfaController).
  #
  # Both render the provisioning secret in plain text next to the QR code, so
  # both need the same cache suppression and the same "never show the secret
  # again once enrolment is complete" guard. Keeping them here means a fix
  # applies to both surfaces instead of only the one that was remembered.
  module MfaEnrollment
    extend ActiveSupport::Concern
    include Authentication::NoStore

    private

    # Plant a secret only when the user has none. Re-generating on every visit
    # would let a repeat GET silently invalidate an authenticator the user has
    # already registered. Prefetch must not plant one either: Turbo issues that
    # GET on hover, and a stored secret makes enrollment mandatory.
    def ensure_otp_secret!
      return if prefetch_request?

      current_user.generate_otp_secret! if current_user.otp_secret.blank?
    end

    def prefetch_request?
      return false unless request.get? || request.head?

      request.headers["X-Sec-Purpose"].to_s == "prefetch" ||
        request.headers["Purpose"].to_s == "prefetch" ||
        request.headers["Sec-Purpose"].to_s.split(/[;,\s]+/).include?("prefetch")
    end

    def enrollment_qr_code
      Authentication::QrCode.svg(current_user.otp_provisioning_uri)
    end
  end
end
