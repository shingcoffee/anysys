# frozen_string_literal: true

module Websites
  module Admin
    # One color attribute in the builder's Design panel: theme default, the
    # theme-aware tokens (drawn in the page theme's real colors), the curated
    # palette, and a custom hex picker. Every choice is a radio carrying
    # data-style-prop, so website-builder serializes the checked one.
    class StyleColorFieldComponent < ApplicationComponent
      SWATCH = [
        "block size-7 rounded-full ring-1 ring-black/10 ring-offset-2 ring-offset-surface transition",
        "peer-checked:ring-2 peer-checked:ring-accent peer-focus-visible:outline-2 peer-focus-visible:outline-offset-4 peer-focus-visible:outline-accent"
      ].join(" ")
      CUSTOM_FALLBACK = "#000000"

      def initialize(name:, attribute:, label:, value:, tokens:, theme:)
        @name = name
        @attribute = attribute.to_s
        @label = label
        @value = value.to_s
        @tokens = tokens
        @theme = theme
      end

      attr_reader :name, :attribute, :label, :value

      def choices
        token_choices = @tokens.map do |token|
          { value: token, label: t("website.admin.pages.style.tokens.#{token}"), css: @theme.color(swatch_role(token)) }
        end
        palette = Websites::SectionStyles::PALETTE.map { |hex| { value: hex, label: hex, css: hex } }
        token_choices + palette
      end

      def checked?(choice_value)
        value == choice_value.to_s
      end

      def default_checked?
        value.blank?
      end

      def custom?
        Websites::SectionStyles.hex?(value) && choices.none? { |choice| choice[:value] == value }
      end

      def custom_value
        custom? ? value : CUSTOM_FALLBACK
      end

      def input_id(suffix)
        "#{name}_#{suffix.to_s.delete('#')}"
      end

      def radio(choice_value, checked:, data: {})
        tag.input(type: "radio", class: "peer sr-only", name: name, value: choice_value, checked: checked,
                  id: input_id(choice_value.presence || "default"),
                  data: { style_prop: attribute, action: "change->website-builder#markDirty" }.merge(data))
      end

      private

      def swatch_role(token)
        token == "accent" && attribute == "background" ? "accent_fill" : token
      end
    end
  end
end
