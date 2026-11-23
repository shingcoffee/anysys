# frozen_string_literal: true

module PageBuilder
  class PageTabsComponent < ApplicationComponent
    include ComponentClasses

    def initialize(pages:, active_page_id:)
      @pages = pages || []
      @active_page_id = active_page_id
    end

    private

    attr_reader :pages, :active_page_id

    def sorted_pages
      pages.sort_by { |p| p["order"] || 0 }
    end

    def active?(page_data)
      page_data["id"] == active_page_id
    end

    def show_delete_button?
      pages.size > 1
    end
  end
end
