# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      class UserActivationsController < ApplicationController
        include ::Authentication::OwnerAccountProtectable

        dashboard_menu_item :modules

        before_action :find_user
        before_action :protect_owner_account!, only: %i[create destroy]

        def create
          @user.update!(status: :active)
          redirect_to admin_modules_authentication_users_path(current_customer_id),
                      notice: t("admin_modules.flash.users.activated", name: @user.display_name)
        end

        def destroy
          if @user == current_user
            redirect_to admin_modules_authentication_users_path(current_customer_id),
                        alert: t("admin_modules.flash.users.deactivate_self_blocked")
            return
          end

          @user.update!(status: :inactive)
          redirect_to admin_modules_authentication_users_path(current_customer_id),
                      notice: t("admin_modules.flash.users.deactivated", name: @user.display_name)
        end

        private

        def find_user
          @user = ::Authentication::User.where(customer_id: current_customer_id).find(params[:user_id])
        end
      end
    end
  end
end
