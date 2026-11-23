# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # A single on/off toggle switch that PATCHes `url` with `field`=1/0.
      # Resource-style endpoints pass `http_method:` (e.g. POST to turn on, DELETE to
      # turn off) and `field: nil`, so the verb alone carries the new state.
      # When `disabled` it renders a static (non-submitting) switch — used for
      # mandatory modules and for Required while a module is inactive.
      class ModuleToggleComponent < ApplicationComponent
        def initialize(url:, field:, on:, http_method: :patch, disabled: false, confirm: nil, on_label: nil, off_label: nil,
                       extra_params: {}, show_label: true, centered: false, aria_label: nil,
                       html_attributes: {})
          @url = url
          @field = field
          @http_method = http_method
          @on = on
          @disabled = disabled
          @confirm = confirm
          @on_label = on_label
          @off_label = off_label
          @extra_params = extra_params
          @show_label = show_label
          @centered = centered
          @aria_label = aria_label
          @html_attributes = html_attributes.deep_dup
        end

        attr_reader :url, :field, :http_method, :on, :disabled, :confirm, :on_label, :off_label, :extra_params, :aria_label

        def on? = @on
        def disabled? = @disabled
        def show_label? = @show_label
        def centered? = @centered
        def next_value = on? ? "0" : "1"

        def control_html_attributes
          attributes = @html_attributes.deep_dup
          attributes[:aria] = attributes.fetch(:aria, {}).dup
          attributes[:aria][:label] = aria_label if aria_label.present?
          attributes
        end

        def wrapper_classes
          base = "flex items-center gap-3 whitespace-nowrap flex-shrink-0"
          if centered?
            "#{base} justify-center"
          else
            "#{base} justify-end ml-auto"
          end
        end

        def track_classes
          base = "relative inline-flex h-6 w-11 flex-shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
          state = on? ? "bg-accent" : "bg-border"
          cursor = disabled? ? "opacity-50 cursor-not-allowed" : "cursor-pointer"
          "#{base} #{state} #{cursor}"
        end

        def knob_classes
          pos = on? ? "translate-x-5" : "translate-x-0"
          "#{pos} pointer-events-none inline-block h-5 w-5 transform rounded-full bg-surface shadow ring-0 transition duration-200 ease-in-out"
        end

        def label
          if on?
            on_label || I18n.t("comp_admin.module_toggle.on")
          else
            off_label || I18n.t("comp_admin.module_toggle.off")
          end
        end
      end
    end
  end
end
