# frozen_string_literal: true

module Authentication
  # Shared cookie reader for controllers that participate in the
  # "trust this device" 2FA-bypass flow.
  #
  # The signed cookie holds the raw token directly (no id prefix).
  # Trust evaluation is entirely server-side: SignInFlow calls
  # Authentication::TrustedDevice.authenticate(user:, raw_token:)
  # which keys off the SHA-256 digest stored in the DB row.
  module TrustedDeviceCookieable
    extend ActiveSupport::Concern

    private

    # Returns the raw trusted-device token from the signed cookie, or nil
    # when the cookie is absent. The value is trusted only as an opaque
    # string passed to the server-side digest lookup — never as an identity.
    def trusted_device_token
      cookies.signed[:trusted_device].presence
    end
  end
end
