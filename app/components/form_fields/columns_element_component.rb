# frozen_string_literal: true

module FormFields
  class ColumnsElementComponent < BaseElementComponent
    LAYOUT_CLASSES = {
      "50-50"       => "grid grid-cols-2 gap-6",
      "33-33-33"    => "grid grid-cols-3 gap-6",
      "25-25-25-25" => "grid grid-cols-4 gap-6",
      "66-33"       => "grid gap-6",
      "33-66"       => "grid gap-6"
    }.freeze

    LAYOUT_STYLES = {
      "66-33" => "grid-template-columns: 2fr 1fr",
      "33-66" => "grid-template-columns: 1fr 2fr"
    }.freeze

    attr_reader :column_layout, :columns

    def initialize(column_layout: "50-50", columns: [], theme: {})
      super(theme: theme)
      @column_layout = column_layout
      @columns = columns
    end

    def grid_classes
      LAYOUT_CLASSES[column_layout] || LAYOUT_CLASSES["50-50"]
    end

    def grid_style
      LAYOUT_STYLES[column_layout]
    end

    def column_count
      columns.size
    end
  end
end
