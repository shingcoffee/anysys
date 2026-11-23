# frozen_string_literal: true

module Billing
  module Admin
    # Renders the bulk-edit form for platform countable items (Area d).
    #
    # Constructor:
    #   items:       Collection of Billing::CountableItem records
    #   customer_id: Platform owner customer_id for route helpers
    #
    # Items render as separate cards in position order. Each card keeps its
    # identity (key, order, enabled) in the header and its editable fields below.
    # The Stimulus controller `countable-items-reorder` manages drag-and-drop
    # and Up/Down button reordering, updating hidden position inputs in real time.
    #
    # Submitted field names per row (stable idx = render-time index in sorted order):
    #   items[<idx>][id]          — record id (hidden)
    #   items[<idx>][label]       — human-readable label text input
    #   items[<idx>][description] — longer description textarea
    #   items[<idx>][unit]        — unit string (e.g. "emails", "MB")
    #   items[<idx>][category]    — category select
    #   items[<idx>][period]      — period select (total | monthly)
    #   items[<idx>][enabled]     — enabled checkbox (with hidden false companion)
    #   items[<idx>][position]    — display-order hidden input (managed by Stimulus)
    class CountableItemsFormComponent < ApplicationComponent
      CATEGORY_OPTIONS = %w[Content Communications Commerce Platform Storage Support].freeze
      PERIOD_OPTIONS   = %w[total monthly].freeze

      def initialize(items:, customer_id:)
        @items       = items
        @customer_id = customer_id.to_s
      end

      attr_reader :customer_id

      def form_url
        helpers.admin_maintenance_platform_billing_countable_items_path(customer_id)
      end

      # Items sorted by position ascending for initial render.
      def sorted_items
        @sorted_items ||= @items.sort_by { |item| [item.position.to_i, item.key.to_s] }
      end

      # Stable per-record index in the sorted list for consistent field naming.
      def index_for(item)
        @index_map ||= sorted_items.each_with_index
                                   .each_with_object({}) { |(itm, idx), h| h[itm] = idx }
        @index_map[item]
      end

      def category_options
        CATEGORY_OPTIONS.map { |c| [category_label(c), c] }
      end

      def period_options
        PERIOD_OPTIONS.map { |p| [period_label(p), p] }
      end

      def category_label(category)
        t("comp_billing.countable_items_form.category.#{category.to_s.downcase}")
      end

      def period_label(period)
        t("comp_billing.countable_items_form.period.#{period}")
      end
    end
  end
end
