# frozen_string_literal: true

module Admin
  module Pages
    # Lists every visible audience with a Distribution-colored dot + label.
    # Only audiences that can open the page are shown (no empty grey slots).
    class AudienceReachComponent < ViewComponent::Base
      DOT_ON = {
        "admin"  => "bg-accent",
        "member" => "bg-member-accent",
        "public" => "bg-success"
      }.freeze

      def initialize(page:)
        @page = page
      end

      def render?
        page.present?
      end

      def items
        page.visible_audiences.map do |key|
          {
            key:   key,
            label: I18n.t("common.visibility.#{key}"),
            dot:   DOT_ON.fetch(key, "bg-border-subtle")
          }
        end
      end

      def empty?
        items.empty?
      end

      def aria_label
        return I18n.t("admin_misc.pages.audience.aria_unknown") if empty?

        names = items.map { |i| i[:label] }
        I18n.t("admin_misc.pages.audience.aria_visible_to", audiences: names.to_sentence)
      end

      private

      attr_reader :page
    end
  end
end
