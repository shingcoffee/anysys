# frozen_string_literal: true

module Authentication
  # Sign-in guard for the MFA controllers.
  #
  # These live under /:cid/auth/... — neither the admin nor the member prefix —
  # so RouteAuthorization does not gate them, and they cannot use Devise's
  # `authenticate_user!` because that would bounce a user mid-MFA into a
  # Warden failure rather than the sign-in form. Each of the three MFA
  # controllers carried its own identical copy of this filter.
  module RequiresSignIn
    extend ActiveSupport::Concern

    included do
      before_action :require_signed_in!
    end

    private

    def require_signed_in!
      return if user_signed_in?

      redirect_to new_user_session_path, alert: t("auth.flash.sign_in_first")
    end
  end
end
