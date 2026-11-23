# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        class CredentialPanelComponent < ApplicationComponent
          def initialize(title:, description: nil, status: nil, status_variant: :default,
                         action: nil, rows: [])
            @title = title
            @description = description
            @status = status
            @status_variant = status_variant
            @action = action
            @rows = Array(rows)
          end

          attr_reader :title, :description, :status, :status_variant, :action, :rows
        end
      end
    end
  end
end
