# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class UserRolesTableComponent < ViewComponent::Base
          def initialize(users:, roles:, customer:)
            @users    = users
            @roles    = roles
            @customer = customer
          end

          attr_reader :users, :roles, :customer

          def role_options
            roles.map do |role|
              presenter = Admin::Settings::RolePresenter.new(role)
              { id: role.id, name: presenter.name, key: role.key, system: role.system?,
                description: role.reserved? ? presenter.scope : role.description.presence || presenter.scope }
            end
          end
        end
      end
    end
  end
end
