# frozen_string_literal: true

module Billing
  module Admin
    class HistoryFiltersComponent < ApplicationComponent
      # compact: single-row toolbar with visually hidden labels, for embedding
      # in a card header (customer settings). Default keeps the stacked form.
      def initialize(action:, filters:, query_key:, statuses:, status_prefix:, tenant_filter:, compact: false)
        @action, @query_key, @statuses, @status_prefix, @tenant_filter = action, query_key, statuses, status_prefix, tenant_filter
        @filters = (filters || {}).to_h.symbolize_keys
        @compact = compact
      end

      attr_reader :action, :filters, :query_key, :statuses, :status_prefix, :tenant_filter

      def compact? = @compact

      def label_class
        compact? ? visually_hidden_class : "form-label"
      end
    end
  end
end
