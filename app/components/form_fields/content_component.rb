# frozen_string_literal: true

module FormFields
  class ContentComponent < ApplicationComponent
    include ThemeResolver

    def initialize(theme: {})
      @theme = theme
    end

    private

    attr_reader :theme

    def content_classes
      resolve_field_spacing(theme)
    end
  end
end
