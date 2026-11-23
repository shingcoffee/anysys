# frozen_string_literal: true

class PageBuilder::FloatingActionBarComponent < ApplicationComponent
  WIDTH_OPTION_KEYS = %w[full three_quarters two_thirds half third quarter].freeze

  def width_options
    WIDTH_OPTION_KEYS.map do |key|
      { key: key, label: I18n.t("comp_page_builder.floating_action_bar.widths.#{key}") }
    end
  end
end
