# frozen_string_literal: true

module Admin
  module Pages
    # Forms list: audience reach meter, Live/Draft status pill, and a row
    # menu. Clicking a row (or its name) opens maintenance preview in a new
    # tab. `show_entity` adds each form's entity under its name, for lists
    # that span entities. Parallel to Entities::EntriesTableComponent without
    # stretching the shared AdminTableComponent.
    class OpsTableComponent < ApplicationComponent
      FRAME_ID = "pages-ops-table"
      PUBLISHING_FRAME = PublishingPanelComponent::FRAME_ID
      PER_PAGE_OPTIONS = [10, 25, 50, 100].freeze
      FORM_ICON = "M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"
      ENTITY_ICON = "M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 5.625c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"
      NEW_TAB_ICON = "M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25"
      # [sort key, label key, width/visibility classes shared by <th> and <td>].
      # Secondary columns drop out on narrower screens; Form takes the rest.
      SORT_COLUMNS = [
        [:name, "admin_misc.domains.pages.column", ""],
        [:visibility, "common.labels.visibility", "hidden md:table-cell md:w-44 xl:w-56"],
        [:launched, "common.labels.status", "w-28"],
        [:updated_at, "common.labels.updated_at", "hidden lg:table-cell lg:w-40"]
      ].freeze

      attr_reader :rows, :pagination, :params, :filters, :search,
                  :empty_state, :base_path, :customer_id, :frame_id

      def initialize(rows:, pagination:, params:, customer_id:,
                     base_path:, show_entity: true,
                     filters: [], search: nil, empty_state: nil,
                     frame_id: FRAME_ID,
                     statuses: {})
        @rows           = Array(rows)
        @pagination     = pagination || {}
        @params         = symbolize_params(params)
        @customer_id    = customer_id
        @base_path      = base_path.to_s
        @show_entity    = show_entity
        @filters        = Array(filters)
        @search         = search
        @empty_state    = empty_state
        @frame_id       = frame_id
        @statuses       = statuses || {}
      end

      # Badge status for a row (Pages::FormHealth), or nil.
      def form_status(page)
        @statuses[page.id]
      end

      def show_entity? = @show_entity

      def entity_subtitle(page)
        return nil unless show_entity?

        (page.respond_to?(:entity) && page.entity&.display_label.presence) ||
          page.metadata["entity_name"].presence ||
          I18n.t("admin_misc.pages.uncategorized.row_subtitle")
      end

      # Comma-joined audience labels for the visibility cell's overflow tooltip.
      # The cell already renders dots + labels via AudienceReachComponent; this
      # only supplies the plain-text full text for the tooltip (shown when the
      # cell is too narrow and the content is truncated).
      def audience_tooltip(page)
        page.visible_audiences.map { |key| I18n.t("common.visibility.#{key}") }.join(", ")
      end

      def manage_path(page)
        helpers.admin_page_path(customer_id, page)
      end

      def preview_path(page)
        helpers.admin_maintenance_page_preview_path(customer_id, page)
      end

      def preview_link_attributes
        { target: "_blank", rel: "noopener noreferrer", data: { turbo_frame: "_top" } }
      end

      def name_link(page, classes)
        link_to page.name, preview_path(page), class: classes,
                **preview_link_attributes.merge(
                  aria: { label: t("admin_misc.pages.preview_hint", name: page.name) },
                  data: preview_link_attributes[:data].merge(
                    row_link_primary: true, tooltip: page.name, tooltip_overflow: "true"
                  )
                )
      end

      def icon_svg(path, classes)
        tag.svg(class: "#{classes} shrink-0", fill: "none", viewBox: "0 0 24 24", stroke: "currentColor",
                "stroke-width": 1.75, "aria-hidden": true) do
          tag.path(d: path, "stroke-linecap": "round", "stroke-linejoin": "round")
        end
      end

      def form_tile_classes(page)
        page.launched? ? "bg-accent-subtle text-accent" : "bg-surface-active text-text-muted"
      end

      def launch_path(page)
        helpers.admin_maintenance_page_launch_path(
          customer_id, page, return_to: return_to_path
        )
      end

      def return_to_path
        query = params.except(:page).compact_blank
        query.any? ? "#{base_path}?#{query.to_query}" : base_path
      end

      def sort_headers
        SORT_COLUMNS.map do |key, label_key, classes|
          active    = params[:sort].to_s == key.to_s
          direction = (params[:dir] == "desc" ? "desc" : "asc") if active
          {
            label:     t(label_key),
            href:      query_link(sort: key, dir: direction == "asc" ? "desc" : "asc", page: nil),
            direction: direction,
            classes:   classes
          }
        end
      end

      def column_classes(key)
        SORT_COLUMNS.find { |column, _label, _classes| column == key }.last
      end

      def page_link(page_num)
        query_link(page: page_num)
      end

      def per_page_link(size)
        query_link(per_page: size, page: nil)
      end

      def clear_search_path
        param = search&.dig(:param) || :q
        query_link(param => nil, page: nil)
      end

      def query_link(overrides = {})
        query = params.merge(overrides).compact_blank
        query.any? ? "#{base_path}?#{query.to_query}" : base_path
      end

      def status_pill_classes(page)
        if page.launched?
          "bg-success-subtle text-success ring-success/20"
        else
          "bg-surface-active text-text-secondary ring-border"
        end
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

      def relative_updated(page)
        value = page.updated_at
        return nil unless value.respond_to?(:strftime)

        distance = helpers.time_ago_in_words(value)
        future   = value.to_time > Time.current
        text = I18n.t("chrome.admin_table.#{future ? 'time_in' : 'time_ago'}", time: distance)
        {
          text:  text,
          exact: I18n.l(value, format: :long),
          iso:   (value.iso8601 if value.respond_to?(:iso8601))
        }
      end

      private

      def symbolize_params(p)
        if p.respond_to?(:to_unsafe_h)
          p.to_unsafe_h.symbolize_keys
        else
          (p || {}).symbolize_keys
        end
      end
    end
  end
end
