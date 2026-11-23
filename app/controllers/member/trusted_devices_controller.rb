# frozen_string_literal: true

module Member
  # Self-service revocation of the member's own trusted (2FA-bypass) devices,
  # surfaced on the security page. Strictly scoped to current_user — the device
  # is looked up through current_user's association and never accepts a user_id,
  # so a member can only ever revoke their own device. Member-only via
  # RouteAuthorization (member path).
  class TrustedDevicesController < BaseController
    def destroy
      device = current_user.trusted_devices.find(params[:id])
      device.destroy!

      redirect_to member_security_path(current_user.customer_id),
                  notice: t("member.securities.show.device_revoked")
    end
  end
end
