# frozen_string_literal: true

module Admin
  # Desktop sidebar jump list over a detail page's main-column cards, shared by
  # the entry and user detail pages. Items are `{ id:, label:, dot:, count: }`;
  # +link_action+ is a Stimulus action each link also triggers (e.g. opening a
  # collapsed card before jumping to it).
  class SectionIndexComponent < ApplicationComponent
    attr_reader :items, :id_prefix, :link_action

    def initialize(items:, id_prefix:, link_action: nil)
      @items = items
      @id_prefix = id_prefix
      @link_action = link_action
    end

    def heading_id = "#{id_prefix}-sections-heading"
    def dot_class(item) = item[:dot].presence || "bg-border-strong"
  end
end
