# frozen_string_literal: true

module Websites
  module Sections
    # One oversized sentence and a short gloss (Pentagram / Kinfolk openers).
    class StatementComponent < Websites::SectionComponent
      def paragraphs
        prop("body").split(/\n{2,}/).map(&:strip).reject(&:blank?)
      end
    end
  end
end
