# frozen_string_literal: true

module Websites
  module Sections
    class FaqComponent < Websites::SectionComponent
      def items
        list("items")
      end
    end
  end
end
