# frozen_string_literal: true

module Authentication
  # OwnerAccountProtectable
  #
  # The owner-pin invariant (see `UsersRole#owner_role_pinned_to_platform_owner`)
  # protects the owner *role* — it stops anyone granting or stripping `owner`.
  # It does NOT protect the pinned owner's *account*: a non-owner admin inside
  # customer 81721200 could otherwise reset the owner's MFA, set the owner's
  # password, or deactivate the owner via the admin Users surface, then sign in
  # as the owner (who has `can :manage, :all` across every tenant).
  #
  # This concern closes that gap. Any admin controller action that mutates a
  # target user's credentials, MFA, or activation state must refuse when the
  # target holds the `owner` role and the acting user is not themselves an owner.
  #
  # Usage:
  #   before_action :protect_owner_account!, only: %i[update destroy create]
  #
  # `@user` (or the `find_user`-loaded target) must be set by an earlier
  # before_action. The guard redirects back with a generic flash and halts.
  module OwnerAccountProtectable
    extend ActiveSupport::Concern

    private

    def protect_owner_account!
      target = protected_owner_target
      return unless target&.owner?
      return if current_user&.owner?

      redirect_to owner_account_protected_redirect_path,
                  alert: t("admin_modules.flash.users.owner_account_protected")
    end

    # The user being mutated. Defaults to the conventional `@user` ivar; a
    # controller loading the target under a different name overrides this.
    def protected_owner_target
      @user
    end

    # Where to send a blocked actor. Defaults to the module's users index;
    # controllers with a more specific surface may override.
    def owner_account_protected_redirect_path
      admin_modules_authentication_users_path(current_customer_id)
    end
  end
end
