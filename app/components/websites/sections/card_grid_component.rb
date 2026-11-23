# frozen_string_literal: true

module Websites
  module Sections
    class CardGridComponent < Websites::SectionComponent
      def cards
        list("cards")
      end
    end
  end
end
