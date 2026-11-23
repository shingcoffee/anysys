# frozen_string_literal: true

module Websites
  module Admin
    # Catalog of marketing kit types. Each cell is an Add button with data-type
    # for website-builder#addSection. Types are grouped via SectionKit.groups.
    class KitPickerComponent < ApplicationComponent
      def initialize(types: Websites::SectionKit::TYPES)
        @types = Array(types).map(&:to_s)
      end

      attr_reader :types

      def grouped_types
        grouped = Websites::SectionKit.groups.transform_values { |list| list & types }
                                      .reject { |_key, list| list.empty? }
        leftover = types - grouped.values.flatten
        leftover.any? ? grouped.merge("more" => leftover) : grouped
      end

      def group_label(key)
        t("website.sections.groups.#{key}")
      end

      def type_name(type)
        key = "website.sections.#{type}.name"
        I18n.exists?(key) ? t(key) : type.to_s.humanize
      end

      def type_description(type)
        key = "website.sections.#{type}.description"
        I18n.exists?(key) ? t(key) : ""
      end
    end
  end
end
