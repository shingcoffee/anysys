# frozen_string_literal: true

module Websites
  module Admin
    # Recap of the chosen layout beside the new-page form. The server renders
    # the initial choice; website-layout-picker rewrites the same targets from
    # the checked card's data attributes.
    class LayoutSummaryComponent < ApplicationComponent
      def self.section_labels(layout)
        Array(layout.try(:sections)).filter_map do |section|
          type = section.respond_to?(:to_h) ? section.to_h.stringify_keys["type"].to_s : ""
          I18n.t("website.sections.#{type}.name") if Websites::SectionKit.known?(type)
        end
      end

      def self.sections_text(labels)
        Array(labels).join(" · ")
      end

      def self.count_label(labels)
        I18n.t("website.admin.pages.new.section_count", count: Array(labels).size)
      end

      def initialize(layout:)
        @layout = layout
      end

      def render?
        @layout.present?
      end

      def name
        @layout.display_name
      end

      def description
        @layout.display_description.to_s
      end

      def labels
        @labels ||= self.class.section_labels(@layout)
      end

      def count_label
        self.class.count_label(labels)
      end

      def sections_text
        self.class.sections_text(labels)
      end
    end
  end
end
