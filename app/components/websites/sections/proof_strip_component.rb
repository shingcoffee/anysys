# frozen_string_literal: true

module Websites
  module Sections
    class ProofStripComponent < Websites::SectionComponent
      def items
        list("items")
      end

      def grid_class
        case items.size
        when 4 then "grid grid-cols-2 md:grid-cols-4"
        when 5 then "grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5"
        else "grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6"
        end
      end

      def strip_padding
        theme.density == "compact" ? "py-8 md:py-12" : "py-12 md:py-16"
      end
    end
  end
end
