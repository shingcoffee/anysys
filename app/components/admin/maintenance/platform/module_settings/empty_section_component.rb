# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        class EmptySectionComponent < ApplicationComponent
          def initialize(title:, description:, action_path: nil, action_label: nil)
            @title = title
            @description = description
            @action_path = action_path
            @action_label = action_label
          end

          attr_reader :title, :description, :action_path, :action_label

          def action?
            action_path.present? && action_label.present?
          end
        end
      end
    end
  end
end
