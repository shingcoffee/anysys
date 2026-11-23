# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      class UserMfaResetsController < ApplicationController
        include ::Authentication::OwnerAccountProtectable

        dashboard_menu_item :modules

        before_action :find_user
        before_action :protect_owner_account!, only: %i[create]

        def create
          if @user == current_user
            redirect_to admin_modules_authentication_user_path(current_customer_id, @user),
                        alert: t("admin_modules.flash.users.mfa_reset_self_blocked")
            return
          end

          unless @user.mfa_configured?
            redirect_to admin_modules_authentication_user_path(current_customer_id, @user),
                        alert: t("admin_modules.flash.users.mfa_not_configured")
            return
          end

          ::Authentication::MutationAudit.mfa(user: @user, request: request,
                                              actor: current_user, source: "admin_reset") { @user.disable_mfa! }
          redirect_to admin_modules_authentication_user_path(current_customer_id, @user),
                      notice: t("admin_modules.flash.users.mfa_reset", name: @user.display_name)
        end

        private

        def owner_account_protected_redirect_path
          admin_modules_authentication_user_path(current_customer_id, @user)
        end

        def find_user
          @user = ::Authentication::User.where(customer_id: current_customer_id).find(params[:user_id])
        end
      end
    end
  end
end
