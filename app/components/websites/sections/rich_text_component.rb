# frozen_string_literal: true

module Websites
  module Sections
    class RichTextComponent < Websites::SectionComponent
      def paragraphs
        prop("body").split(/\n{2,}/).map(&:strip).reject(&:blank?)
      end
    end
  end
end
