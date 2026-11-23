# frozen_string_literal: true

module PageBuilder
  # Trigger + lazy-loaded modal for selecting a layout template.
  # Used by the entity create/edit form and the page builder "New Page" form.
  # The consuming view supplies the `data-controller="template-selector"` root
  # (and its `*-cards-url-value` / `*-customer-id-value` values) so that the
  # entity <select> in the page builder shares the same controller instance.
  class TemplatePickerComponent < ApplicationComponent
    def initialize(selected_template:, category_counts:, cards_url:,
                   field_name:, field_value:, field_key:,
                   confirm_label: nil, controller_name: "template-selector",
                   preview_url: nil)
      @selected_template = selected_template
      @category_counts   = category_counts
      @cards_url         = cards_url
      @field_name        = field_name
      @field_value       = field_value
      @field_key         = field_key.to_s
      @confirm_label     = confirm_label
      @controller_name   = controller_name
      @preview_url       = preview_url
    end

    attr_reader :selected_template, :category_counts, :cards_url,
                :field_name, :field_value, :field_key, :controller_name,
                :preview_url

    def confirm_label
      @confirm_label || I18n.t("comp_page_builder.template_picker.use_template")
    end

    def selected?
      field_key.present?
    end

    def selected_name
      selected_template&.dig(:name).presence || selected_template&.dig("name").presence || field_key
    end

    def selected_theme
      selected_template&.dig(:theme_preset).presence || selected_template&.dig("theme_preset").presence
    end
  end
end
