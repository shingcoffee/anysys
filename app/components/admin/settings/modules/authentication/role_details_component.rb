# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class RoleDetailsComponent < ApplicationComponent
          def initialize(role:)
            @role = role
          end

          attr_reader :role

          def presenter = RolePresenter.new(role)
        end
      end
    end
  end
end
