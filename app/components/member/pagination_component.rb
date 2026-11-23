# frozen_string_literal: true

module Member
  # Themed prev/next pagination bar. All page math comes from the wrapped
  # Pagy object; this component only owns the member-facing markup.
  class PaginationComponent < ApplicationComponent
    include UsesSiteChrome

    def initialize(pagy:, base_path:)
      @pagy      = pagy
      @base_path = base_path
    end

    attr_reader :pagy, :base_path

    delegate :from, :to, to: :pagy

    def render?
      pagy.pages > 1
    end

    def total_count
      pagy.count
    end

    def previous_path
      page_path(pagy.prev)
    end

    def next_path
      page_path(pagy.next)
    end

    def show_previous?
      pagy.prev.present?
    end

    def show_next?
      pagy.next.present?
    end

    private

    def page_path(target_page)
      separator = base_path.include?("?") ? "&" : "?"
      "#{base_path}#{separator}page=#{target_page}"
    end
  end
end
