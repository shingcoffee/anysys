# frozen_string_literal: true

module Websites
  module Sections
    class CtaBandComponent < Websites::SectionComponent
      def glow_class
        theme.accent == "ink" && theme.dark? ? "bg-neutral-300" : Websites::Theme.new(theme.tokens.merge("appearance" => "light")).glow_class
      end
    end
  end
end
