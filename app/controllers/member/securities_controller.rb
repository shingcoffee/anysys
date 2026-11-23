# frozen_string_literal: true

module Member
  # Security center. A composition page over existing auth surfaces — does
  # not introduce new endpoints. Links out to Devise password reset and
  # the existing /:cid/auth/mfa/* MFA flows.
  class SecuritiesController < BaseController
    def show
      @mfa_enabled = current_user.mfa_required?
      @last_signin = {
        at: current_user.last_sign_in_at,
        ip: current_user.last_sign_in_ip
      }
      @trusted_devices = current_user.trusted_devices.active.order(last_used_at: :desc)
    end
  end
end
