# frozen_string_literal: true

module FormFields
  class WizardComponent < ApplicationComponent
    include ComponentClasses
    include ThemeResolver

    renders_many :steps, "StepComponent"

    def initialize(pages:, action:, method: :post, show_progress: true,
                   allow_back: true, validate_on_next: true, submit_text: nil,
                   theme: {}, cancel_url: nil, initial_step: 1, page: nil, extra_action: nil)
      @pages = pages
      @action = action
      @method = method
      @show_progress = show_progress
      @allow_back = allow_back
      @validate_on_next = validate_on_next
      @submit_text = submit_text
      @theme = theme
      @cancel_url = cancel_url || "javascript:history.back()"
      @initial_step = initial_step
      @page = page
      @extra_action = extra_action
    end

    private

    attr_reader :pages, :action, :method, :show_progress, :allow_back,
                :validate_on_next, :theme, :cancel_url, :initial_step, :page, :extra_action

    # Translated at render time so the current locale is honoured.
    def submit_text
      @submit_text || I18n.t("common.actions.submit")
    end

    # Wizard navigation buttons live in a horizontal toolbar (Cancel/Previous on
    # the left, Step counter/Next/Submit on the right), so they must be
    # auto-width and inline — never the theme's full-width submit styling.
    NAV_BUTTON_WIDTH = "w-auto px-6"

    def primary_button_classes
      [
        resolve_button_style_classes(theme),
        NAV_BUTTON_WIDTH,
        resolve_button_size(theme),
        resolve_radius_class(theme),
        "transition-all duration-200 focus:ring-2 focus:ring-offset-2 font-medium",
        "disabled:opacity-50 disabled:cursor-not-allowed"
      ].reject(&:blank?).join(" ").squish
    end

    def secondary_button_classes
      radius = resolve_radius_class(theme)
      size   = resolve_button_size(theme)
      "#{NAV_BUTTON_WIDTH} #{size} #{radius} bg-white text-gray-600 border border-gray-200 " \
        "hover:bg-gray-50 hover:border-gray-300 transition-all duration-150 focus:ring-2 " \
        "focus:ring-gray-200 focus:ring-offset-2 font-medium"
    end

    def progress_bar_color
      color_palette(theme)[:bg]
    end

    def step_indicator_items
      pages.each_with_index.map do |p, idx|
        { number: idx + 1, name: p["name"] || I18n.t("comp_form_fields.wizard.default_step_name", number: idx + 1), id: p["id"] }
      end
    end

    def total_steps
      pages.length
    end

    def wizard_data
      {
        controller: "wizard",
        wizard_total_steps_value: total_steps,
        wizard_current_step_value: initial_step,
        wizard_validate_on_next_value: validate_on_next,
        wizard_cancel_url_value: cancel_url,
        wizard_accent_color_value: progress_bar_color,
        wizard_step_of_format_value: I18n.t("comp_form_fields.wizard.step_of_format"),
        wizard_field_required_msg_value: I18n.t("comp_form_fields.wizard.field_required_msg")
      }
    end

    def form_method
      method == :get ? :get : :post
    end

    class StepComponent < ApplicationComponent
      def initialize(id:)
        @id = id
      end

      attr_reader :id

      def call
        content_tag :div,
                    content,
                    class: "wizard-step",
                    data: { wizard_target: "step", step_id: id }
      end
    end
  end
end
