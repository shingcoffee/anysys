# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        class ProviderWorkspaceComponent < ApplicationComponent
          renders_one :assignment
          renders_one :provider
          renders_one :health
          renders_one :credentials
          renders_one :advanced_options

          def stages
            [
              [:assignment, assignment],
              [:provider, provider],
              [:health, health],
              [:credentials, credentials],
              [:"advanced-options", advanced_options]
            ].select { |_name, slot| slot.present? }
          end
        end
      end
    end
  end
end
