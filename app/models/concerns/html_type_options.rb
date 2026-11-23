# frozen_string_literal: true

module HtmlTypeOptions
  extend ActiveSupport::Concern

  # Stable identifiers only — this constant is evaluated once at class-load
  # time, so it cannot bake in I18n.t (that would freeze under the boot-time
  # locale). Category keys and label keys are translated at call time by
  # `grouped_html_types` via config/locales/maint_core.*.yml
  # (`maint_core.field_types.categories.*` / `maint_core.field_types.labels.*`).
  GROUPED_HTML_TYPES = {
    text: [
      [:text_input, "text"],
      [:textarea, "textarea"],
      [:search, "search"],
      [:password, "password"],
      [:hidden, "hidden"]
    ],
    selection: [
      [:dropdown, "select"],
      [:radio_buttons, "radio"],
      [:checkboxes, "checkbox"]
    ],
    numeric: [
      [:number, "number"],
      [:range_slider, "range"]
    ],
    date_time: [
      [:date, "date"],
      [:time, "time"],
      [:datetime, "datetime-local"],
      [:month, "month"],
      [:week, "week"]
    ],
    contact: [
      [:email, "email"],
      [:phone, "tel"],
      [:url, "url"]
    ],
    media_file: [
      [:file_upload, "file"],
      [:image_upload, "image"],
      [:color_picker, "color"]
    ]
  }.freeze

  SELECTION_TYPES = %w[select radio checkbox].freeze

  CONFIG_TYPES = {
    selection: %w[select radio checkbox],
    numeric: %w[number range],
    textarea: %w[textarea],
    file: %w[file image]
  }.freeze

  # Module-level methods (callable as HtmlTypeOptions.method_name)
  class << self
    def selection_type?(value)
      return false if value.blank?
      SELECTION_TYPES.include?(value.to_s)
    end

    def config_type_for(value)
      return nil if value.blank?
      CONFIG_TYPES.find { |_type, values| values.include?(value.to_s) }&.first
    end

    def configurable_type?(value)
      !config_type_for(value).nil?
    end

    # Translates GROUPED_HTML_TYPES' stable category/label keys into the
    # current locale's display text. Built fresh on every call (not memoized)
    # so it always reflects I18n.locale at call time.
    def grouped_html_types
      GROUPED_HTML_TYPES.each_with_object({}) do |(category, types), result|
        category_label = I18n.t("maint_core.field_types.categories.#{category}")
        result[category_label] = types.map { |key, value| [I18n.t("maint_core.field_types.labels.#{key}"), value] }
      end
    end

    def all_html_types
      grouped_html_types.values.flatten(1)
    end

    def valid_html_type?(value)
      return false if value.blank?
      all_html_types.any? { |_, v| v == value }
    end

    def label_for(value)
      return I18n.t("maint_core.field_types.labels.text_input") if value.blank?
      pair = all_html_types.find { |_, v| v == value }
      pair ? pair.first : value
    end
  end
end
