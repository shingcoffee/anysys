# frozen_string_literal: true

module Admin
  # Column-header link that toggles a list's sort. Shows the direction arrow on
  # the active column and a faint up/down hint on hover elsewhere. The caller
  # owns the <th> (and its aria-sort) and builds the href.
  class SortableHeaderComponent < ApplicationComponent
    attr_reader :label, :href, :direction, :frame_id

    def initialize(label:, href:, direction: nil, frame_id: nil, align: :left)
      @label     = label
      @href      = href
      @direction = direction.presence&.to_s
      @frame_id  = frame_id
      @align     = align
    end

    def self.aria_sort(direction)
      { "asc" => "ascending", "desc" => "descending" }[direction.to_s]
    end

    def active? = direction.present?

    def link_classes
      justify = { right: "justify-end", center: "justify-center" }.fetch(@align, "")
      "group/sort inline-flex items-center gap-1 #{justify} transition-base hover:text-text-primary #{'text-text-primary' if active?}"
    end

    def icon_classes
      active? ? "text-text-primary" : "text-text-tertiary opacity-0 group-hover/sort:opacity-100"
    end

    def icon_path
      case direction
      when "asc"  then "M12 19V5m-6 6l6-6 6 6"
      when "desc" then "M12 5v14m6-6l-6 6-6-6"
      else             "M8 9l4-4 4 4m0 6l-4 4-4-4"
      end
    end

    def link_data
      frame_id ? { turbo_frame: frame_id, turbo_action: "advance" } : {}
    end
  end
end
