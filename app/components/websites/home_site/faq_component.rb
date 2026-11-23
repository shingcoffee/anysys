# frozen_string_literal: true

module Websites
  module HomeSite
    class FaqComponent < SectionComponent
      def items = list("items").select { |item| present_text?(item["question"]) }
      def section_class = page_role == :pricing ? "bg-slate-50" : "bg-white"
    end
  end
end
