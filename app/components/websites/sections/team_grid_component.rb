# frozen_string_literal: true

module Websites
  module Sections
    class TeamGridComponent < Websites::SectionComponent
      def people
        list("people")
      end
    end
  end
end
