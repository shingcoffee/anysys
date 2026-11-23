# frozen_string_literal: true

module FormFields
  class FormComponent < ApplicationComponent
    include ComponentClasses
    include ThemeResolver

    def initialize(action: nil, method: :post, submit_text: nil, css_class: nil, data: {}, theme: {}, page: nil, extra_action: nil)
      @action = action
      @method = method
      @submit_text = submit_text
      @css_class = css_class
      @data = data
      @theme = theme
      @page = page
      @extra_action = extra_action
    end

    private

    attr_reader :action, :method, :css_class, :data, :theme, :page, :extra_action

    # Translated at render time so the current locale is honoured.
    def submit_text
      @submit_text || I18n.t("common.actions.submit")
    end

    def form_container_classes
      # Provides a subtle focus-within highlight for borderless themes
      "group"
    end

    def form_classes
      [field_spacing_class, css_class].compact.join(" ")
    end

    def field_spacing_class
      resolve_field_spacing(theme)
    end

    def submit_button_classes
      resolve_submit_button_classes(theme)
    end

    def form_method
      method == :get ? :get : :post
    end

    def hidden_method_field?
      %i[put patch delete].include?(method)
    end
  end
end
