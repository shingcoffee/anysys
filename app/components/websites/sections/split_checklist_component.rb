# frozen_string_literal: true

module Websites
  module Sections
    # Pitch on the left, checked reasons on the right (Mailchimp / Shopify).
    class SplitChecklistComponent < Websites::SectionComponent
      def items
        list("items").select { |item| present_text?(item["title"]) || present_text?(item["body"]) }
      end

      def button_href
        resolved_href("button_href")
      end

      def check_wrap_class
        "mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full #{theme.accent_soft_class}"
      end
    end
  end
end
