# frozen_string_literal: true

module Authentication
  class User < ApplicationRecord
    # MfaMethods
    #
    # TOTP-based two-factor / multi-factor authentication helpers for
    # Authentication::User. Extracted as a concern to keep the model thin.
    # All methods operate exclusively on the +otp_secret+,
    # +otp_required_for_login+, +last_otp_at+, and +trusted_devices+
    # attributes/association — no auth or role state is touched here.
    module MfaMethods
      extend ActiveSupport::Concern

      # Generate a new OTP secret for this user
      def generate_otp_secret!
        Authentication::MfaMutation.call(user: self, otp_secret: ROTP::Base32.random)
      end

      # Get a TOTP instance for verification
      def otp
        ROTP::TOTP.new(otp_secret, issuer: "Anysys")
      end

      # Verify a TOTP code, consuming it so it cannot be replayed.
      def verify_otp(code)
        return false unless otp_secret.present? && code.present?

        # NB: ROTP's drift_* are SECONDS, not steps — ±15s is well within a
        # single 30s TOTP step (≈1 live code), tolerating minor clock skew,
        # while consuming the timecode below prevents replay and
        # Authentication::Throttle caps brute force. (A tighter ±1s would
        # reject legitimately-skewed codes.)
        Authentication::CredentialLifecycle.with_current(self) do |account|
          verified_at = account.otp.verify(code.to_s.strip,
                                           drift_behind: 15, drift_ahead: 15,
                                           after: account.last_otp_at)
          next false unless verified_at
          next false unless account.send(:claim_otp_timecode, Time.at(verified_at).utc)

          # Keep the verified secret snapshot: reloading after releasing the
          # lock could bind the controller's MFA flag to a newer, unverified key.
          self.last_otp_at = account.last_otp_at
          clear_attribute_change(:last_otp_at)
          true
        end
      rescue ActiveRecord::StaleObjectError
        false
      end

      # Generate a provisioning URI for QR code generation
      def otp_provisioning_uri
        return nil unless otp_secret.present?

        otp.provisioning_uri(email)
      end

      # Enable MFA for this user (must have otp_secret set first)
      def enable_mfa!
        raise "OTP secret not set" unless otp_secret.present?

        Authentication::MfaMutation.call(user: self, otp_required_for_login: true)
      end

      # Disable MFA for this user
      def disable_mfa!
        Authentication::MfaMutation.call(user: self, otp_required_for_login: false, otp_secret: nil)
      end

      # Invalidate every "trust this device" record for this user. Fired by the
      # after_update callback on password change/reset and on MFA disable/reset.
      def revoke_trusted_devices!
        trusted_devices.delete_all
      end

      # Check if MFA is set up (has secret) regardless of enforcement
      def mfa_configured?
        otp_secret.present?
      end

      # Check if MFA verification is required for this user
      def mfa_required?
        otp_required_for_login? && otp_secret.present?
      end

      private

      # Advance last_otp_at in a single conditional UPDATE, so exactly one
      # request can consume a given timecode.
      #
      # `after: last_otp_at` alone only orders *sequential* attempts: it reads
      # the column into memory and writes it back, so two requests firing the
      # same stolen code concurrently both read the old value and both verify.
      # That let one observed code be spent twice — e.g. clearing the MFA
      # challenge and disabling MFA outright at the same time.
      def claim_otp_timecode(consumed_at)
        claimed = self.class.where(id: id)
                      .where("last_otp_at IS NULL OR last_otp_at < :at", at: consumed_at)
                      .update_all(last_otp_at: consumed_at)
        return false unless claimed.positive?

        # Re-sync the in-memory attribute to what the row now holds without
        # marking it dirty — the same end state #update_column leaves behind.
        self.last_otp_at = consumed_at
        clear_attribute_change(:last_otp_at)
        true
      end
    end
  end
end
