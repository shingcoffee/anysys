# frozen_string_literal: true

module Admin
  module Pages
    # The card a launched page's form fills on an admin dashboard page (the
    # block is the rendered page), followed by the first "+ Add New" dialog
    # its entity-backed dropdowns open. Without a rendered page it shows the
    # +empty_title+ / +empty_description+ empty state instead.
    class FormPanelComponent < ApplicationComponent
      attr_reader :empty_title, :empty_description

      def initialize(empty_title: nil, empty_description: nil)
        @empty_title = empty_title
        @empty_description = empty_description
      end

      def page? = content.present?
    end
  end
end
