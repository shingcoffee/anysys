# frozen_string_literal: true

module Websites
  module Admin
    # Registers as a website-theme-picker scrollspy section; the jump nav
    # links to heading_id, so ids must stay stable.
    class SettingsSectionComponent < ApplicationComponent
      renders_one :aside

      def initialize(id:, heading:, description: nil, data: {})
        @id = id
        @heading = heading
        @description = description
        @data = data
      end

      attr_reader :id, :heading, :description

      def heading_id
        "#{id}-heading"
      end

      def section_data
        { website_theme_picker_target: "section" }.merge(@data)
      end
    end
  end
end
