# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class RolesController < ApplicationController
          dashboard_menu_item :settings
          before_action :set_role, only: %i[show edit update destroy]

          def index
            @columns = [
              { key: :name,              label: I18n.t("common.labels.name"),        sortable: true, searchable: true },
              { key: :key,               label: I18n.t("common.labels.key"),         sortable: true, searchable: true },
              { key: :system,            label: I18n.t("common.labels.system"),      type: :badge, sortable: true,
                badge: ->(r) { { variant: r.system? ? :info : :default, label: r.system? ? I18n.t("common.labels.system") : I18n.t("common.labels.custom") } },
                cell:  ->(r) { r.system? ? I18n.t("common.labels.system") : I18n.t("common.labels.custom") } },
              { key: :users_count,       label: I18n.t("common.labels.users"),       type: :number, sortable: false, searchable: false,
                cell: ->(r) { r.users.size } },
              { key: :permissions_count, label: I18n.t("common.labels.permissions"), type: :number, sortable: false, searchable: false,
                cell: ->(r) { r.role_permissions.size } }
            ]
            scope  = ::Role.where(customer_id: current_customer.id).includes(:users, :role_permissions)
            result = ModuleEntriesResolver.call(
              scope: scope, columns: @columns,
              params: params.permit(:q, :sort, :dir, :page).to_h.symbolize_keys
            )
            @roles      = result[:rows]
            @rows       = result[:rows]
            @pagination = result[:pagination]
          end

          def show; end

          def new
            @role = current_customer.roles.new
          end

          def create
            result = Roles::Operation::Create.call(customer: current_customer, params: role_params)
            if result.success?
              redirect_to admin_settings_modules_authentication_role_path(current_customer.id, result[:model]),
                          notice: t("admin_settings.flash.roles.created")
            else
              @role = result[:model]
              render :new, status: :unprocessable_entity
            end
          end

          def edit; end

          def update
            result = Roles::Operation::Update.call(role: @role, params: role_params)
            if result.success?
              redirect_to admin_settings_modules_authentication_role_path(current_customer.id, @role),
                          notice: t("admin_settings.flash.roles.updated")
            else
              render :edit, status: :unprocessable_entity
            end
          end

          def destroy
            result = Roles::Operation::Destroy.call(role: @role)
            if result.success?
              redirect_to admin_settings_modules_authentication_roles_path(current_customer.id),
                          notice: t("admin_settings.flash.roles.destroyed")
            else
              redirect_to admin_settings_modules_authentication_role_path(current_customer.id, @role),
                          alert: t("admin_settings.flash.roles.destroy_failed")
            end
          end

          private

          def set_role
            @role = current_customer.roles.find(params[:id])
          end

          def role_params
            params.require(:role).permit(:key, :name, :description)
          end
        end
      end
    end
  end
end
