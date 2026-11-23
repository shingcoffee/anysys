# frozen_string_literal: true

module Admin
  # Header band for admin data-table lists: debounced search, single-value
  # filter selects, a Reset link when anything is narrowed, and an optional
  # +actions+ slot on the right (column picker, density toggle, …).
  #
  # Submits as GET into +frame_id+ so only the list re-renders; every current
  # query param except search, filters and page rides along as a hidden field.
  #
  # +filters+ entries: { key:, label:, options: [[label, value], …] }
  class ListToolbarComponent < ApplicationComponent
    renders_one :actions

    attr_reader :base_path, :frame_id, :params, :search, :filters, :html_data

    def initialize(base_path:, frame_id:, params:, search: nil, filters: [], data: {})
      @base_path = base_path.to_s
      @frame_id  = frame_id
      @params    = params.to_h.symbolize_keys
      @search    = search
      @filters   = Array(filters)
      @html_data = data
    end

    def search_param = search&.dig(:param) || :q

    def search_value = params[search_param].to_s

    def filter_value(filter) = params[filter[:key]].to_s

    def filter_active?(filter) = filter_value(filter).present?

    def narrowed?
      (search && search_value.present?) || filters.any? { |f| filter_active?(f) }
    end

    def hidden_params
      params.except(search_param, :page, *filter_keys).compact_blank
    end

    def reset_path
      query = hidden_params
      query.any? ? "#{base_path}?#{query.to_query}" : base_path
    end

    def frame_data
      { turbo_frame: frame_id, turbo_action: "advance" }
    end

    def filter_classes(filter)
      base = "input-field h-9 w-full sm:w-auto sm:max-w-52 appearance-none truncate py-0 pl-3 pr-8 text-sm cursor-pointer"
      if filter_active?(filter)
        "#{base} border-accent-muted bg-accent-subtle text-accent-text font-medium"
      else
        "#{base} border-dashed text-text-secondary"
      end
    end

    private

    def filter_keys = filters.map { |f| f[:key] }
  end
end
