# frozen_string_literal: true

module FormFields
  class SectionElementComponent < BaseElementComponent
    attr_reader :title, :description, :variant

    def initialize(title:, description: nil, variant: nil, theme: {})
      super(theme: theme)
      @title = title
      @description = description
      @variant = %w[linked].include?(variant) ? variant : nil
    end

    private

    def section_fieldset_classes
      top    = resolve_section_top_margin(@theme)
      bottom = resolve_section_bottom_margin(@theme)
      # Left-border accent lives on the legend, not the fieldset: browsers paint
      # fieldset border-left below the legend's special layout slot, so the bar
      # starts mid-title. Putting the accent on the legend aligns it with the text.
      [top, bottom].reject(&:blank?).join(" ")
    end

    def section_legend_classes
      extra = resolve_section_legend_extra(@theme)
      border = resolve_section_border(@theme)
      base  = if extra.include?("text-xs")
                # uppercase/small variant — suppress the default text-lg
                ""
      elsif border.present?
                # Skip pb-1.5: it stretches the left accent below the glyphs.
                "text-lg font-semibold leading-snug #{neutral(:strong_text)} w-full"
      else
                "text-lg font-semibold #{neutral(:strong_text)} pb-1.5 w-full"
      end
      # Elegant/minimalist (no left border) get a bottom border on the legend;
      # presets with a left border accent skip the bottom border to avoid clutter.
      border_b = border.blank? && !extra.include?("text-xs") ?
                   "border-b #{neutral(:subtle_border)}" : ""
      [base, border, border_b, extra].reject(&:blank?).join(" ")
    end
  end
end
