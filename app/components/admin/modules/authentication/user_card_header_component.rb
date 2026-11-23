# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      # Card header shared by the user detail sections: tinted icon tile,
      # heading, optional description, and a trailing meta line. A collapsible
      # header is the <summary> of a `group/section` <details>, so the body
      # owns the divider and only shows it while open. +action_space+ keeps the
      # trailing edge clear for a header action placed over it, since a link
      # nested in a <summary> would be interactive content inside a button.
      class UserCardHeaderComponent < ApplicationComponent
        LEVELS = %i[h2 h3].freeze
        BASE_CLASSES = "flex items-start gap-3 px-4 py-3.5 sm:px-6"
        STATIC_CLASSES = "border-b border-border-subtle"
        SUMMARY_CLASSES = "cursor-pointer list-none transition-base hover:bg-surface-hover " \
                          "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent " \
                          "[&::-webkit-details-marker]:hidden"
        ACTION_SPACE_CLASSES = "pr-16 sm:pr-36"

        attr_reader :heading_id, :title, :icon_path, :tile_class, :meta, :description

        def initialize(heading_id:, title:, icon_path:, tile_class:, meta: nil, description: nil, level: :h2,
                       collapsible: false, action_space: false)
          @heading_id = heading_id
          @title = title
          @icon_path = icon_path
          @tile_class = tile_class
          @meta = meta
          @description = description
          @level = LEVELS.include?(level) ? level : :h2
          @collapsible = collapsible
          @action_space = action_space
        end

        def heading_tag = @level
        def collapsible? = @collapsible
        def root_tag = collapsible? ? :summary : :header

        def root_classes
          [BASE_CLASSES, collapsible? ? SUMMARY_CLASSES : STATIC_CLASSES, (ACTION_SPACE_CLASSES if @action_space)].compact.join(" ")
        end
      end
    end
  end
end
