# frozen_string_literal: true

module FormFields
  class DividerElementComponent < BaseElementComponent
    # "md" (the default) resolves from the theme's field_spacing instead.
    SPACING = {
      "sm" => "my-2",
      "lg" => "my-8"
    }.freeze

    attr_reader :label, :spacing

    def initialize(label: nil, spacing: "md", theme: {})
      super(theme: theme)
      @label = label
      @spacing = spacing
    end

    def spacing_class
      SPACING[spacing] || resolve_divider_spacing(@theme)
    end

    def label_bg_class
      FORM_BG_MAP[resolve_theme(@theme)["form_background"]] || FORM_BG_MAP["white"]
    end
  end
end
