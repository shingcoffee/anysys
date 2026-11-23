# frozen_string_literal: true

module Billing
  module Admin
    # Progressive-enhancement disclosure for secondary billing sections.
    # The panel is never `hidden` in SSR so no-JS / Capybara can read it;
    # billing-disclosure applies visibility after connect.
    class DisclosureComponent < ApplicationComponent
      HEADING_TAGS = %i[h2 h3 h4].freeze

      renders_one :summary

      attr_reader :id, :title, :description, :open, :hashes, :flush, :heading_tag, :heading_class, :card, :bordered

      def initialize(id:, title:, description: nil, open: false, hashes: [], flush: false, heading_tag: :h2, heading_class: "section-header", card: true, bordered: true)
        @heading_tag = heading_tag.to_sym
        raise ArgumentError, "unsupported heading_tag: #{heading_tag.inspect}" unless HEADING_TAGS.include?(@heading_tag)

        @id = id
        @title = title
        @description = description
        @open = open
        @hashes = Array(hashes)
        @flush = flush
        @heading_class = heading_class
        @card = card
        @bordered = bordered
      end

      def wrapper_classes
        return "card min-w-0 overflow-hidden" if card

        bordered ? "min-w-0 overflow-hidden rounded-xl border border-border-subtle bg-surface" : "min-w-0"
      end

      def panel_id = "#{id}-panel"
    end
  end
end
