# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        class FormActionsComponent < ApplicationComponent
          def initialize(cancel_path:, submit_label:, sticky: false)
            @cancel_path = cancel_path
            @submit_label = submit_label
            @sticky = sticky
          end

          attr_reader :cancel_path, :submit_label

          def sticky?
            @sticky
          end
        end
      end
    end
  end
end
