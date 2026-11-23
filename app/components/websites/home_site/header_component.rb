# frozen_string_literal: true

module Websites
  module HomeSite
    class HeaderComponent < Websites::NavComponent
      include Navigation

      def header_bar_class = "h-auto min-[280px]:min-h-16 lg:min-h-[72px]"
    end
  end
end
