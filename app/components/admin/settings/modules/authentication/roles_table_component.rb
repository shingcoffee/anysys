# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class RolesTableComponent < ApplicationComponent
          def initialize(rows:, pagination:, params:, customer:)
            @rows, @pagination, @params, @customer = rows, pagination, params, customer
          end

          attr_reader :rows, :pagination, :params, :customer

          def columns
            [
              { key: :name, label: I18n.t("common.labels.name"), sortable: true,
                cell: ->(role) { RolePresenter.new(role).name } },
              { key: :scope, label: I18n.t("settings_people.scope"), cell: ->(role) { RolePresenter.new(role).scope } },
              { key: :system, label: I18n.t("common.labels.type"), sortable: true, cell: ->(role) { RolePresenter.new(role).kind } },
              { key: :users_count, label: I18n.t("settings_people.assigned_users"), cell: ->(role) { role.users.size } }
            ]
          end

          def row_actions(role)
            actions = [{ label: I18n.t("settings_people.permissions"), path: helpers.admin_settings_modules_authentication_role_grants_path(customer.id, role) }]
            unless role.system?
              actions << { label: I18n.t("common.actions.edit"), path: helpers.edit_admin_settings_modules_authentication_role_path(customer.id, role) }
              actions << { label: I18n.t("common.actions.delete"), path: helpers.admin_settings_modules_authentication_role_path(customer.id, role), method: :delete,
                           data: { turbo_confirm: I18n.t("admin_settings.authentication.roles.index.delete_confirm", name: role.name) } }
            end
            actions
          end
        end
      end
    end
  end
end
