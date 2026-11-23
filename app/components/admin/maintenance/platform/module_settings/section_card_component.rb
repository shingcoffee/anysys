# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        class SectionCardComponent < ApplicationComponent
          def initialize(title:, description: nil, action: nil)
            @title = title
            @description = description
            @action = action
          end

          attr_reader :title, :description, :action

          def title_id
            @title_id ||= "module-settings-section-#{title.to_s.parameterize}-#{object_id}"
          end
        end
      end
    end
  end
end
