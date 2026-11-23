# frozen_string_literal: true

module Admin
  module Entities
    # One attribute group of an entry: the group's icon and color, and each
    # field's label and display value (via +display+, an Entities::EntryDisplay)
    # as a label / value row. Long-form fields stack their value under the
    # label; email, phone and web-address values link out. +framed+ draws its
    # own card; unframed groups sit inside a card the caller provides.
    class AttributeGroupCardComponent < ApplicationComponent
      FULL_WIDTH_TYPES = %w[textarea multi-select].freeze
      WEB_ADDRESS = %r{\Ahttps?://\S+\z}i
      VALUE_LINK_CLASSES = "font-medium text-accent-text hover:underline focus-visible:underline"

      attr_reader :id, :heading, :icon, :fields, :entry, :display, :heading_tag

      def initialize(id:, heading:, icon:, color:, fields:, entry:, display:, heading_tag: :h2, framed: true)
        @id = id
        @heading = heading
        @icon = icon
        @color = color
        @fields = fields
        @entry = entry
        @display = display
        @heading_tag = heading_tag
        @framed = framed
      end

      def section_classes
        classes = "scroll-mt-6 px-4 pt-4 pb-1 transition-shadow duration-500 sm:px-6 sm:pt-5 sm:pb-2"
        @framed ? "card overflow-hidden #{classes}" : classes
      end

      def icon_tile_classes = helpers.attribute_group_color_classes(@color, variant: :soft)

      def attribute_label(field)
        field["display_label"].presence || field["name"].presence || field["name_slug"].to_s
      end

      def attribute_value(field) = display.text(entry, field["name_slug"])
      def attribute_files(field) = display.files(entry, field["name_slug"])
      def blank_value?(value) = value == t("common.labels.em_dash")

      def full_width?(field) = FULL_WIDTH_TYPES.include?(field["html_type"].to_s)

      def field_classes(field)
        full_width?(field) ? "min-w-0 py-3" : "min-w-0 py-3 sm:grid sm:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] sm:gap-6"
      end

      def value_classes(field) = full_width?(field) ? "mt-1.5" : "mt-1 sm:mt-0"

      def linked_value(field, value)
        case field["html_type"].to_s
        when "email" then helpers.mail_to(value, value, class: VALUE_LINK_CLASSES)
        when "tel"
          link_to(value, "tel:#{value.gsub(/[^\d+]/, '')}", class: VALUE_LINK_CLASSES) if value.match?(/\d/)
        when "url"
          link_to(value, value, class: VALUE_LINK_CLASSES, target: "_blank", rel: "noopener noreferrer") if value.match?(WEB_ADDRESS)
        end
      end
    end
  end
end
