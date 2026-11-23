# frozen_string_literal: true

module Admin
  module Dashboard
    # Compact recents card on Admin Home (pages or entities). Empty state stays
    # inside the card — never the default py-16 EmptyStateComponent.
    class RecentListComponent < ApplicationComponent
      attr_reader :title, :view_all_href, :view_all_label, :empty_title,
                  :empty_description, :empty_cta_label, :empty_cta_href, :kind

      def initialize(title:, view_all_href:, view_all_label:, items:, empty_title:,
                     empty_description:, empty_cta_label:, empty_cta_href:, kind:)
        @title = title
        @view_all_href = view_all_href
        @view_all_label = view_all_label
        @items = Array(items)
        @empty_title = empty_title
        @empty_description = empty_description
        @empty_cta_label = empty_cta_label
        @empty_cta_href = empty_cta_href
        @kind = kind.to_sym
      end

      def items
        @items
      end

      def heading_id
        "dashboard-recents-#{kind}-title"
      end

      def item_name(item)
        read_attr(item, :name)
      end

      def item_href(item)
        read_attr(item, :href)
      end

      def item_badge(item)
        read_attr(item, :badge)&.to_s&.presence
      end

      def live_badge?(item)
        item_badge(item) == "live"
      end

      def draft_badge?(item)
        item_badge(item) == "draft"
      end

      def item_icon
        ::Dashboard::Home::METRIC_ICONS.fetch(kind.to_s, ::Dashboard::Home::METRIC_ICONS.fetch("pages"))
      end

      def header_icon_classes
        case kind
        when :entities
          "bg-accent-subtle text-accent ring-1 ring-inset ring-accent-muted/70"
        else
          "bg-info-subtle text-info ring-1 ring-inset ring-sky-200/80"
        end
      end

      def row_icon_classes
        case kind
        when :entities
          "bg-canvas-elevated text-text-secondary ring-1 ring-inset ring-border-subtle group-hover:bg-accent-subtle group-hover:text-accent group-hover:ring-accent-muted"
        else
          "bg-canvas-elevated text-text-secondary ring-1 ring-inset ring-border-subtle group-hover:bg-info-subtle group-hover:text-info group-hover:ring-sky-200"
        end
      end

      def stretch_rows?
        items.size >= 4
      end

      def item_updated_label(item)
        time = read_attr(item, :updated_at)
        return if time.nil?

        I18n.t(
          "admin_misc.domains.directory.updated",
          time: I18n.t("chrome.admin_table.time_ago", time: helpers.time_ago_in_words(time))
        )
      end

      private

      def read_attr(obj, name)
        return if obj.nil?
        return obj[name] || obj[name.to_s] if obj.is_a?(Hash)

        obj.public_send(name) if obj.respond_to?(name)
      end
    end
  end
end
