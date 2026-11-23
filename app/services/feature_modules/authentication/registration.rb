# frozen_string_literal: true

module FeatureModules
  module Authentication
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "authentication"
      def self.module_name        = "User Authentication"
      def self.module_description = "Devise-based user authentication with optional TOTP 2FA/MFA"

      mandatory!

      # Keys in `customer_feature_modules.configuration` that are surfaced
      # by the generic `Admin::ModuleConfigsController`. The two toggles for
      # self sign-up and forgot-password live here too (defaults consumed by
      # `Authentication::Settings`) but are NOT exposed by the generic page —
      # they have their own dedicated entries under
      # /:cid/admin/settings/modules/authentication/{sign_up,forget_password}.
      def self.configuration_schema
        {
          "mfa_enabled"        => { "type" => "boolean", "default" => false,
                                    "description" => "Require 2FA/MFA for all users" },
          "session_timeout"    => { "type" => "number",  "default" => 30,
                                    "description" => "Session timeout in minutes" },
          "max_login_attempts" => { "type" => "number",  "default" => 10,
                                    "description" => "Max failed login attempts before lockout" }
        }
      end

      # Whitelist of keys that the generic ModuleConfigsController is allowed
      # to write. The dedicated SignUp/ForgetPassword controllers update their
      # own keys directly; including them here would let the generic page also
      # write them, defeating the categorization.
      def self.configuration_keys
        %i[mfa_enabled session_timeout max_login_attempts]
      end

      entry_path   { |_customer| "/auth/sign_in" }
      default_exit kind: "route", name: "customer_home"

      def self.provision!(customer)
        FeatureModules::Authentication::Provisioner.call(customer)
      end

      def self.deprovision!(customer)
        FeatureModules::Authentication::Deprovisioner.call(customer)
      end

      def self.sidebar_contributions(_controller)
        {
          entries: [
            ModuleContribution.new(
              label: I18n.t("feature_modules.authentication.entries.users"),
              entry_key: "users",
              path: ->(customer_id) { "/#{customer_id}/admin/modules/authentication/users" },
              permitted_by: :admin_or_owner?
            ),
            ModuleContribution.new(
              label: I18n.t("feature_modules.authentication.entries.events"),
              entry_key: "events",
              path: ->(customer_id) { "/#{customer_id}/admin/modules/authentication/events" },
              permitted_by: :admin_or_owner?
            )
          ],
          settings: [
            ModuleContribution.new(
              label: I18n.t("feature_modules.authentication.settings.sign_up"),
              entry_key: "sign_up",
              path: ->(customer_id) { "/#{customer_id}/admin/settings/modules/authentication/sign_up" },
              permitted_by: :admin_or_owner?
            ),
            ModuleContribution.new(
              label: I18n.t("feature_modules.authentication.settings.forget_password"),
              entry_key: "forget_password",
              path: ->(customer_id) { "/#{customer_id}/admin/settings/modules/authentication/forget_password" },
              permitted_by: :admin_or_owner?
            ),
            ModuleContribution.new(
              label: I18n.t("feature_modules.authentication.settings.roles"),
              entry_key: "roles",
              path: ->(customer_id) { "/#{customer_id}/admin/settings/modules/authentication/roles" },
              permitted_by: :admin_or_owner?
            ),
            ModuleContribution.new(
              label: I18n.t("feature_modules.authentication.settings.user_role_assignments"),
              entry_key: "user_role_assignments",
              path: ->(customer_id) { "/#{customer_id}/admin/settings/modules/authentication/user_role_assignments" },
              permitted_by: :admin_or_owner?
            )
          ]
        }
      end

      # This module deliberately has no per-request hook.
      #
      # Sign-in enforcement for the admin and member prefixes is owned by
      # RouteAuthorization, and MFA enforcement — including the per-tenant
      # `mfa_enabled` toggle declared in this module's configuration_schema —
      # is owned by Authentication::EnforcesMfa, which consults
      # Authentication::Settings for exactly that key.
      #
      # A second MFA gate used to live here. Having two produced the usual
      # outcome: their exemption lists drifted apart, they disagreed about
      # whether a half-finished enrolment sends the user to verification or
      # back to setup, and only one of them re-derived the decision instead
      # of trusting a session flag. Do not reintroduce one.
    end
  end
end
