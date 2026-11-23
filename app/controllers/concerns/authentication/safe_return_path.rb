# frozen_string_literal: true

module Authentication
  # Shared allow-list for Devise `stored_location_for(:user)` after sign-in
  # or MFA. Same-tenant paths plus the public OAuth authorize URL.
  module SafeReturnPath
    extend ActiveSupport::Concern

    OAUTH_AUTHORIZE_PATH = %r{\A/oauth/authorize(?:\?|\z)}.freeze
    RETURN_TO_SESSION_KEY = "user_return_to"

    # Browsers strip C0 control characters before resolving a URL, so
    # "/\t/evil.com" normalises to "//evil.com" — a protocol-relative
    # off-site redirect that the `start_with?("//")` check below does not
    # catch. Reject control characters outright rather than trying to predict
    # each browser's normalisation. Space is deliberately not included: it is
    # percent-encoded in a real request path and is not a normalisation vector.
    CONTROL_CHARACTERS = /[\u0000-\u001F\u007F]/

    private

    def safe_return_path_for(user, target)
      return nil unless target.is_a?(String) && target.start_with?("/")
      return nil if target.match?(CONTROL_CHARACTERS)
      return nil if target.start_with?("//", "/\\")
      return target if target.match?(OAUTH_AUTHORIZE_PATH)
      return target if user && target.start_with?("/#{user.customer_id}/")

      nil
    end

    def peek_return_to
      session[RETURN_TO_SESSION_KEY]
    end

    def restore_return_to(path)
      session[RETURN_TO_SESSION_KEY] = path if path.present?
    end
  end
end
