# frozen_string_literal: true

module Admin
  # Shared admin list pagination footer. Used by AdminTableComponent and other
  # admin list surfaces so page chrome stays consistent.
  #
  # +pagination+ is the ModuleEntriesResolver hash:
  #   { page:, per_page:, total:, total_pages: }
  # +page_path+ is a callable that receives a page number and returns an href.
  #
  # Opt-in extras for the richer data-table lists:
  # +summary+          — show the "Showing 1–10 of 57" range (and keep the footer
  #                      on single-page lists so the count is always visible)
  # +per_page_options+ — e.g. [10, 25, 50, 100]; requires +per_page_path+, a
  #                      callable that receives a page size and returns an href
  class PaginationComponent < ApplicationComponent
    WINDOW = 1

    attr_reader :pagination, :page_path, :turbo_frame, :per_page_options, :per_page_path

    def initialize(pagination:, page_path:, turbo_frame: nil, summary: false,
                   per_page_options: nil, per_page_path: nil)
      @pagination       = pagination || {}
      @page_path        = page_path
      @turbo_frame      = turbo_frame
      @summary          = summary
      @per_page_options = Array(per_page_options).map(&:to_i).select(&:positive?)
      @per_page_path    = per_page_path
    end

    def render?
      total_pages > 1 || (summary? && total.positive?)
    end

    def summary? = @summary

    def page
      (pagination[:page].presence || 1).to_i
    end

    def total_pages
      (pagination[:total_pages] || 0).to_i
    end

    def total
      pagination[:total].to_i
    end

    def per_page
      pagination[:per_page].to_i
    end

    def multi_page? = total_pages > 1

    def show_previous?
      page > 1
    end

    def show_next?
      page < total_pages
    end

    def previous_href
      page_path.call(page - 1)
    end

    def next_href
      page_path.call(page + 1)
    end

    def page_href(number)
      page_path.call(number)
    end

    def summary_text
      if multi_page?
        from = ((page - 1) * per_page) + 1
        to   = [page * per_page, total].min
        t("chrome.admin_table.showing_range", from: from, to: to, total: total)
      else
        t("chrome.admin_table.result_count", count: total)
      end
    end

    # Page numbers with :gap markers, e.g. [1, :gap, 4, 5, 6, :gap, 12].
    def page_window
      return (1..total_pages).to_a if total_pages <= 5 + (WINDOW * 2)

      inner = ((page - WINDOW)..(page + WINDOW)).select { |n| n > 1 && n < total_pages }
      numbers = [1, *inner, total_pages]
      numbers.each_with_object([]) do |n, out|
        out << :gap if out.any? && n - out.last.to_i > 1
        out << n
      end
    end

    def per_page_menu?
      per_page_options.any? && per_page_path.respond_to?(:call) &&
        (multi_page? || total > per_page_options.min)
    end

    def per_page_href(size)
      per_page_path.call(size)
    end

    def link_data
      data = { turbo_action: "advance" }
      data[:turbo_frame] = turbo_frame if turbo_frame.present?
      data
    end
  end
end
