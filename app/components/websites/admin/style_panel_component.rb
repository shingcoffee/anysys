# frozen_string_literal: true

module Websites
  module Admin
    # Inline Design panel for one editor element (a text field, the buttons, a
    # list or the whole section), hidden until its #trigger is clicked. Each
    # [data-style-target] group of [data-style-prop] controls carries color,
    # font, size, weight, italic and alignment overrides; website-builder
    # folds the chosen values into props.styles. A list panel holds several
    # targets, so each one collapses into its own accordion row.
    class StylePanelComponent < ApplicationComponent
      SEGMENTED = {
        "size" => Websites::SectionStyles::SCALES.keys,
        "scale" => Websites::SectionStyles::SCALES.keys,
        "italic" => Websites::SectionStyles::ITALICS,
        "align" => Websites::SectionStyles::ALIGNS,
        "shape" => Websites::SectionStyles::SHAPES
      }.freeze
      SEGMENT_SCOPE = { "size" => "scales", "scale" => "scales", "italic" => "italics", "align" => "aligns", "shape" => "shapes" }.freeze
      SELECTS = {
        "font" => :fonts, "heading_font" => :fonts, "body_font" => :fonts,
        "weight" => Websites::SectionStyles::WEIGHTS.keys
      }.freeze
      COLOR_TOKENS = {
        "color" => Websites::SectionStyles::COLOR_TOKENS,
        "fill" => Websites::SectionStyles::COLOR_TOKENS,
        "text" => Websites::SectionStyles::COLOR_TOKENS,
        "background" => Websites::SectionStyles::BACKGROUND_TOKENS
      }.freeze
      SEGMENT_CLASS = [
        "flex min-h-8 cursor-pointer items-center justify-center rounded-[5px] px-2.5 text-xs font-medium text-text-secondary transition-colors",
        "hover:text-text-primary peer-checked:bg-surface peer-checked:text-text-primary peer-checked:shadow-xs",
        "peer-focus-visible:outline-2 peer-focus-visible:outline-accent pointer-coarse:min-h-10"
      ].join(" ")

      attr_reader :targets, :label

      def initialize(section_id:, targets:, styles:, theme:, label:)
        @section_id = section_id.to_s
        @targets = Array(targets)
        @styles = styles.respond_to?(:to_h) ? styles.to_h.deep_stringify_keys : {}
        @theme = theme || Websites::Theme.new
        @label = label
      end

      def render?
        targets.any?
      end

      def panel_id
        "website-style-#{@section_id}-#{targets.first[:key].tr('.', '-')}"
      end

      def trigger(reveal: false)
        StyleTriggerComponent.new(panel_id: panel_id, label: label, edited: edited?, reveal: reveal)
      end

      def grouped?
        targets.size > 1
      end

      def edited?
        targets.any? { |target| edited_target?(target) }
      end

      def edited_target?(target)
        @styles[target[:key]].respond_to?(:values) && @styles[target[:key]].values.any?(&:present?)
      end

      def attributes_for(target)
        Websites::SectionStyles::ATTRIBUTES.fetch(target[:kind])
      end

      def value(target, attribute)
        @styles.dig(target[:key], attribute).to_s
      end

      def target_label(target)
        case target[:kind]
        when :section, :buttons then t("website.admin.pages.style.targets.#{target[:kind]}")
        when :items then t("website.admin.pages.style.targets.items", list: field_label(target[:array]))
        else field_label(target[:field])
        end
      end

      def attribute_label(attribute)
        t("website.admin.pages.style.attributes.#{attribute}")
      end

      def control_kind(attribute)
        return :color if COLOR_TOKENS.key?(attribute)
        return :segmented if SEGMENTED.key?(attribute)

        :select
      end

      def control_name(target, attribute)
        "website_style_#{@section_id}_#{target[:key].tr('.', '_')}_#{attribute}"
      end

      # The section's preset surface sits beside its color, so the color reads as the custom option.
      def color_field(target, attribute)
        section = target[:kind] == :section
        StyleColorFieldComponent.new(name: control_name(target, attribute), attribute: attribute,
                                     label: attribute_label(section ? "custom_#{attribute}" : attribute),
                                     value: value(target, attribute), tokens: section ? [] : COLOR_TOKENS.fetch(attribute), theme: @theme)
      end

      def segments(attribute)
        SEGMENTED.fetch(attribute)
      end

      def segment_label(attribute, option)
        t("website.admin.pages.style.options.#{SEGMENT_SCOPE.fetch(attribute)}.#{option}")
      end

      def select_options(attribute)
        source = SELECTS.fetch(attribute)
        if source == :fonts
          Websites::Fonts.keys.map { |key| [Websites::Fonts.label(key), key] }
        else
          source.map { |option| [t("website.admin.pages.style.options.weights.#{option}"), option] }
        end
      end

      def segment_id(target, attribute, option)
        "#{control_name(target, attribute)}_#{option.presence || 'default'}"
      end

      def segment_radio(target, attribute, option)
        tag.input(type: "radio", class: "peer sr-only", name: control_name(target, attribute), value: option,
                  id: segment_id(target, attribute, option), checked: value(target, attribute) == option.to_s,
                  data: { style_prop: attribute, action: "change->website-builder#markDirty" })
      end

      private

      def field_label(key)
        label_key = Websites::SectionFields::LABEL_KEYS[key.to_s]
        label_key ? t(label_key) : key.to_s.humanize
      end
    end
  end
end
