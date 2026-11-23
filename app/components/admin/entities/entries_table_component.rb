# frozen_string_literal: true

module Admin
  module Entities
    # Bespoke admin entity-entry list table with batch selection, detail-page
    # links, and per-entity column rendering. Composed from the same visual
    # primitives as AdminTableComponent without modifying that shared component.
    #
    # The whole row opens the entry detail page; +toolbar_actions+ renders on
    # the right of the shared toolbar next to the density toggle.
    class EntriesTableComponent < ApplicationComponent
      TYPES = AdminTableComponent::TYPES
      NUMERIC_TYPES = AdminTableComponent::NUMERIC_TYPES
      PER_PAGE_OPTIONS = [10, 25, 50, 100].freeze
      DENSITIES = %w[comfortable compact].freeze
      MOBILE_META_LIMIT = 3

      renders_one :toolbar_actions

      attr_reader :rows, :columns, :pagination, :params,
                  :search, :filters, :empty_state, :frame_id, :base_path,
                  :batch_path, :entry_path, :edit_path, :destroy_path, :density

      def initialize(rows:, columns:, pagination:, params:,
                     filters: [], search: nil, empty_state: nil,
                     base_path:, batch_path:, entry_path:, destroy_path:, edit_path: nil,
                     density: "comfortable", frame_id: "entity-entries-table")
        @rows         = Array(rows)
        @columns      = columns.map { |c| normalize_column(c) }
        @pagination   = pagination || {}
        @params       = symbolize_params(params)
        @filters      = Array(filters)
        @search       = search
        @empty_state  = empty_state
        @base_path    = base_path.to_s
        @batch_path   = batch_path.to_s
        @entry_path   = entry_path
        @edit_path    = edit_path
        @destroy_path = destroy_path
        @density      = density.to_s == "compact" ? "compact" : "comfortable"
        @frame_id     = frame_id
      end

      def compact? = density == "compact"

      def cell_padding_class
        compact? ? "py-2" : "py-3"
      end

      def frame_data
        { turbo_frame: frame_id, turbo_action: "advance" }
      end

      def sort_link_for(column)
        return nil unless column[:sortable]

        active    = params[:sort].to_s == column[:key].to_s
        direction = (params[:dir] == "desc" ? "desc" : "asc") if active
        next_dir  = direction == "asc" ? "desc" : "asc"

        { href: query_link(sort: column[:key], dir: next_dir, page: nil), active: active, direction: direction }
      end

      def page_link(page_num)
        query_link(page: page_num)
      end

      def per_page_link(size)
        query_link(per_page: size, page: nil)
      end

      def density_link(value)
        query_link(density: value)
      end

      def query_link(overrides = {})
        query = params.merge(overrides).compact_blank
        query.any? ? "#{base_path}?#{query.to_query}" : base_path
      end

      def clear_search_path
        param = search&.dig(:param) || :q
        query_link(param => nil, page: nil)
      end

      def cell_value(row, column)
        if column[:cell].respond_to?(:call)
          column[:cell].call(row)
        else
          row.public_send(column[:key])
        end
      end

      def blank_cell?(value)
        value.nil? || value == "" || value == t("common.labels.em_dash")
      end

      def cell_text(row, column)
        value = cell_value(row, column)
        return t("common.labels.em_dash") if blank_cell?(value)

        case column[:type]
        when :datetime
          format_datetime(value)
        when :date
          format_date(value)
        when :truncate
          helpers.truncate(value.to_s, length: column[:truncate] || 60)
        when :boolean
          value ? I18n.t("common.labels.yes") : I18n.t("common.labels.no")
        else
          value.to_s
        end
      end

      # Badge, <time> or truncated text (with overflow tooltip) for one cell.
      def cell_content(row, column)
        if (badge = badge_for(row, column))
          render(BadgeComponent.new(variant: badge[:variant], size: :sm).with_content(badge[:label]))
        elsif (dt = datetime_cell(row, column))
          tag.time(dt[:text], datetime: dt[:iso], title: dt[:exact], class: "whitespace-nowrap")
        elsif blank_cell?(cell_value(row, column))
          tag.span(t("common.labels.em_dash"), class: "text-text-tertiary")
        else
          text = cell_text(row, column)
          tag.span(text, class: "block truncate text-center", data: { tooltip: text, tooltip_overflow: "true" })
        end
      end

      def badge_for(row, column)
        return nil unless column[:type] == :badge && column[:badge].respond_to?(:call)

        column[:badge].call(row)
      end

      def numeric_class(column)
        NUMERIC_TYPES.include?(column[:type]) ? "tabular-nums" : ""
      end

      def datetime_cell(row, column)
        return nil unless NUMERIC_TYPES.include?(column[:type]) && column[:type] != :number

        value = cell_value(row, column)
        return nil unless value.respond_to?(:strftime)

        exact = column[:type] == :date ? format_date(value) : format_datetime(value)
        {
          text:  column[:relative] ? relative_time(value) : exact,
          exact: exact,
          iso:   (value.iso8601 if value.respond_to?(:iso8601))
        }
      end

      def relative_time(value)
        distance = helpers.time_ago_in_words(value)
        future   = value.to_time > Time.current
        I18n.t("chrome.admin_table.#{future ? 'time_in' : 'time_ago'}", time: distance)
      end

      def id_column?(column)
        column[:key].to_sym == :id
      end

      # The ID cell is the visible entry link. Without an ID column the first
      # cell keeps that role so the row still has one primary link.
      def entry_link?(column, index)
        return true if id_column?(column)

        index.zero? && visible_columns.none? { |col| id_column?(col) }
      end

      # A column with +href:+ links its cell somewhere other than the entry.
      def cell_href(row, column)
        column[:href]&.call(row)
      end

      def width_class(column)
        column[:width].to_s
      end

      def empty_after_search?
        rows.empty? && (active_search? || active_filters?)
      end

      def active_search?
        !search.nil? && params[search[:param]].to_s.present?
      end

      def active_filters?
        filters.any? { |f| params[f[:key]].to_s.present? }
      end

      def visible_columns
        columns.reject { |col| col[:display] == false }
      end

      def primary_column
        visible_columns.first
      end

      # Mobile cards lead with the first descriptive field rather than the ID.
      def mobile_title_column
        visible_columns.find { |col| col[:key] != :id } || primary_column
      end

      def mobile_meta_columns
        visible_columns.reject { |col| col == mobile_title_column || col[:key] == :id }
                       .first(MOBILE_META_LIMIT)
      end

      def entry_href(row)
        entry_path.call(row)
      end

      # nil without an edit_path: the entity takes no edits (inactive or bridge).
      def edit_href(row)
        edit_path&.call(row)
      end

      def destroy_href(row)
        destroy_path.call(row)
      end

      private

      def normalize_column(col)
        type       = col[:type] || :text
        sortable   = col.key?(:sortable) ? col[:sortable] : true
        searchable = col.key?(:searchable) ? col[:searchable] : (type == :text)
        col.merge(type: type, sortable: sortable, searchable: searchable)
      end

      def symbolize_params(p)
        if p.respond_to?(:to_unsafe_h)
          p.to_unsafe_h.symbolize_keys
        else
          (p || {}).symbolize_keys
        end
      end

      def format_datetime(value)
        return t("common.labels.em_dash") if value.blank?

        value.respond_to?(:strftime) ? I18n.l(value, format: :long) : value.to_s
      end

      def format_date(value)
        return t("common.labels.em_dash") if value.blank?

        value.respond_to?(:strftime) ? I18n.l(value.to_date, format: :long) : value.to_s
      end
    end
  end
end
