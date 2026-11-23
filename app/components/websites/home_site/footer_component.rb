# frozen_string_literal: true

module Websites
  module HomeSite
    class FooterComponent < Websites::FooterComponent
      def inner_measure_class = SectionComponent::CONTAINER
      def link_class
        "inline-flex min-h-11 min-w-11 max-w-full items-center rounded-sm text-[15px] leading-6 text-slate-300 transition-colors hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950"
      end
    end
  end
end
